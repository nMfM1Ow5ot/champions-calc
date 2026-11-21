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
import select
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


_restart_note_defer_since = None


def maybe_restart_self():
    # 同期で serve.py 自身が差し替わっていたら、新しいコードで起動し直す。
    # 起動時点のハッシュと比べるので、差し替えがなければ何も起きない。
    # exec で同じプロセスを置き換えるため、start_all.sh 側の管理
    # (バックグラウンド起動・終了時の trap) はそのまま効く。
    # ただし備考プロンプトの回答待ち・対象範囲内の備考待ちがある間は
    # 再起動しない。対戦終了直後のプロンプトへ再起動が割り込むと、
    # 入力の機会自体が失われる (実例: 2026-11-22
    # battle_20261122_071457)。備考待ちはプロンプトの制限時間
    # (30 秒) で解消するのが通常で、万一解消しない場合も 120 秒で
    # 引き継ぎ付きで再起動する (引き継ぎ先でも備考は聞ける)
    global _restart_note_defer_since
    current = self_hash()
    if current is None or START_HASH is None or current == START_HASH:
        _restart_note_defer_since = None
        return
    if _note_blocking():
        now = time.monotonic()
        if _restart_note_defer_since is None:
            _restart_note_defer_since = now
            if not _note_prompt_waiting:
                # プロンプト表示中にこの表示を出すと割り込み出力に
                # なって入力を無効化するため、表示中は出さない
                print("[sync] 備考の入力待ちがあるため、serve.py の再起動を保留します", flush=True)
        if now - _restart_note_defer_since < 120:
            return
    _restart_note_defer_since = None
    _set_note_carry()
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
    upload_logs_once(session_only=True)
    cycles = 0
    sync_deferred = False
    while True:
        time.sleep(5)
        try:
            # 対戦中は同期の反映を保留する: 対戦中に UI ファイルが
            # 差し替わると、開いている計算画面のセッションが再読み
            # 込み等で初期化され、推論の記録が止まる事故があった
            # (2026-11-22 battle_20261122_054802、推論ログの記録が
            # 別チャットの push の時刻で停止した)。同期は周期処理
            # なので、対戦が終わるまで回さなければ次の周期でその
            # まま反映される。serve.py 自身の再起動も同期に付随する
            # ため一緒に保留する。試合ログの送信は UI ファイルに
            # 触れないため、対戦中も従来どおり回す
            if _note_prompt_waiting:
                # 備考プロンプトの回答待ち中は、同期の反映とそれに
                # 伴う表示を一切出さない。同期側の表示がプロンプトへ
                # 割り込むと入力が無効化される (実例: 2026-11-22
                # battle_20261122_071457、対戦終了直後の再開表示が
                # プロンプトへ割り込んだ)。プロンプトは制限時間で
                # 解消するため、保留は最大でもその間だけ
                pass
            elif _battle_in_progress():
                if not sync_deferred:
                    sync_deferred = True
                    print("[sync] 対戦中のため、同期の反映を対戦終了まで保留します", flush=True)
            else:
                if sync_deferred:
                    sync_deferred = False
                    print("[sync] 対戦が終了したため、同期を再開します", flush=True)
                run_sync(False)
                try:
                    maybe_restart_self()
                except Exception:
                    print("[sync] serve.py の自動再起動に失敗しました。次回同期時に再試行します", flush=True)
            cycles += 1
            if cycles % 6 == 0:   # 試合ログの送信チェックは約 30 秒ごと
                upload_logs_once(session_only=True)
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

# 自己再起動 (os.execv) の引き継ぎ: 再起動の時点で備考待ちだった
# 試合 (このプロセスの対象範囲内のもの) のゲートキーを、環境変数
# CHAMPIONS_NOTE_CARRY で次のプロセスへ渡す。再起動後のプロセスでは
# 起動時刻より前に終わった試合でも、引き継がれた試合だけは自動処理
# の対象に残す。対戦終了直後に備考プロンプトが出ている最中へ、同期
# の再開に伴う自己再起動が割り込み、その試合の備考の機会自体が
# 失われた件への対策 (実例: 2026-11-22 battle_20261122_071457)
_CARRIED_NOTE_KEYS = {k for k in
                      os.environ.get("CHAMPIONS_NOTE_CARRY", "").split(",")
                      if k}


