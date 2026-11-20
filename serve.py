#!/usr/bin/env python3
# Champions ダメージ計算UI用の静的サーバ。
# python3 -m http.server と違い、アクセスログを一切出さない
# (UI が state.json を 0.5 秒ごとにポーリングするため、標準サーバだとログが溢れる)。
# サーバは即座に起動し、オンライン版ファイルへの同期は裏で走る
# (起動時 + 5 秒ごと)。同期が終わる前でも手元のファイルで画面は開ける。
# 同期でファイルが変わると ui_version.txt が更新され、開いている UI が自動で再読込する。
# 同期で serve.py 自身が更新された場合は、プロセスを自動で再起動して
# 新しいコードを読み直す (start_all.sh の再実行は不要)。
import functools
import hashlib
import http.server
import os
import subprocess
import sys
import threading
import time


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
    while True:
        time.sleep(5)
        run_sync(False)
        try:
            maybe_restart_self()
        except Exception:
            print("[sync] serve.py の自動再起動に失敗しました。次回同期時に再試行します", flush=True)


class QuietHandler(http.server.SimpleHTTPRequestHandler):
    def log_message(self, format, *args):
        pass

    def end_headers(self):
        self.send_header("Cache-Control", "no-store")
        super().end_headers()


if __name__ == "__main__":
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
