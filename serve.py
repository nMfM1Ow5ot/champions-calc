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
import re
import signal
import subprocess
import sys
import threading
import traceback
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
    # 予期しない例外でスレッドが無言で死ぬと、サーバが生きているのに
    # 送信だけが止まり続ける (2026-11-21 の送信停止の候補)。周期の
    # 処理全体を囲み、異常はクラッシュジャーナルへ残して継続する
    try:
        run_sync(True, force=True)
    except Exception as e:
        _record_crash("sync_startup", e)
    try:
        maybe_restart_self()
    except Exception:
        print("[sync] serve.py の自動再起動に失敗しました。次回同期時に再試行します", flush=True)
    upload_logs_once()
    cycles = 0
    while True:
        time.sleep(5)
        try:
            run_sync(False)
            try:
                maybe_restart_self()
            except Exception:
                print("[sync] serve.py の自動再起動に失敗しました。次回同期時に再試行します", flush=True)
            cycles += 1
            if cycles % 6 == 0:   # 試合ログの送信チェックは約 30 秒ごと
                upload_logs_once()
        except Exception as e:
            _record_crash("sync_loop", e)
            time.sleep(2)


# ---- 試合ログの自動送信 ----
# reader が試合ごとに logs/ へ保存した battle_*.log (人間可読ログ) と
# battle_*_protocol.log (プロトコルログ) を、team_key.txt で暗号化して
# GitHub リポジトリ (nMfM1Ow5ot/champions-calc) の logs_enc/ へ送る。
#
# 備考ゲート (2026-11-21、ユーザーの指示。当初 UI に備考欄を付けたが、
# 同日ユーザーの訂正でターミナル入力に変更): 試合ログは、ターミナルで
# 備考が入力されるまで送信しない。serve.py がターミナルで動いている
# 場合 (start_all.sh / start_ui.sh)、送信待ちの試合ができるとこの
# ターミナルに備考の入力プロンプトが出る。1 行入力して Enter を押すと
# 備考が logs/battle_<試合ID>_note.txt に保存され (空欄で Enter でも
# ファイルは作る。ファイルの存在そのものが「入力済み」の印)、その時点で
# 初めてその試合のログ・デバッグ一式・備考ファイルがまとめて送信される。
# プロンプトが出ていない状況 (別のターミナルから手動で送りたい場合等)
# では、別のターミナルで `python3 serve.py --note` を実行すれば、
# 送信待ちの試合を順に聞かれて同じように送れる。
# 備考ファイルも他のファイルと同じ暗号化で logs_enc/ へ送られ、
# 受信側 (ログ分析チャット) は備考の内容を到着報告に含めて分析し、
# 備考の指示に応じて champions_calc 全般の修正につなげる。
# あわせて、reader が問題発生時に保存したデバッグ同梱ファイル
# (battle_<試合ID>_debugNN.jpg/.json、画面全体の画像とイベント
# 情報) も同じ便で送る。目録 (logs_enc/index.json) にはログと同じ形式で
# フラットに載るため、同梱の無い試合では従来と完全に同じになる。
# デバッグ同梱は保持ルールで掃除する: 送信から 30 日超、または総数
# _DEBUG_KEEP_MAX 件超の古いものから目録と実体を削除する
# (ログ本体は削除対象にしない)。
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
STATE_JSON_PATH = os.path.join(BASE_DIR, "state.json")
GH_CONTENTS = "https://api.github.com/repos/nMfM1Ow5ot/champions-calc/contents/"
JST = timezone(timedelta(hours=9))
_log_notice_shown = False
_log_last_error = ""
_log_prune_done_date = None
_log_hold_notice_keys = set()
_upload_lock = threading.Lock()
_note_prompt_waiting = False
_note_prompt_current_key = None
# このプロセスの起動時刻。自動の備考プロンプトは、起動後に終了した
# 試合 (最新のファイルが起動時刻より新しい試合) だけを対象にする。
# 起動時点で既に終わっていた未送信分 (手動で処理済みの残りなど) を
# 起動のたびに聞き直さないため (実例: 2026-11-21
# battle_20261121_150535)。手動の --note では従来どおり全件を聞く。
# serve.py の自己再起動 (exec) ではプロセスが置き換わるため起動
# 時刻も更新されるが、その場合も対戦中の試合のログは再起動後に
# 書かれるため対象から漏れない
_PROCESS_STARTED_AT = time.time()

# ---- 異常記録 (クラッシュジャーナル) ----
# 備考プロンプトのスレッドや serve.py 本体が異常終了した際の証拠を、
# logs/serve_crashes.log へ追記保存する。ターミナルが消えると画面の
# 表示は失われるため、証拠はファイルに残す (実例: 2026-11-21
# battle_20261121_150535 の後、備考入力中にターミナルが異常終了し、
# Mac 側の送信処理が止まったが、当時の版では記録が何も残らず原因を
# 特定できなかった)。このファイル自体も通常の送信対象に含めるため、
# 次回の送信で Muse 側にも届く (備考ゲートの対象外)。
_CRASH_LOG_NAME = "serve_crashes.log"
_CRASH_LOG_MAX = 256 * 1024