def _in_session_scope(gate_key, mtime):
    """自動処理 (プロンプト・送信) の対象範囲内かどうか。

    起動後に終わった試合が原則で、自己再起動で引き継がれた試合も
    対象に含める。"""
    return mtime >= _PROCESS_STARTED_AT or gate_key in _CARRIED_NOTE_KEYS


def _note_blocking():
    """備考まわりで同期の反映や再起動を止めるべき状態か。

    プロンプトの回答待ち中か、このプロセスの対象範囲内に備考待ちの
    試合がある間は True。"""
    if _note_prompt_waiting:
        return True
    try:
        return any(_in_session_scope(p["key"], p.get("mtime", 0))
                   for p in list_pending_log_notes())
    except Exception:
        return False


def _set_note_carry():
    """再起動の直前に、対象範囲内の備考待ちを引き継ぎ用に控える。"""
    try:
        keys = sorted({p["key"] for p in list_pending_log_notes()
                       if _in_session_scope(p["key"], p.get("mtime", 0))})
    except Exception:
        keys = []
    if keys:
        os.environ["CHAMPIONS_NOTE_CARRY"] = ",".join(keys)
    else:
        os.environ.pop("CHAMPIONS_NOTE_CARRY", None)

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


# ---- チームプリセットの共有 (POST /presets) ----
# プリセットの正本はリポジトリ直下の presets.json (UI が raw から
# 直接読む)。localhost の UI はこのエンドポイント経由で保存し、
# デバッグ用ページはページ側のトークンで直接 PUT する。同期
# マニフェストの対象外で、備考ゲートにもかけない。
PRESETS_PATH = os.path.join(BASE_DIR, "presets.json")
_PRESETS_MAX_BYTES = 1024 * 1024
_presets_lock = threading.Lock()


def _save_and_upload_presets(body):
    """プリセットストア全体を受けて保存し、GitHub へ即時反映する。

    戻り値: (status, payload_dict)。検証不正は 400、保存や
    アップロードの失敗は 500 (payload に理由を入れる)。
    """
    try:
        data = json.loads(body)
    except Exception:
        return 400, {"ok": False, "error": "invalid json"}
    if not isinstance(data, dict) \
            or not isinstance(data.get("mine"), list) \
            or not isinstance(data.get("opps"), list):
        return 400, {"ok": False, "error": "mine/opps must be arrays"}
    with open(PRESETS_PATH, "wb") as f:
        f.write(body)
    token = _log_token()
    if not token:
        return 500, {"ok": False,
                     "error": "github_log_token.txt is not configured"}
    with _presets_lock:
        _, sha = _gh_get_file("presets.json", token)
        try:
            _gh_put_file("presets.json", body, token,
                         "Update presets.json via serve.py", sha=sha)
        except urllib.error.HTTPError as e:
            if e.code != 409:
                raise
            # デバッグ用ページ側の PUT と競合した場合は、sha を
            # 取り直して 1 回だけ再試行する (内容はこちらの保存が正)
            _, sha = _gh_get_file("presets.json", token)
            _gh_put_file("presets.json", body, token,
                         "Update presets.json via serve.py", sha=sha)
    return 200, {"ok": True}


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
    if name.endswith("_inference.json"):
        # 型推定エンジンの推論過程ログ (POST /inference_log で保存)。
        # その試合のファイル一式の一部として、備考ゲート付きで
        # 試合ログと一緒に送る
        return True
    if name.endswith("_calclog.json"):
        # ダメ計ログ (POST /calclog で保存)。推論過程ログと同じく、
        # その試合のファイル一式の一部として、備考ゲート付きで
        # 試合ログと一緒に送る
        return True
    if name.endswith("_states.json"):
        # state.json のスナップショット (reader が形の切り替わり点で
        # 蓄積)。推論過程ログと同じく、その試合のファイル一式の
        # 一部として、備考ゲート付きで試合ログと一緒に送る
        return True
    return "_debug" in name and (name.endswith(".jpg") or name.endswith(".json"))


_receipt_printed = set()


