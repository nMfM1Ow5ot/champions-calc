#!/usr/bin/env python3
# Terminal-output limitation, remaining items (user decision 案B:
# suppress normal-path displays, keep abnormal warnings).
# - start_all.sh: routine echoes go through a gated helper.
# - sync_ui.py: normal [sync] prints (progress/success) go through
#   a gated helper; failure/warning prints stay as they are.
# Switch-style, suppression ON, no "disabled" notice. Delegated by
# the comprehensive chat on the user's explicit instruction.
import sys

def patch(path, edits):
    src = open(path, encoding="utf-8").read()
    orig = src
    for old, new, tag, count in edits:
        n = src.count(old)
        if n != count:
            print(f"ABORT {tag}: anchor count = {n} (expected {count}) in {path}")
            sys.exit(1)
        src = src.replace(old, new)
        print(f"OK {tag}")
    if src == orig:
        print(f"ABORT: no changes in {path}")
        sys.exit(1)
    open(path, "w", encoding="utf-8").write(src)
    print("WROTE", path)

SH = "/home/hatch/workspace/champions_calc/start_all.sh"
patch(SH, [
    ('''cd "$(dirname "$0")"
''',
     '''cd "$(dirname "$0")"

# 通常系の表示 (起動の進行・案内など) の抑止スイッチ。true の間は
# 通常系の echo を出さない。異常系の警告 (起動直後の繰り返し終了・
# 予期せぬ終了) は常に出す。表示を戻すには false に変える
LIMIT_TERMINAL_OUTPUT=true
echo_info() {
  if [ "$LIMIT_TERMINAL_OUTPUT" != "true" ]; then
    echo "$@"
  fi
}
''', "sh switch", 1),
    ('  echo "起動中の旧サーバを停止します (PID: $OLD)"',
     '  echo_info "起動中の旧サーバを停止します (PID: $OLD)"', "sh old server", 1),
    ('echo "最新のファイルに同期します..."',
     'echo_info "最新のファイルに同期します..."', "sh sync", 1),
    ('  echo "現在の rev (同期対象一式): $REV"',
     '  echo_info "現在の rev (同期対象一式): $REV"', "sh rev", 1),
    ('echo "UI はブラウザで http://localhost:8765/ui.html を開いてください (自動では開きません)"',
     'echo_info "UI はブラウザで http://localhost:8765/ui.html を開いてください (自動では開きません)"', "sh ui guide", 1),
    ('echo "リーダーを起動します (終了は Ctrl+C で両方止まります)"',
     'echo_info "リーダーを起動します (終了は Ctrl+C で両方止まります)"', "sh reader start", 1),
    ('    echo "リーダーを再起動します"',
     '    echo_info "リーダーを再起動します"', "sh reader restart", 1),
])

PY = "/home/hatch/workspace/champions_calc/sync_ui.py"
patch(PY, [
    ('''BASE = os.path.dirname(os.path.abspath(__file__))
''',
     '''BASE = os.path.dirname(os.path.abspath(__file__))

# 通常系の表示 (同期の進行・成功) の抑止スイッチ。True の間は
# 通常系の [sync] 表示を出さない。異常系の警告 (復号失敗・ハッシュ
# 不一致・取得失敗など) は常に出す。表示を戻すには False に変える
_LIMIT_TERMINAL_OUTPUT = True


def _info(message):
    if not _LIMIT_TERMINAL_OUTPUT:
        print(message)
''', "py switch", 1),
    ('        print("[sync] my_team.json はローカルで取り込み済みのため、オンライン版で上書きしません")',
     '        _info("[sync] my_team.json はローカルで取り込み済みのため、オンライン版で上書きしません")', "py myteam (both sites)", 2),
    ('        print("[sync] 更新しました: " + ", ".join(sorted(changed)))',
     '        _info("[sync] 更新しました: " + ", ".join(sorted(changed)))', "py updated (both sites)", 2),
])
