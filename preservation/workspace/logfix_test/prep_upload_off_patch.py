#!/usr/bin/env python3
# serve.py patch: suspend ALL automatic log uploads via a single
# switch at the choke point (_upload_logs_once_locked). Local
# recording is untouched; nothing is marked sent while suspended.
# User instruction via the comprehensive chat, 2026-11-23.
import sys

PATH = "/home/hatch/workspace/champions_calc/serve.py"
src = open(PATH, encoding="utf-8").read()
orig = src

def rep(old, new, tag, count=1):
    global src
    n = src.count(old)
    if n != count:
        print(f"ABORT {tag}: anchor count = {n} (expected {count})")
        sys.exit(1)
    src = src.replace(old, new)
    print(f"OK {tag}")

rep('''_NOTE_GATE_ENABLED = False''',
    '''_NOTE_GATE_ENABLED = False

# ログの自動送信は、ユーザーの指示により一時的に無効化している
# (2026-11-23)。無効化中は送信処理が何も送らず、送信済みの記録
# も付けない。Mac ローカルへの記録 (logs フォルダへの保存) は
# 従来どおり続く。再有効化はこの値を True に戻すだけ (送信の
# 仕組み自体は残してある)
_AUTO_UPLOAD_ENABLED = False''',
    "W1 upload switch")

rep('''def _upload_logs_once_locked(session_only=False):
    global _log_notice_shown, _log_last_error
    if not os.path.isdir(LOG_DIR):
        return''',
    '''def _upload_logs_once_locked(session_only=False):
    global _log_notice_shown, _log_last_error
    if not _AUTO_UPLOAD_ENABLED:
        # 自動送信の無効化中は何も送らない (送信済みの記録も付けない)
        return
    if not os.path.isdir(LOG_DIR):
        return''',
    "W2 choke-point guard")

if src == orig:
    print("ABORT: no changes")
    sys.exit(1)
open(PATH, "w", encoding="utf-8").write(src)
print("WROTE", PATH)