def _announce_receipt(tag, label, name, count):
    """受け取り表示は、同じ試合・同じ種類につきプロセス内で 1 回
    だけ出す。UI は蓄積全件を数秒おきに再送するため、毎回出すと
    対戦中のターミナルに送信が行われているかのような表示が並ぶ
    (2026-11-22 のユーザー指摘)。保存そのものは毎回行う"""
    if tag in _receipt_printed:
        return
    _receipt_printed.add(tag)
    print(f"[log] {label}を受け取りました: {name} ({count} 件)", flush=True)


def _save_inference_log(body):
    """推論過程ログ (UI からの POST /inference_log) を保存する。

    ボディは {kind, version, battle, entries} の JSON で、battle は
    試合キー (battle_ を除いた日時部分、_salvage 付きも可)。
    検証できないものは ValueError を送出する。保存先は
    logs/battle_<キー>_inference.json で、同じ試合への再送は
    上書きする (UI はその試合の蓄積全件を送る方式のため)。
    """
    try:
        data = json.loads(body)
    except Exception:
        raise ValueError("inference log is not JSON")
    if not isinstance(data, dict):
        raise ValueError("inference log is not an object")
    battle = data.get("battle")
    if not isinstance(battle, str) or not _BATTLE_KEY_RE.match(battle):
        raise ValueError("inference log has no valid battle key")
    if not isinstance(data.get("entries"), list):
        raise ValueError("inference log has no entries list")
    os.makedirs(LOG_DIR, exist_ok=True)
    name = f"battle_{battle}_inference.json"
    with open(os.path.join(LOG_DIR, name), "wb") as f:
        f.write(body)
    # 起動前に終わった試合の推論過程ログが、UI の再送で起動時に
    # 届くことがある。保存はするが、起動時に過去分の処理が走って
    # いるように見える表示は出さない (2026-11-21 のユーザー指示)。
    # 判定はその試合のログの時刻で行う (対戦中の試合にはまだ
    # ログが無いため、通常どおり表示される)
    ended_before_start = False
    try:
        gk = _gate_key(battle)
        log_times = []
        for n in os.listdir(LOG_DIR):
            k = _battle_key(n)
            if k is not None and _gate_key(k) == gk and n.endswith(".log"):
                log_times.append(os.path.getmtime(os.path.join(LOG_DIR, n)))
        ended_before_start = bool(log_times) and max(log_times) < _PROCESS_STARTED_AT
    except OSError:
        ended_before_start = False
    if not ended_before_start:
        _announce_receipt(("inference", battle), "推論過程ログ",
                          name, len(data["entries"]))
    return name


def _save_calc_log(body):
    """ダメ計ログ (UI からの POST /calclog) を保存する。

    ボディは {kind, version, battle, entries} の JSON で、battle は
    試合キー (battle_ を除いた日時部分、_salvage 付きも可)。
    検証できないものは ValueError を送出する。保存先は
    logs/battle_<キー>_calclog.json で、同じ試合への再送は
    上書きする (UI はその試合の蓄積全件を送る方式のため)。
    推論過程ログと同水準の検証・同型の受け取り表示にする。
    """
    try:
        data = json.loads(body)
    except Exception:
        raise ValueError("calc log is not JSON")
    if not isinstance(data, dict):
        raise ValueError("calc log is not an object")
    battle = data.get("battle")
    if not isinstance(battle, str) or not _BATTLE_KEY_RE.match(battle):
        raise ValueError("calc log has no valid battle key")
    if not isinstance(data.get("entries"), list):
        raise ValueError("calc log has no entries list")
    os.makedirs(LOG_DIR, exist_ok=True)
    name = f"battle_{battle}_calclog.json"
    with open(os.path.join(LOG_DIR, name), "wb") as f:
        f.write(body)
    # 推論過程ログと同じく、起動前に終わった試合分は保存だけして
    # 受け取り表示を出さない (起動時に過去分の処理が走っている
    # ように見せないため)
    ended_before_start = False
    try:
        gk = _gate_key(battle)
        log_times = []
        for n in os.listdir(LOG_DIR):
            k = _battle_key(n)
            if k is not None and _gate_key(k) == gk and n.endswith(".log"):
                log_times.append(os.path.getmtime(os.path.join(LOG_DIR, n)))
        ended_before_start = bool(log_times) and max(log_times) < _PROCESS_STARTED_AT
    except OSError:
        ended_before_start = False
    if not ended_before_start:
        _announce_receipt(("calclog", battle), "ダメ計ログ",
                          name, len(data["entries"]))
    return name


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
    elif rest.endswith("_inference.json"):
        rest = rest[: -len("_inference.json")]
    elif rest.endswith("_calclog.json"):
        rest = rest[: -len("_calclog.json")]
    elif rest.endswith("_states.json"):
        rest = rest[: -len("_states.json")]
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