def _record_crash(where, exc=None):
    """異常の証拠 (発生時刻・発生箇所・当時の状態・トレースバック) を
    クラッシュジャーナルへ追記する。この関数自体の失敗で本来の処理を
    止めないよう、例外は握りつぶす。"""
    try:
        os.makedirs(LOG_DIR, exist_ok=True)
        head = (f"=== {datetime.now(JST).isoformat()} where={where} "
                f"prompt_waiting={_note_prompt_waiting} "
                f"prompt_key={_note_prompt_current_key or '-'}")
        body = ""
        if exc is not None:
            body = "".join(traceback.format_exception(
                type(exc), exc, exc.__traceback__))
        path = os.path.join(LOG_DIR, _CRASH_LOG_NAME)
        with open(path, "a", encoding="utf-8") as f:
            f.write(head + "\n" + body + "\n")
        _trim_crash_log(path)
    except Exception:
        pass


def _trim_crash_log(path):
    """クラッシュジャーナルが際限なく大きくならないよう、一定量を
    超えたら古い分を間引いて後半だけ残す。"""
    try:
        if os.path.getsize(path) <= _CRASH_LOG_MAX:
            return
        with open(path, "rb") as f:
            data = f.read()
        keep = data[-_CRASH_LOG_MAX // 2:]
        nl = keep.find(b"\n")
        if nl >= 0:
            keep = keep[nl + 1:]
        with open(path, "wb") as f:
            f.write("=== (古い記録は間引かれました)\n".encode("utf-8"))
            f.write(keep)
    except Exception:
        pass


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


def _gh_delete_file(path, token, message, sha):
    return _gh_request("DELETE", path, token, {"message": message, "sha": sha})


# 見せ合いテストの送信セッション。通常起動 (start_all.sh) の
# serve.py は、logs/ に残った過去の見せ合いテスト結果を送らない
# (通常起動でテスト結果が送信されると、テストが起動したように
# 見えるため)。preview_test.sh が起動した serve.py は環境変数で、
# 起動済みの serve.py は POST /preview_test_session で、それぞれ
# 明示的に有効化したときだけ送る。有効化はプロセスの生存期間のみ
# (自動再起動で環境変数は引き継がれる。エンドポイントで有効化した
# 場合は preview_test.sh が撮影のたびに送り直す)
_preview_test_session = (
    os.environ.get("CHAMPIONS_PREVIEW_TEST_SESSION") == "1")


def _preview_test_upload_allowed():
    return _preview_test_session


def _is_upload_target(name):
    if name == _CRASH_LOG_NAME:
        # クラッシュジャーナルは試合に紐づかないため備考ゲートの
        # 対象外とし、内容が変わるたびにそのまま送る
        return True
    if name.startswith("preview_test_") and (
            name.endswith(".jpg") or name.endswith(".json")):
        # 見せ合いテストの成果物 (撮影画像と検出結果)。試合に紐づか
        # ないため備考ゲートの対象外とし、そのまま送る。受信側では
        # preview_test_ 始まりが「見せ合いテストの到着」の目印になる。
        # ただし送信は見せ合いテストのセッションで有効化された
        # ときだけ (上記 _preview_test_session を参照)
        return _preview_test_upload_allowed()
    if name.startswith("debug_ui_") and name.endswith(".json"):
        # UI の「デバッグ送信」ボタンで送られたスナップショット
        # (POST /debug_report で保存)。試合に紐づかないため備考
        # ゲートの対象外とし、そのまま送る。配送先はログ分析では
        # なくダメージ計算チャット (受信側は debug_ui_ 始まりを目印
        # に監視する)。自チームの型情報を含むため、暗号化は他の
        # ファイルと同じ経路 (全送信物が暗号化される) で行われる
        return True
    if not name.startswith("battle_"):
        return False
    if name.endswith(".log"):
        return True
    if name.endswith("_note.txt"):
        return True
    return "_debug" in name and (name.endswith(".jpg") or name.endswith(".json"))


# ---- 備考ゲート ----
# 試合ID (キー) は battle_<日時>[_salvage] の <日時>[_salvage] 部分。
# ファイル名の種類によらず同じ試合のファイルを 1 つのキーに束ねる。
_BATTLE_KEY_RE = re.compile(r"^\d{8}_\d{6}(_salvage)?$")

# 備考ゲートの適用開始 (キー先頭の試合開始時刻、JST)。ゲート導入
# (2026-11-21 13:13 の push) より前に始まった試合はゲートの対象に
# しない。導入時点で未送信のまま残っていた旧試合のログ (前日の
# salvage 残りなど) にまでゲートがかかり、次の試合の開始直後に
# 「入力待ち」の通知とプロンプトが出てしまった件 (2026-11-21、
# battle_20261120_124322_salvage) への対策。判定はファイルの保存
# 時刻ではなくキー先頭の試合開始時刻で行うため、導入後に salvage
# されて現れた旧試合も対象外になり、導入後の試合は salvage でも
# 従来どおりゲート対象になる。
_NOTE_GATE_SINCE = "20261121_131309"


def _note_gate_applies(key):
    """その試合に備考ゲートがかかるか (導入後に始まった試合だけ)。"""
    if not key:
        return False
    return key[:15] >= _NOTE_GATE_SINCE


def _battle_in_progress():
    """いま対戦中かどうかを state.json から判定する。

    reader は対戦中だけ state.json に battle (現在の試合ID) を入れ、
    その試合のログが保存されるまでは対戦中とみなす。reader が再起動
    して進行中の試合を salvage した場合、その salvage は「中断」ログ
    として即座に備考待ちになるが、試合自体は新しい試合IDで続いて
    いるため、対戦中に備考プロンプトを出さないようにする
    (2026-11-21 のユーザー報告: battle_20261121_140542_salvage)。
    state.json が古い (reader が動いていない) 場合は対戦中とみなさ
    ないので、放置された中断ログのプロンプトは従来どおり出る。
    """
    try:
        if time.time() - os.path.getmtime(STATE_JSON_PATH) > 60:
            return False
        with open(STATE_JSON_PATH, encoding="utf-8") as f:
            battle = json.load(f).get("battle")
    except Exception:
        return False
    if not battle or not _BATTLE_KEY_RE.match(str(battle)):
        return False
    # その試合のログ (.log) がまだ保存されていなければ対戦中。
    # デバッグ同梱 (.jpg/.json) は対戦中にも書かれるため対象にしない
    try:
        names = os.listdir(LOG_DIR)
    except OSError:
        return False
    return not any(n.endswith(".log") and _battle_key(n) == battle
                   for n in names)


def _battle_key(name):
    """logs/ のファイル名から試合キーを返す。対象外の名前は None。"""
    if not name.startswith("battle_"):
        return None
    rest = name[len("battle_"):]
    debug_stripped = re.sub(r"_debug\d+\.(jpg|json)$", "", rest)
    if debug_stripped != rest:
        return debug_stripped if _BATTLE_KEY_RE.match(debug_stripped) else None
    if rest.endswith("_note.txt"):
        rest = rest[: -len("_note.txt")]
    elif rest.endswith(".log"):
        rest = rest[: -len(".log")]
        if rest.endswith("_protocol"):
            rest = rest[: -len("_protocol")]
        if rest.endswith("_final"):
            rest = rest[: -len("_final")]
        elif rest.endswith("_interrupted"):
            rest = rest[: -len("_interrupted")]
    else:
        return None
    return rest if _BATTLE_KEY_RE.match(rest) else None


def _note_name(key):
    return f"battle_{key}_note.txt"


def _note_exists(key):
    return os.path.exists(os.path.join(LOG_DIR, _note_name(key)))


def _gate_key(key):
    """備考ゲートとプロンプトで試合を束ねるキーを返す。

    salvage で救済されたログは <元の試合ID>_salvage のキーになるが、
    デバッグ一式 (preview_id を含む) は元の試合 ID のままで保存される。
    末尾の _salvage を落として束ねないと、一式だけが別の試合として
    残り、備考待ちにならずゲートに残り続けて届かなくなる。
    """
    if key and key.endswith("_salvage"):
        return key[: -len("_salvage")]
    return key


def _note_exists_any(key):
    """その試合の備考があるか (salvage 変種のキーで保存された備考も含む)。"""
    return _note_exists(key) or _note_exists(_gate_key(key))


def _load_upload_state():
    if os.path.exists(LOG_STATE_PATH):
        try:
            return json.loads(open(LOG_STATE_PATH).read())
        except Exception:
            return {}
    return {}


def _file_hash(path):
    try:
        return hashlib.sha256(open(path, "rb").read()).hexdigest()
    except OSError:
        return None


def list_pending_log_notes():
    """備考の入力待ちの試合の一覧を返す (ターミナルのプロンプト用)。

    すでに送信済みの試合 (uploaded.json とハッシュが一致するログしか
    残っていない試合) と、備考ファイルが既にある試合は含めない。
    """
    if not os.path.isdir(LOG_DIR):
        return []
    state = _load_upload_state()
    groups = {}
    for name in sorted(os.listdir(LOG_DIR)):
        if not _is_upload_target(name):
            continue
        key = _battle_key(name)
        if key is None:
            continue
        # salvage 変種は元の試合と 1 つのグループに束ねる (デバッグ
        # 一式は元の試合 ID、救済されたログは _salvage 付きの ID で
        # 保存されるため、束ねないと一式が備考待ちにならない)
        groups.setdefault(_gate_key(key), []).append(name)
    pending = []
    for key, names in sorted(groups.items()):
        if _note_exists(key):
            continue
        if any(_note_exists(_battle_key(n) or "") for n in names):
            # salvage 変種のキーで保存された備考がある場合も入力済み
            continue
        if not _note_gate_applies(key):
            # ゲート導入前の試合は備考待ちに数えない (旧試合のログが
            # 後から salvage で現れてもプロンプトを出さない)
            continue
        mtime = 0.0
        for n in names:
            try:
                mtime = max(mtime, os.path.getmtime(os.path.join(LOG_DIR, n)))
            except OSError:
                pass
        log_names = [n for n in names if n.endswith(".log")]
        if log_names:
            # ログが全て送信済みなら、備考待ちではない (備考機能より前に
            # 送信された試合や、送信後に残ったデバッグ一式だけの状態)
            unsent = [n for n in log_names
                      if state.get(n) != _file_hash(os.path.join(LOG_DIR, n))]
            if not unsent:
                continue
        else:
            # ログの無い試合 (reader の異常終了で salvage も効かなかった
            # 場合など) は、デバッグ一式だけが残って通常は備考待ちに
            # ならず、証拠が届かないままになる。最後のファイルから
            # 10 分経っていれば備考待ちに数える (対戦中の試合は
            # ファイルが新しいため対象にならない)
            unsent = [n for n in names
                      if state.get(n) != _file_hash(os.path.join(LOG_DIR, n))]
            if not unsent:
                continue
            if not mtime or time.time() - mtime < 600:
                continue
        kind = "final" if any("_final" in n for n in log_names) else "interrupted"
        opponent = ""
        for n in log_names:
            if "_protocol" in n:
                continue
            try:
                text = open(os.path.join(LOG_DIR, n), encoding="utf-8").read()
            except OSError:
                continue
            m = re.search(r"Battle started between .+? and (.+?)!", text)
            if m:
                opponent = m.group(1).strip()
                break
        pending.append({
            "key": key, "kind": kind, "opponent": opponent,
            "files": sorted(names),
            "mtime": mtime,
            "saved_at": datetime.fromtimestamp(mtime, JST).isoformat()
            if mtime else "",
        })
    return pending


def save_log_note(key, note):
    """ターミナルで入力された備考を logs/battle_<key>_note.txt に保存する。

    空欄でもファイルを作る (存在が「入力済み」の印になる)。
    保存できたら True、キーが不正なら False を返す。
    """
    if not key or not _BATTLE_KEY_RE.match(key):
        return False
    if not isinstance(note, str):
        note = ""
    note = note[:8000]
    os.makedirs(LOG_DIR, exist_ok=True)
    path = os.path.join(LOG_DIR, _note_name(key))
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        f.write(note)
    os.replace(tmp, path)
    # 受け付けた本文も表示する (意図しない入力がそのまま送信される
    # 事故に、その場で気づけるようにするため)
    shown = note if len(note) <= 200 else note[:200] + "…"
    print(f"[log] 備考を受け付けました: battle_{key} "
          f"({len(note)}文字) {shown!r}", flush=True)
    return True


# デバッグ同梱の総数保持上限。記録側の上限が 1 試合最大 19 件に
# なったため (2026-11-21 のクラス分け)、保持できる試合数を従来
# 並み (約 30 試合分) に保つよう比例で引き上げた (旧: 300 件)
_DEBUG_KEEP_MAX = 570


def _prune_debug_entries(index, token, limit=10):
    # デバッグ同梱の保持ルール (30 日超 / 総数 _DEBUG_KEEP_MAX 件超の
    # 古い順) に従い、目録と実体 (logs_enc/*.enc) を削除する。
    # 1 回の掃除は limit 件まで。
    now = datetime.now(JST)
    entries = index.get("files", [])
    debug_entries = [e for e in entries if "_debug" in (e.get("name") or "")]

    def age_days(e):
        try:
            return (now - datetime.fromisoformat(e["uploaded_at"])).days
        except Exception:
            return -1

    victims = [e for e in debug_entries if age_days(e) > 30]
    excess = len(debug_entries) - len(victims) - _DEBUG_KEEP_MAX
    if excess > 0:
        rest = sorted((e for e in debug_entries if e not in victims),
                      key=lambda e: e.get("uploaded_at", ""))
        victims += rest[:excess]
    removed = 0
    for e in victims[:limit]:
        name = e["name"]
        try:
            _, sha = _gh_get_file("logs_enc/" + name + ".enc", token)
            if sha:
                _gh_delete_file("logs_enc/" + name + ".enc", token,
                                f"prune debug bundle {name}", sha)
            entries.remove(e)
            removed += 1
            print(f"[log] 古いデバッグ情報を削除しました: {name}", flush=True)
        except Exception:
            continue
    return removed


def upload_logs_once():
    # 備考の送信ボタンからも呼ばれるため、二重送信を防ぐ
    if not _upload_lock.acquire(blocking=False):
        return
    try:
        _upload_logs_once_locked()
    finally:
        _upload_lock.release()


def _upload_logs_once_locked():
    global _log_notice_shown, _log_last_error, _log_prune_done_date
    if not os.path.isdir(LOG_DIR):
        return
    if _note_prompt_waiting:
        # 備考プロンプトが回答待ちの間は送信しない。回答前に別の試合の
        # 「送信しました」や「入力待ちです」が出ると、プロンプト中の
        # 試合が入力なしで送られたように見える (2026-11-21 のユーザー
        # 報告)。回答が終わると prompt_for_pending_notes が改めて送信
        # を呼ぶため、保留されていた分はそこでまとめて送られる
        return
    names = sorted(n for n in os.listdir(LOG_DIR) if _is_upload_target(n))
    if not names:
        return
    state = _load_upload_state()
    pending_all = []
    for n in names:
        try:
            data = open(os.path.join(LOG_DIR, n), "rb").read()
        except OSError:
            continue
        h = hashlib.sha256(data).hexdigest()
        if state.get(n) != h:
            pending_all.append((n, data, h))
    # 備考ゲート: 備考ファイルが無い試合のログ・デバッグ一式は送信しない。
    # 備考ファイル自体は「入力済み」の印なので常に対象にする
    pending_log_keys = {_battle_key(n) for n, _, _ in pending_all
                        if n.endswith(".log")}
    pending_log_keys.discard(None)
    pending = []
    held_keys = set()
    for n, data, h in pending_all:
        key = _battle_key(n)
        if (key is not None and not n.endswith("_note.txt")
                and not _note_exists_any(key) and _note_gate_applies(key)):
            # 備考が入るまでは、その試合のファイルは種別を問わず保留する。
            # デバッグ同梱は試合の途中で作られるため、ログが保存される前
            # でも保留対象に含める (以前はログのある試合だけが保留され、
            # 同梱だけが試合の途中で送信されてしまっていた。2026-11-21 の
            # ユーザー指示で「ログ・デバッグ一式をまとめて送信」に変更)。
            # 「入力待ち」の通知は、試合が終わってログがある試合だけに出す
            if key in pending_log_keys:
                held_keys.add(key)
            continue
        pending.append((n, data, h))
    for key in sorted(held_keys):
        if key not in _log_hold_notice_keys:
            _log_hold_notice_keys.add(key)
            print(f"[log] 試合ログは備考の入力待ちです: battle_{key} "
                  "(このターミナルのプロンプトで入力するか、別のターミナルで "
                  "python3 serve.py --note を実行してください)", flush=True)
    _log_hold_notice_keys.intersection_update(
        {_battle_key(n) for n in names if n.endswith(".log")})
    # デバッグ同梱の掃除は 1 日 1 回まで (送信が無い日でもその回だけ目録を見る)
    prune_due = _log_prune_done_date != datetime.now(JST).date()
    if not pending and not prune_due:
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
        sent_battle = 0
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
            if _battle_key(n) is not None:
                sent_battle += 1
            if n.startswith("preview_test_"):
                print(f"[log] 見せ合いテストの結果を送信しました: {n}",
                      flush=True)
            elif n.startswith("debug_ui_"):
                print(f"[log] UIデバッグ情報を送信しました: {n}",
                      flush=True)
            else:
                print(f"[log] 試合ログを送信しました: {n}", flush=True)
        if prune_due or changed_index:
            if _prune_debug_entries(index, token):
                changed_index = True
            _log_prune_done_date = datetime.now(JST).date()
        if changed_index:
            index["files"].sort(key=lambda e: e["name"])
            _gh_put_file("logs_enc/index.json",
                         json.dumps(index, ensure_ascii=False, indent=1).encode(),
                         token, "update battle log index", sha=index_sha)
        with open(LOG_STATE_PATH, "w") as f:
            json.dump(state, f)
        _log_last_error = ""
        if sent_battle:
            _report_upload_completion(state)
    except Exception as e:
        msg = f"[log] 試合ログの送信に失敗しました (次回再試行します): {e}"
        if msg != _log_last_error:
            print(msg, flush=True)
            _log_last_error = msg


def _report_upload_completion(state):
    # 送信完了の表示 (2026-11-21 のユーザー指示)。このサイクルで試合の
    # ファイルを実際に送信した後にだけ呼ばれる。残っている未送信
    # ファイルを数え、全部送れていれば完了を表示し、備考待ちだけが
    # 残っていればその旨を表示する (「全部終わった」と誤解させない)。
    # 備考待ち以外の未送信が残っている場合は何も出さない
    try:
        names = sorted(n for n in os.listdir(LOG_DIR) if _is_upload_target(n))
    except OSError:
        return
    held = set()
    other = 0
    for n in names:
        try:
            data = open(os.path.join(LOG_DIR, n), "rb").read()
        except OSError:
            continue
        if state.get(n) == hashlib.sha256(data).hexdigest():
            continue
        key = _battle_key(n)
        if (key is not None and not n.endswith("_note.txt")
                and not _note_exists_any(key) and _note_gate_applies(key)):
            held.add(_gate_key(key))
        else:
            other += 1
    if other:
        return
    if held:
        print(f"[log] 送信できる分は完了しました "
              f"(備考の入力待ちが {len(held)} 件あります)", flush=True)
    else:
        print("[log] 送信が完了しました", flush=True)


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

    def do_POST(self):
        path = self.path.split("?", 1)[0]
        if path == "/preview_test_session":
            # 見せ合いテストの送信をこのプロセスの生存期間だけ有効化
            # する (preview_test.sh が撮影前に送る)。通常起動の
            # serve.py が過去のテスト結果を送らないための明示スイッチ
            global _preview_test_session
            _preview_test_session = True
            payload = json.dumps({"ok": True}).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(payload)))
            self.end_headers()
            self.wfile.write(payload)
            return
        # UI の「デバッグ送信」ボタンの受け口。スナップショット JSON
        # を logs/debug_ui_<日時>.json に保存し、通常のアップロード
        # サイクル (備考ゲート対象外) で暗号化して送る。UI は 2xx
        # 以外を送信失敗として表示するため、失敗時は必ず非 2xx を返す
        if path != "/debug_report":
            self.send_error(404)
            return
        try:
            length = int(self.headers.get("Content-Length") or 0)
        except ValueError:
            length = 0
        if length <= 0:
            self.send_error(400)
            return
        if length > 5 * 1024 * 1024:
            self.send_error(413)
            return
        body = self.rfile.read(length)
        try:
            json.loads(body)
        except Exception:
            self.send_error(400)
            return
        try:
            os.makedirs(LOG_DIR, exist_ok=True)
            stamp = datetime.now(JST).strftime("%Y%m%d_%H%M%S")
            name = f"debug_ui_{stamp}.json"
            path = os.path.join(LOG_DIR, name)
            suffix = 1
            while os.path.exists(path):
                suffix += 1
                name = f"debug_ui_{stamp}_{suffix}.json"
                path = os.path.join(LOG_DIR, name)
            with open(path, "wb") as f:
                f.write(body)
        except Exception as e:
            _record_crash("debug_report_save", e)
            self.send_error(500)
            return
        print(f"[log] UIデバッグ情報を受け取りました: {name}", flush=True)
        payload = json.dumps({"ok": True, "file": name}).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)


