#!/usr/bin/env python3
# Champions ダメージ計算UI用の静的サーバ。
# python3 -m http.server と違い、アクセスログを一切出さない
# (UI が state.json を 0.5 秒ごとにポーリングするため、標準サーバだとログが溢れる)。
# サーバは即座に起動し、オンライン版ファイルへの同期は裏で走る
# (起動時 + 5 秒ごと)。同期が終わる前でも手元のファイルで画面は開ける。
# 同期でファイルが変わると ui_version.txt が更新され、開いている UI が自動で再読込する。
# 同期で serve.py 自身が更新された場合は、プロセスを自動で再起動して
# 新しいコードを読み直す (start_all.sh の再実行は不要)。
import base64
import functools
import hashlib
import http.server
import json
import os
import subprocess
import sys
import threading
import time
import urllib.error
import urllib.request
from datetime import datetime, timedelta, timezone


def run_sync(show_output, force=False):
    cmd = [sys.executable, "sync_ui.py"] + (["--force"] if force else [])
    try:
        if show_output:
            subprocess.run(cmd, timeout=120)
        else:
            subprocess.run(cmd, timeout=120, capture_output=True)
    except Exception:
        pass


SELF_PATH = os.path.abspath(__file__)


def self_hash():
    try:
        with open(SELF_PATH, "rb") as f:
            return hashlib.sha256(f.read()).hexdigest()
    except OSError:
        return None


START_HASH = self_hash()


def maybe_restart_self():
    # 同期で serve.py 自身が差し替わっていたら、新しいコードで起動し直す。
    # 起動時点のハッシュと比べるので、差し替えがなければ何も起きない。
    # exec で同じプロセスを置き換えるため、start_all.sh 側の管理
    # (バックグラウンド起動・終了時の trap) はそのまま効く。
    current = self_hash()
    if current is not None and START_HASH is not None and current != START_HASH:
        print("[sync] serve.py が更新されたため、サーバを自動で再起動します", flush=True)
        os.execv(sys.executable, [sys.executable, SELF_PATH] + sys.argv[1:])


def sync_loop():
    # 起動時の同期はサーバ開始をブロックしないよう、このスレッド側で行う。
    # 先にサーバを立ち上げてから同期するので、ブラウザがすぐ開ける。
    # スリープ復帰直後などで一時的に失敗しても、スレッドごと死なずに
    # 次の周期で再試行する (サーバ本体は動き続ける)。
    run_sync(True, force=True)
    try:
        maybe_restart_self()
    except Exception:
        print("[sync] serve.py の自動再起動に失敗しました。次回同期時に再試行します", flush=True)
    upload_logs_once()
    cycles = 0
    while True:
        time.sleep(5)
        run_sync(False)
        try:
            maybe_restart_self()
        except Exception:
            print("[sync] serve.py の自動再起動に失敗しました。次回同期時に再試行します", flush=True)
        cycles += 1
        if cycles % 12 == 0:   # 試合ログの送信チェックは約 60 秒ごと
            upload_logs_once()


# ---- 試合ログの自動送信 ----
# reader が試合ごとに logs/ へ保存した battle_*.log (人間可読ログ) と
# battle_*_protocol.log (プロトコルログ) を、team_key.txt で暗号化して
# GitHub リポジトリ (nMfM1Ow5ot/champions-calc) の logs_enc/ へ送る。
# リポジトリは公開のため、平文は置かず my_team.enc と同じ
# AES-256-CBC + PBKDF2 100k 回の暗号化を必須とする。
# 送信には Mac 側の github_log_token.txt (このリポジトリへの Contents
# 書き込み専用の fine-grained PAT) が必要。未設定の間はログは logs/ に
# 溜まり続け、設定後にまとめて送信される (試合ごとの送信キューを兼ねる)。
# 送信済みは logs/uploaded.json (ファイル名 -> 平文 SHA-256) で管理し、
# 受信側の目録として logs_enc/index.json を更新する。
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
LOG_DIR = os.path.join(BASE_DIR, "logs")
LOG_TOKEN_PATH = os.path.join(BASE_DIR, "github_log_token.txt")
LOG_KEY_PATH = os.path.join(BASE_DIR, "team_key.txt")
LOG_STATE_PATH = os.path.join(LOG_DIR, "uploaded.json")
GH_CONTENTS = "https://api.github.com/repos/nMfM1Ow5ot/champions-calc/contents/"
JST = timezone(timedelta(hours=9))
_log_notice_shown = False
_log_last_error = ""


def _log_token():
    try:
        with open(LOG_TOKEN_PATH) as f:
            return f.read().strip() or None
    except OSError:
        return None


def _encrypt_log(data):
    if not os.path.exists(LOG_KEY_PATH):
        return None
    p = subprocess.run(
        ["openssl", "enc", "-aes-256-cbc", "-pbkdf2", "-iter", "100000",
         "-a", "-salt", "-pass", f"file:{LOG_KEY_PATH}"],
        input=data, capture_output=True, timeout=20)
    if p.returncode != 0:
        return None
    return p.stdout