_upload_battle_deferred = False


def upload_logs_once(session_only=False):
    # 備考の送信ボタンからも呼ばれるため、二重送信を防ぐ。
    # session_only=True (自動送信) では、このプロセスの起動前から
    # 残っている試合 (滞留分) を扱わない (2026-11-21 のユーザー指示:
    # 起動時に過去分の備考解消や送信が始まらないようにする)
    global _upload_battle_deferred
    if session_only and _battle_in_progress():
        # 対戦中は、前の試合の分も含めて自動送信をしない
        # (2026-11-22 のユーザー指示: 対戦中にターミナルへ送信の
        # 動きが出ること自体が問題とされた)。判定は備考プロンプトの
        # 保留と同じ _battle_in_progress を使い、対戦終了後の周期で
        # まとめて送る。手動経路 (session_only=False) は従来どおり
        # 即時に送る
        if not _upload_battle_deferred:
            _upload_battle_deferred = True
            print("[log] 対戦中のため、試合ログの送信を対戦終了まで保留します", flush=True)
        return
    _upload_battle_deferred = False
    if not _upload_lock.acquire(blocking=False):
        return
    try:
        _upload_logs_once_locked(session_only)
    finally:
        _upload_lock.release()


def _battle_group_mtimes(names):
    """試合キー (salvage 束ね済み) ごとの代表時刻を返す。

    代表時刻は、その試合のログ (.log) の最新時刻とする。推論過程
    ログのように、対戦の終了後に遅れて届くファイルがあっても、
    試合が「起動前に終わったものかどうか」の判定は変わらない
    (2026-11-21 のユーザー報告: 起動時に UI から再送された推論
    過程ログの時刻で、起動前の試合が送信対象に化けた)。ログの
    無い一式は、全ファイルの最新時刻で代用する。"""
    log_mtimes = {}
    all_mtimes = {}
    for n in names:
        key = _battle_key(n)
        if key is None:
            continue
        try:
            mt = os.path.getmtime(os.path.join(LOG_DIR, n))
        except OSError:
            continue
        gk = _gate_key(key)
        all_mtimes[gk] = max(all_mtimes.get(gk, 0.0), mt)
        if n.endswith(".log"):
            log_mtimes[gk] = max(log_mtimes.get(gk, 0.0), mt)
    return {gk: log_mtimes.get(gk, mt) for gk, mt in all_mtimes.items()}


def _upload_logs_once_locked(session_only=False):
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
    group_mtimes = _battle_group_mtimes(names) if session_only else {}
    pending_all = []
    for n in names:
        if session_only:
            key = _battle_key(n)
            if (key is not None
                    and not _in_session_scope(
                        _gate_key(key),
                        group_mtimes.get(_gate_key(key), 0.0))):
                # 起動前から残っている試合は自動送信の対象外 (滞留分は
                # Mac 側にそのまま残し、手動の --note 経路でだけ扱う)
                continue
        try:
            data = open(os.path.join(LOG_DIR, n), "rb").read()
        except OSError:
            continue
        h = hashlib.sha256(data).hexdigest()
        if state.get(n) != h:
            pending_all.append((n, data, h))
    # 安全網の下書き (interrupted) は、確定版 (final) がある試合では
    # 送らない。下書きは対戦序盤の断片でしかなく、確定版が正である
    # (reader 側でも確定保存時に下書きは消される)。両方が届くと、
    # 序盤で途切れた下書きが「対戦本体が記録されていない試合」に
    # 見えてしまう (実例: 2026-11-21 battle_20261121_234913、
    # 下書きはヘッダーのみ、確定版は 10 ターン完結していた)
    final_gate_keys = set()
    for n in names:
        if "_final" in n and n.endswith(".log"):
            k = _battle_key(n)
            if k is not None:
                final_gate_keys.add(_gate_key(k))
    if final_gate_keys:
        pending_all = [(n, d, h) for n, d, h in pending_all
                       if not ("_interrupted" in n and n.endswith(".log")
                               and _battle_key(n) is not None
                               and _gate_key(_battle_key(n))
                               in final_gate_keys)]
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
    if session_only:
        # クラッシュ記録は、起動しただけでは送らない。起動後に
        # 終わった試合がこのサイクルで送られる時に同梱する
        # (本来のタイミングでの送信は止めない、という 2026-11-21
        # のユーザー指示)
        if not any(_battle_key(n) is not None for n, _, _ in pending):
            pending = [(n, d, h) for n, d, h in pending
                       if n != "serve_crashes.log"]
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
            _report_upload_completion(state, session_only)
    except Exception as e:
        msg = f"[log] 試合ログの送信に失敗しました (次回再試行します): {e}"
        if msg != _log_last_error:
            print(msg, flush=True)
            _log_last_error = msg