# ---- 備考のターミナル入力 ----
# 送信待ちの試合を 1 件ずつ聞いて備考を保存する。入力は 1 行で、
# 空欄で Enter を押せば備考なしで送信される。EOF (入力が閉じている)
# の場合は例外で呼び出し側に知らせる。
def prompt_for_pending_notes(input_fn=None, do_upload=True, session_only=False):
    if input_fn is None:
        # 既定も _prompt_input を使う (タイプアヘッド破棄などの保護を
        # --note の手動経路でも効かせるため)
        input_fn = lambda prompt: _prompt_input(sys.stdin, sys.stdout, prompt)  # noqa: E731
    global _note_prompt_current_key
    count = 0
    for p in list_pending_log_notes():
        if session_only and p.get("mtime", 0) < _PROCESS_STARTED_AT:
            # 自動プロンプトでは、このプロセスの起動前に終わっていた
            # 試合は聞かない (起動のたびに古い未送信分を聞き直す
            # のを防ぐ。手動の --note では従来どおり聞く)
            continue
        vs = f" vs {p['opponent']}" if p.get("opponent") else ""
        kind = "勝敗確定" if p.get("kind") == "final" else "中断"
        print(f"[log] 試合ログが保存されました (battle_{p['key']}{vs}、{kind})。"
              "送信前に備考を入力してください", flush=True)
        # 異常記録用に、現在聞いている試合を控える
        _note_prompt_current_key = p["key"]
        try:
            note = input_fn("備考 (空欄で Enter = 備考なしで送信): ")
        finally:
            _note_prompt_current_key = None
        if save_log_note(p["key"], note or ""):
            count += 1
    if count and do_upload:
        upload_logs_once()
    return count