def _gh_request(method, path, token, payload=None):
    req = urllib.request.Request(GH_CONTENTS + path, method=method)
    req.add_header("Authorization", "Bearer " + token)
    req.add_header("Accept", "application/vnd.github+json")
    req.add_header("User-Agent", "champions-calc-log-upload")
    data = None
    if payload is not None:
        data = json.dumps(payload).encode()
        req.add_header("Content-Type", "application/json")
    with urllib.request.urlopen(req, data=data, timeout=30) as r:
        return json.loads(r.read().decode())


def _gh_get_file(path, token):
    try:
        r = _gh_request("GET", path + "?ref=main", token)
        return base64.b64decode(r["content"]), r["sha"]
    except urllib.error.HTTPError as e:
        if e.code == 404:
            return None, None
        raise


def _gh_put_file(path, content, token, message, sha=None):
    payload = {"message": message,
               "content": base64.b64encode(content).decode()}
    if sha:
        payload["sha"] = sha
    return _gh_request("PUT", path, token, payload)


def upload_logs_once():
    global _log_notice_shown, _log_last_error
    if not os.path.isdir(LOG_DIR):
        return
    names = sorted(n for n in os.listdir(LOG_DIR)
                   if n.startswith("battle_") and n.endswith(".log"))
    if not names:
        return
    state = {}
    if os.path.exists(LOG_STATE_PATH):
        try:
            state = json.loads(open(LOG_STATE_PATH).read())
        except Exception:
            state = {}
    pending = []
    for n in names:
        try:
            data = open(os.path.join(LOG_DIR, n), "rb").read()
        except OSError:
            continue
        h = hashlib.sha256(data).hexdigest()
        if state.get(n) != h:
            pending.append((n, data, h))
    if not pending:
        return
    token = _log_token()
    if not token:
        if not _log_notice_shown:
            print("[log] 試合ログの自動送信には github_log_token.txt の設定が必要です。"
                  "ログは logs/ に保存され続けます", flush=True)
            _log_notice_shown = True
        return
    try:
        index_bytes, index_sha = _gh_get_file("logs_enc/index.json", token)
        index = {"files": []}
        if index_bytes:
            try:
                index = json.loads(index_bytes.decode())
            except Exception:
                index = {"files": []}
        known = {e.get("name"): e.get("sha256") for e in index.get("files", [])}
        changed_index = False
        for n, data, h in pending:
            if known.get(n) == h:
                state[n] = h
                continue
            enc = _encrypt_log(data)
            if enc is None:
                raise RuntimeError("暗号化に失敗しました (team_key.txt を確認してください)")
            _, enc_sha = _gh_get_file("logs_enc/" + n + ".enc", token)
            _gh_put_file("logs_enc/" + n + ".enc", enc, token,
                         f"battle log {n}", sha=enc_sha)
            index["files"] = [e for e in index.get("files", [])
                              if e.get("name") != n]
            index["files"].append({
                "name": n, "sha256": h,
                "uploaded_at": datetime.now(JST).isoformat()})
            known[n] = h
            state[n] = h
            changed_index = True
            print(f"[log] 試合ログを送信しました: {n}", flush=True)
        if changed_index:
            index["files"].sort(key=lambda e: e["name"])
            _gh_put_file("logs_enc/index.json",
                         json.dumps(index, ensure_ascii=False, indent=1).encode(),
                         token, "update battle log index", sha=index_sha)
        with open(LOG_STATE_PATH, "w") as f:
            json.dump(state, f)
        _log_last_error = ""
    except Exception as e:
        msg = f"[log] 試合ログの送信に失敗しました (次回再試行します): {e}"
        if msg != _log_last_error:
            print(msg, flush=True)
            _log_last_error = msg


def check_log_token():
    """起動時に github_log_token.txt の所在を確認する (2026-11-20 ユーザー指示)。
    無くても起動は続けるが、試合ログの自動送信だけが無効になる旨を明示する。"""
    try:
        ok = os.path.isfile(LOG_TOKEN_PATH) and os.path.getsize(LOG_TOKEN_PATH) > 0
    except OSError:
        ok = False
    if ok:
        print("[log] github_log_token.txt を確認しました (試合ログの自動送信: 有効)", flush=True)
    else:
        print("[log] github_log_token.txt が見つかりません。試合ログの自動送信は無効です "
              "(対戦・計算には影響しません)。使う場合はこのフォルダに置いてください", flush=True)


class QuietHandler(http.server.SimpleHTTPRequestHandler):
    def log_message(self, format, *args):
        pass

    def end_headers(self):
        self.send_header("Cache-Control", "no-store")
        super().end_headers()


if __name__ == "__main__":
    check_log_token()
    threading.Thread(target=sync_loop, daemon=True).start()
    handler = functools.partial(QuietHandler, directory=".")
    try:
        server = http.server.ThreadingHTTPServer(("127.0.0.1", 8765), handler)
    except OSError:
        print("ポート 8765 は使用中です。別のターミナルで旧サーバが動いています。")
        print("そのターミナルで Ctrl+C を押して止めてから、もう一度実行してください。")
        print("見つからない場合は次のコマンドで止められます: lsof -ti tcp:8765 | xargs kill")
        raise SystemExit(1)
    with server as httpd:
        httpd.serve_forever()