def _report_upload_completion(state, session_only=False):
    # 送信完了の表示 (2026-11-21 のユーザー指示)。このサイクルで試合の
    # ファイルを実際に送信した後にだけ呼ばれる。残っている未送信
    # ファイルを数え、全部送れていれば完了を表示し、備考待ちだけが
    # 残っていればその旨を表示する (「全部終わった」と誤解させない)。
    # 備考待ち以外の未送信が残っている場合は何も出さない。
    # 自動送信 (session_only) では、起動前から残っている試合 (滞留分)
    # は数えない (自動処理の対象外のため、入力待ちとは表示しない)
    try:
        names = sorted(n for n in os.listdir(LOG_DIR) if _is_upload_target(n))
    except OSError:
        return
    group_mtimes = _battle_group_mtimes(names) if session_only else {}
    held = set()
    other = 0
    for n in names:
        key = _battle_key(n)
        if (session_only and key is not None
                and not _in_session_scope(
                    _gate_key(key),
                    group_mtimes.get(_gate_key(key), 0.0))):
            continue
        try:
            data = open(os.path.join(LOG_DIR, n), "rb").read()
        except OSError:
            continue
        if state.get(n) == hashlib.sha256(data).hexdigest():
            continue
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


class QuietHTTPServer(http.server.ThreadingHTTPServer):
    # クライアント側の切断 (ブラウザが大きなファイルの取得を中断
    # して再試行した、タブを閉じた等) で copyfile が送る
    # BrokenPipeError 等は無害なので、トレースバックを出さずに
    # 静かに処理する。それ以外のハンドラ例外は従来どおり表示し、
    # クラッシュジャーナルにも残す (2026-11-22、ユーザーの報告:
    # data/vgc_pastes.json の取得中断でトレースバックが表示された)
    def handle_error(self, request, client_address):
        exc = sys.exc_info()[1]
        if isinstance(exc, (BrokenPipeError, ConnectionResetError,
                            ConnectionAbortedError)):
            return
        _record_crash("http_handler", exc)
        super().handle_error(request, client_address)


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
        if path == "/inference_log":
            # 型推定エンジンの推論過程ログの受け口 (UI が対戦分を
            # 蓄積して送る)。その試合のファイル一式の一部として
            # logs/battle_<試合キー>_inference.json に保存し、備考
            # ゲート付きで試合ログと一緒に送る。UI は 2xx 以外を
            # 失敗として扱うため、失敗時は必ず非 2xx を返す
            try:
                length = int(self.headers.get("Content-Length") or 0)
            except ValueError:
                length = 0
            if length <= 0:
                self.send_error(400)
                return
            if length > 10 * 1024 * 1024:
                self.send_error(413)
                return
            body = self.rfile.read(length)
            try:
                name = _save_inference_log(body)
            except ValueError:
                self.send_error(400)
                return
            except Exception as e:
                _record_crash("inference_log_save", e)
                self.send_error(500)
                return
            payload = json.dumps({"ok": True, "file": name}).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(payload)))
            self.end_headers()
            self.wfile.write(payload)
            return
        if path == "/calclog":
            # ダメ計ログの受け口 (UI が試合中の計算記録を蓄積して送る)。
            # 推論過程ログと同型: その試合のファイル一式の一部として
            # logs/battle_<試合キー>_calclog.json に保存し、備考
            # ゲート付きで試合ログと一緒に送る。UI は 2xx 以外を
            # 失敗として扱うため、失敗時は必ず非 2xx を返す
            try:
                length = int(self.headers.get("Content-Length") or 0)
            except ValueError:
                length = 0
            if length <= 0:
                self.send_error(400)
                return
            if length > 10 * 1024 * 1024:
                self.send_error(413)
                return
            body = self.rfile.read(length)
            try:
                name = _save_calc_log(body)
            except ValueError:
                self.send_error(400)
                return
            except Exception as e:
                _record_crash("calc_log_save", e)
                self.send_error(500)
                return
            payload = json.dumps({"ok": True, "file": name}).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(payload)))
            self.end_headers()
            self.wfile.write(payload)
            return
        if path == "/presets":
            # チームプリセットの共有 (localhost の UI からストア全体
            # が POST される)。検証して presets.json に保存し、既存の
            # GitHub 経路でリポジトリ直下の presets.json へ即時反映
            # する。備考ゲートの対象外。結果は JSON で返す
            try:
                length = int(self.headers.get("Content-Length") or 0)
            except ValueError:
                length = 0
            if length <= 0:
                status, payload_obj = 400, {"ok": False, "error": "empty body"}
            elif length > _PRESETS_MAX_BYTES:
                # 本体を読まずに返すと接続がリセットされ、送信側が
                # 413 を受け取れないことがあるため、適度な量までは
                # 読み捨ててから返す
                if length <= 8 * 1024 * 1024:
                    remaining = length
                    while remaining > 0:
                        chunk = self.rfile.read(min(65536, remaining))
                        if not chunk:
                            break
                        remaining -= len(chunk)
                status, payload_obj = 413, {"ok": False, "error": "too large"}
            else:
                body = self.rfile.read(length)
                try:
                    status, payload_obj = _save_and_upload_presets(body)
                except Exception as e:
                    _record_crash("presets_save", e)
                    status, payload_obj = 500, {"ok": False, "error": str(e)}
            if status == 200:
                print("[log] プリセットを受け取り、リポジトリへ反映しました",
                      flush=True)
            payload = json.dumps(payload_obj).encode()
            self.send_response(status)
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
        if session_only and not _in_session_scope(p["key"], p.get("mtime", 0)):
            # 自動プロンプトでは、このプロセスの起動前に終わっていた
            # 試合は扱わない (2026-11-21 のユーザー指示: 起動時に
            # 過去分の備考解消が始まらないようにする。滞留分は Mac
            # 側にそのまま残り、手動の --note でのみ扱う。手動経路
            # (session_only=False) では従来どおり聞く)
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
        upload_logs_once(session_only=session_only)
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