def _open_prompt_io():
    """備考プロンプト用の入出力ストリームを開く。

    標準入力がターミナルならそれを使う。そうでなくても制御端末
    (/dev/tty) が開けるならそちらを使う。以前は標準入力がターミナル
    でないとプロンプト自体が出ず、入力も届かなかった (2026-11-21 の
    battle_20261121_132153 の備考が送信できなかった件)。起動方法に
    よらずプロンプトが無言で無効にならないよう、フォールバックと
    起動時の状態表示を入れた。戻り値は (入力, 出力, 説明)。
    """
    try:
        if sys.stdin is not None and sys.stdin.isatty():
            return sys.stdin, sys.stdout, "標準入力のターミナル"
    except Exception:
        pass
    try:
        tty = open("/dev/tty", "r+")
        return tty, tty, "/dev/tty"
    except OSError:
        return None, None, ""


def _flush_typeahead(stream):
    """プロンプト表示前に、端末の未読入力 (タイプアヘッド) を破棄する。

    対戦中は誰も入力を読まないため、対戦中やそれ以前にそのターミナルへ
    打たれた文字がカーネルの入力バッファに残り続け、試合終了直後の
    プロンプトがそれを備考として取り込んでしまう (実例: 2026-11-21
    battle_20261121_145658、備考が「a」1 文字で勝手に送信された)。
    端末でないストリームでは何もしない。
    """
    try:
        fd = stream.fileno()
    except Exception:
        return
    try:
        import termios
        if os.isatty(fd):
            termios.tcflush(fd, termios.TCIFLUSH)
    except Exception:
        pass


