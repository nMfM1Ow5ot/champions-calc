#!/usr/bin/env python3
# serve.py patch: (1) suspend the note gate via a switch (manual
# --note path included); (2) limit terminal output to the
# send-completion log line via a print shadow (switch-based).
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

# V1: terminal output limiter (print shadow), after the path constants
rep('''FLAG_CONTROL_PATH = os.path.join(BASE_DIR, "flag_control.json")''',
    '''FLAG_CONTROL_PATH = os.path.join(BASE_DIR, "flag_control.json")

# terminal 表示の限定 (2026-11-23、ユーザーの指示で一時的に有効):
# 送信完了ログ以外の terminal 表示を出さない。このモジュール内の
# print は下の同名関数に解決され、限定中は送信完了ログの行だけを
# 通す。限定の解除は _LIMIT_TERMINAL_OUTPUT を False に戻すだけ
# (それ以外の表示経路には手を入れていない)。ファイルへの記録は
# terminal 表示ではないため対象外
_LIMIT_TERMINAL_OUTPUT = True
_builtin_print = print


def print(*args, **kwargs):
    if _LIMIT_TERMINAL_OUTPUT:
        text = " ".join(str(a) for a in args)
        if not (text.startswith("[log] battle_")
                and "の試合ログをすべて送信しました" in text):
            return
    _builtin_print(*args, **kwargs)''',
    "V1 print shadow")

# V2: note gate switch + choke point
rep('''_NOTE_GATE_SINCE = "20261121_131309"


def _note_gate_applies(key):
    """その試合に備考ゲートがかかるか (導入後に始まった試合だけ)。"""
    if not key:
        return False
    return key[:15] >= _NOTE_GATE_SINCE''',
    '''_NOTE_GATE_SINCE = "20261121_131309"

# 備考ゲートは、ユーザーの指示により一時的に無効化している
# (2026-11-23)。無効化中は備考の入力を待たず、試合が終了すれば
# 自動的に送信が始まる。手動の --note 経路も働かない。再有効化
# はこの値を True に戻すだけ (ゲートの仕組み自体は残してある)
_NOTE_GATE_ENABLED = False


def _note_gate_applies(key):
    """その試合に備考ゲートがかかるか (導入後に始まった試合だけ)。"""
    if not _NOTE_GATE_ENABLED or not key:
        return False
    return key[:15] >= _NOTE_GATE_SINCE''',
    "V2 note gate switch")

# V3: manual --note path is inert while the gate is suspended
rep('''    if "--note" in sys.argv:
        # 備考を付けて送るだけの手動コマンド (サーバは起動しない)
        raise SystemExit(cli_send_notes())''',
    '''    if "--note" in sys.argv:
        # 備考を付けて送るだけの手動コマンド (サーバは起動しない)。
        # 備考ゲートの無効化中は働かない
        raise SystemExit(cli_send_notes() if _NOTE_GATE_ENABLED else 0)''',
    "V3 --note guard")

if src == orig:
    print("ABORT: no changes")
    sys.exit(1)
open(PATH, "w", encoding="utf-8").write(src)
print("WROTE", PATH)