# 備考プロンプトの入力待ち上限 (秒)。表示からこの時間入力がなければ
# 備考は空欄として送信に進む (入力待ちで止まり続けないため)
_NOTE_PROMPT_TIMEOUT_SEC = 30.0

# プロンプト表示中の割り込み検出 (2026-11-21 のユーザー追加指示)。
# 入力待ちの間に別の処理のログ出力がターミナルに流れると、入力行が
# 崩れて何を入力したか分からなくなる。その場合は入力を無効とし、
# 空欄の備考として送信に進む。検出は、プロンプトを表示している
# スレッド以外からの標準出力があったことをもって割り込みとする
# (_InterruptDetectStdout が sys.stdout に被せるラッパー)。
_prompt_owner_thread = None
_prompt_interrupted = False


class _InterruptDetectStdout:
    """sys.stdout のラッパー。備考プロンプトの入力待ち中に、
    プロンプト以外のスレッドから (空白だけではない) 出力があったら
    _prompt_interrupted を立てる。それ以外は素通しする。"""

    def __init__(self, real):
        self._real = real

    def write(self, s):
        global _prompt_interrupted
        if (s and s.strip() and _prompt_owner_thread is not None
                and threading.get_ident() != _prompt_owner_thread):
            _prompt_interrupted = True
        return self._real.write(s)

    def __getattr__(self, name):
        return getattr(self._real, name)