def _prompt_input(in_stream, out_stream, prompt):
    """プロンプトを確実に表示 (flush) してから 1 行読む。

    表示前のタイプアヘッドは破棄し、表示後に入力された行だけを
    受け付ける。防御の重ねとして、表示から不自然に早く (0.5 秒未満で)
    返った行はバッファ残りの疑いとして 1 回だけ破棄して聞き直す
    (2 回目は速くても受け付ける)。入力が確定したら、表示からの
    経過時間をターミナルに残す。
    """
    for attempt in (1, 2):
        _flush_typeahead(in_stream)
        started = time.monotonic()
        out_stream.write(prompt)
        out_stream.flush()
        line = in_stream.readline()
        if line == "":
            raise EOFError("note prompt input closed")
        elapsed = time.monotonic() - started
        line = line.rstrip("\n").rstrip("\r")
        if elapsed < 0.5 and attempt == 1:
            print(f"[log] プロンプト表示から {elapsed:.2f} 秒で入力が返ったため、"
                  f"バッファ残りの疑いとして破棄しました: {line!r}。"
                  "もう一度入力してください", flush=True)
            continue
        print(f"[log] 備考の入力が確定しました "
              f"(プロンプト表示から {elapsed:.1f} 秒)", flush=True)
        return line


def _note_prompt_loop(in_stream=None, out_stream=None):
    # serve.py 本体が動いている間、送信待ちの試合ができたらターミナルで
    # 備考を聞く。EOF (入力が閉じられた) になってもスレッドを終わらせず、
    # ターミナルを開き直して復帰を試みる。それでも開けない場合だけ、
    # 案内を出して終える (以降の送信待ちは `python3 serve.py --note`
    # で送れる)。
    if in_stream is None:
        in_stream, out_stream, _ = _open_prompt_io()
    if in_stream is None:
        _record_crash("note_prompt_start_unavailable")
        return

    def _input_fn(prompt):
        # 回答待ちの間は送信側を止める (入力していないのに送信された
        # ように見える競合の解消。_upload_logs_once_locked を参照)
        global _note_prompt_waiting
        _note_prompt_waiting = True
        try:
            return _prompt_input(in_stream, out_stream, prompt)
        finally:
            _note_prompt_waiting = False

    reopen_tries = 0
    while True:
        try:
            # 対戦中はプロンプトを出さない (進行中の試合の salvage 等が
            # 備考待ちになっても、試合が終わってから聞く)
            if list_pending_log_notes() and not _battle_in_progress():
                prompt_for_pending_notes(input_fn=_input_fn, session_only=True)
                reopen_tries = 0
            else:
                time.sleep(2)
        except (EOFError, OSError) as e:
            # EOF 以外の入出力エラー (端末の消失に伴う EIO 等) でも、
            # 無言で死なずに記録を残してから復帰を試みる
            _record_crash("note_prompt_loop", e)
            reopen_tries += 1
            if reopen_tries > 3:
                print("[log] 備考の入力プロンプトを終了します。"
                      "送信待ちのログは python3 serve.py --note で送れます", flush=True)
                return
            print("[log] 備考の入力が閉じられたため、ターミナルを開き直します", flush=True)
            time.sleep(5)
            new_in, new_out, _ = _open_prompt_io()
            if new_in is not None:
                in_stream, out_stream = new_in, new_out
        except Exception as e:
            _record_crash("note_prompt_loop", e)
            time.sleep(2)


def _server_running():
    import socket
    try:
        with socket.create_connection(("127.0.0.1", 8765), timeout=1):
            return True
    except OSError:
        return False


def cli_send_notes():
    """`python3 serve.py --note`: 別のターミナルから備考を付けて送る。"""
    pending = list_pending_log_notes()
    if not pending:
        print("送信待ちの試合ログはありません")
        return 0
    try:
        count = prompt_for_pending_notes(do_upload=False)
    except (EOFError, OSError):
        print("入力が中断されました")
        return 1
    except Exception as e:
        _record_crash("note_cli", e)
        print("入力が中断されました")
        return 1
    if count:
        if _server_running():
            # 起動中の serve.py の定期送信 (約30秒ごと) に任せる。
            # 二つのプロセスが同時に送信すると目録の競合が起きるため、
            # このプロセスからは送信しない
            print("備考を保存しました。起動中のサーバが約30秒以内に送信します")
        else:
            upload_logs_once()
    return 0


if __name__ == "__main__":
    if "--note" in sys.argv:
        # 備考を付けて送るだけの手動コマンド (サーバは起動しない)
        raise SystemExit(cli_send_notes())
    check_log_token()
    threading.Thread(target=sync_loop, daemon=True).start()
    # バックグラウンドで動くプロセスがターミナル読み取りで止まらない
    # ようにする (start_all.sh では serve.py は裏で動くため、ジョブ制御の
    # あるシェルから起動されると SIGTTIN で停止しうる)
    for _sig_name in ("SIGTTIN", "SIGTTOU"):
        _sig = getattr(signal, _sig_name, None)
        if _sig is not None:
            try:
                signal.signal(_sig, signal.SIG_IGN)
            except (ValueError, OSError):
                pass
    # 備考の入力プロンプト。有効かどうかを必ず表示する (無言で無効に
    # なっていたのが 2026-11-21 の送信失敗の一因)
    _pin, _pout, _plabel = _open_prompt_io()
    if _pin is not None:
        print(f"[log] 備考プロンプト: 有効 ({_plabel}で入力できます)", flush=True)

        def _prompt_thread_entry():
            # プロンプトループから例外が漏れてスレッドが死んでも、
            # 証拠を残して立て直す。立て直しの際は送信停止フラグ
            # (_note_prompt_waiting) を必ず解除する (残ったままだと
            # 送信が永久に止まるため)
            global _note_prompt_waiting
            cur_in, cur_out = _pin, _pout
            for _attempt in range(3):
                try:
                    _note_prompt_loop(cur_in, cur_out)
                    return
                except BaseException as e:
                    _note_prompt_waiting = False
                    _record_crash("note_prompt_thread", e)
                    time.sleep(2)
                    new_in, new_out, _ = _open_prompt_io()
                    if new_in is None:
                        break
                    cur_in, cur_out = new_in, new_out
            _record_crash("note_prompt_thread_gave_up")

        threading.Thread(target=_prompt_thread_entry, daemon=True).start()
    else:
        print("[log] 備考プロンプト: 無効 (ターミナル入力がありません)。"
              "送信待ちのログは別のターミナルで python3 serve.py --note を実行して送ってください",
              flush=True)
    # 端末の異常終了に伴う SIGHUP 等でも、終了の証拠が残るようにする。
    # 記録した後は通常どおり終了させる (ハンドラを既定へ戻して再送する)
    def _signal_crash_handler(signum, frame):
        try:
            _sname = signal.Signals(signum).name
        except Exception:
            _sname = str(signum)
        _record_crash(f"signal_{_sname}")
        signal.signal(signum, signal.SIG_DFL)
        os.kill(os.getpid(), signum)

    for _signame in ("SIGHUP", "SIGTERM"):
        _sig = getattr(signal, _signame, None)
        if _sig is not None:
            try:
                signal.signal(_sig, _signal_crash_handler)
            except (ValueError, OSError):
                pass
    handler = functools.partial(QuietHandler, directory=".")
    try:
        server = http.server.ThreadingHTTPServer(("127.0.0.1", 8765), handler)
    except OSError:
        print("ポート 8765 は使用中です。別のターミナルで旧サーバが動いています。")
        print("そのターミナルで Ctrl+C を押して止めてから、もう一度実行してください。")
        print("見つからない場合は次のコマンドで止められます: lsof -ti tcp:8765 | xargs kill")
        raise SystemExit(1)
    with server as httpd:
        try:
            httpd.serve_forever()
        except BaseException as e:
            _record_crash("main", e)
            raise