def _read_line_with_timeout(in_stream, deadline):
    """deadline (time.monotonic) までに 1 行読む。

    タイムアウト時は None を返し、EOF では EOFError を送出する。
    select が使えないストリーム (疑似ストリーム等) では通常の
    readline にフォールバックする (タイムアウトなし)。
    端末はカノニカルモードのため、行が確定するまで読み取り可能に
    ならない。fd を直接読むのは、バッファ済みリーダだと select で
    検知できないため (プロンプト表示前に _flush_typeahead で入力は
    破棄されており、このストリームの読み手はプロンプトだけ)。
    """
    try:
        fd = in_stream.fileno()
    except Exception:
        fd = None
    if fd is None or fd < 0:
        line = in_stream.readline()
        if line == "":
            raise EOFError("note prompt input closed")
        return line
    buf = b""
    while True:
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            return None
        try:
            ready, _, _ = select.select([fd], [], [], remaining)
        except (OSError, ValueError):
            line = in_stream.readline()
            if line == "":
                raise EOFError("note prompt input closed")
            return line
        if not ready:
            return None
        chunk = os.read(fd, 1)
        if chunk == b"":
            raise EOFError("note prompt input closed")
        buf += chunk
        if chunk == b"\n":
            break
    return buf.decode("utf-8", errors="replace")


def _prompt_input(in_stream, out_stream, prompt):
    """プロンプトを確実に表示 (flush) してから 1 行読む。

    表示前のタイプアヘッドは破棄し、表示後に入力された行だけを
    受け付ける。防御の重ねとして、表示から不自然に早く (0.5 秒未満で)
    返った行はバッファ残りの疑いとして 1 回だけ破棄して聞き直す
    (2 回目は速くても受け付ける)。入力が確定したら、表示からの
    経過時間をターミナルに残す。

    表示から _NOTE_PROMPT_TIMEOUT_SEC 秒入力がなければ、空欄の
    備考として扱って空文字列を返す (聞き直しにまたがって同じ
    締め切りを使う)。手動の `serve.py --note` も同じ経路を使う
    ため、そちらにも同じタイムアウトが効く。

    入力待ちの間に別の処理のログ出力が割り込んだ場合 (入力行が
    崩れた場合) も、その入力は無効として空文字列を返す。
    """
    global _prompt_owner_thread, _prompt_interrupted
    _prompt_owner_thread = threading.get_ident()
    _prompt_interrupted = False
    try:
        deadline = time.monotonic() + _NOTE_PROMPT_TIMEOUT_SEC
        for attempt in (1, 2):
            _flush_typeahead(in_stream)
            started = time.monotonic()
            out_stream.write(prompt)
            out_stream.flush()
            line = _read_line_with_timeout(in_stream, deadline)
            if line is None:
                print(f"[log] プロンプト表示から {_NOTE_PROMPT_TIMEOUT_SEC:.0f} 秒間"
                      "入力がなかったため、備考なしで送信します", flush=True)
                return ""
            if _prompt_interrupted:
                print("[log] 入力中に他の出力が割り込んだため、"
                      "この備考は無効として備考なしで送信します", flush=True)
                return ""
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
    finally:
        _prompt_owner_thread = None


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
    # 備考プロンプト表示中の割り込み出力の検出 (サーバ経路・手動
    # --note 経路の両方に効かせる)
    sys.stdout = _InterruptDetectStdout(sys.stdout)
    if "--note" in sys.argv:
        # 備考を付けて送るだけの手動コマンド (サーバは起動しない)
        raise SystemExit(cli_send_notes())
    check_log_token()
    # 起動前から残っている備考待ち (滞留分) は、この起動では処理
    # しない。その旨だけを 1 行知らせる (2026-11-21 のユーザー指示)
    try:
        _pending_startup = list_pending_log_notes()
        _carried = [p for p in _pending_startup
                    if p["key"] in _CARRIED_NOTE_KEYS]
        if _carried:
            print(f"[log] 再起動から引き継いだ備考待ちの試合が {len(_carried)} 件あります。"
                  "この起動でも続けて処理します", flush=True)
        _backlog = [p for p in _pending_startup
                    if not _in_session_scope(p["key"], p.get("mtime", 0))]
        if _backlog:
            print(f"[log] 起動前から残っている備考待ちの試合が {len(_backlog)} 件あります。"
                  "この起動では処理しません (手動で送る場合は別のターミナルで "
                  "python3 serve.py --note を実行してください)", flush=True)
    except Exception:
        pass
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
        server = QuietHTTPServer(("127.0.0.1", 8765), handler)
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
