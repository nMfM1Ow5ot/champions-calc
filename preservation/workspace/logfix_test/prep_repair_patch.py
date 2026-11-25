#!/usr/bin/env python3
"""serve.py: 同期対象ファイルの自己修復 (VGCPastes が Mac に届かない問題)。
使い方: python3 prep_repair_patch.py [apply]"""
import sys

PATH = "/home/hatch/workspace/champions_calc/serve.py"
src = open(PATH).read()
EDITS = []

# 1. 自己修復の本体を self_hash の直後に追加
EDITS.append((
"""def self_hash():
    try:
        with open(SELF_PATH, "rb") as f:
            return hashlib.sha256(f.read()).hexdigest()
    except OSError:
        return None""",
"""def self_hash():
    try:
        with open(SELF_PATH, "rb") as f:
            return hashlib.sha256(f.read()).hexdigest()
    except OSError:
        return None


# ---- 同期対象ファイルの自己修復 ----
# Mac 側の同期 (sync_ui.py) は、自分の知っているファイルの一覧
# (MANIFEST) にあるものしか取り込まない。新しいファイルを同期対象
# に加えても、その一覧の更新は ZIP の適用でしか Mac に届かないため、
# ZIP 未適用の間は新しいファイル (例: data/vgc_pastes.json) が Mac
# に永遠に届かず、UI が読み込めない (実例: 2026-11-22、VGCPastes
# コーパスがダメ計で読み込めない問題)。serve.py 自身は同期で更新
# されるため、こちら側で「公開マニフェストにあってローカルに無い
# (または内容が違う) ファイル」を補うことで、ユーザーの追加操作
# なしに自己修復できるようにする。my_team.json (ローカル編集の
# 保護対象) と serve.py 自身 (再起動の仕組みが管理) は対象外
_SYNC_RAW_BASE = "https://raw.githubusercontent.com/nMfM1Ow5ot/champions-calc/main/"
_SYNC_REPAIR_EXCLUDE = {"my_team.json", "serve.py"}
_SYNC_BASE = os.path.dirname(SELF_PATH)
_last_missing_repair_at = -1e9


def _repair_missing_synced_files():
    \"\"\"公開マニフェストにあってローカルで不足しているファイルを補う。

    補った相対パスのリストを返す。ネットワーク失敗時は空リストで、
    例外は外へ出さない (同期スレッドを止めないため)。\"\"\"
    repaired = []
    try:
        req = urllib.request.Request(_SYNC_RAW_BASE + "ui_manifest.json",
                                     headers={"User-Agent": "champions-calc-serve"})
        with urllib.request.urlopen(req, timeout=20) as r:
            doc = json.loads(r.read().decode("utf-8"))
        remote_files = doc.get("files") if isinstance(doc, dict) else None
        if not isinstance(remote_files, dict):
            return repaired
        for rel, want in sorted(remote_files.items()):
            if rel in _SYNC_REPAIR_EXCLUDE or not isinstance(want, str):
                continue
            path = os.path.join(_SYNC_BASE, rel)
            try:
                if os.path.exists(path):
                    with open(path, "rb") as f:
                        if hashlib.sha256(f.read()).hexdigest() == want:
                            continue
            except OSError:
                continue
            try:
                req = urllib.request.Request(_SYNC_RAW_BASE + rel,
                                             headers={"User-Agent": "champions-calc-serve"})
                with urllib.request.urlopen(req, timeout=60) as r:
                    data = r.read()
            except Exception:
                continue
            if hashlib.sha256(data).hexdigest() != want:
                continue
            try:
                os.makedirs(os.path.dirname(path), exist_ok=True)
                tmp = path + ".tmp"
                with open(tmp, "wb") as f:
                    f.write(data)
                os.replace(tmp, path)
                if rel.endswith(".sh"):
                    os.chmod(path, 0o755)
                repaired.append(rel)
            except OSError:
                continue
        if repaired and not _note_prompt_waiting:
            # プロンプト表示中にこの表示を出すと割り込み出力になって
            # 入力を無効化するため、表示中は出さない (補充自体は行う)
            print("[sync] 同期の対象外だったファイルを補いました: " + ", ".join(repaired), flush=True)
    except Exception:
        return repaired
    return repaired


def _maybe_repair_missing_synced_files():
    global _last_missing_repair_at
    now = time.monotonic()
    if now - _last_missing_repair_at < 600:
        return
    _last_missing_repair_at = now
    _repair_missing_synced_files()"""))

# 2. 起動時の同期の直後に自己修復を回す
EDITS.append((
"""    try:
        maybe_restart_self()
    except Exception:
        print("[sync] serve.py の自動再起動に失敗しました。次回同期時に再試行します", flush=True)
    upload_logs_once(session_only=True)""",
"""    try:
        maybe_restart_self()
    except Exception:
        print("[sync] serve.py の自動再起動に失敗しました。次回同期時に再試行します", flush=True)
    _maybe_repair_missing_synced_files()
    upload_logs_once(session_only=True)"""))

# 3. 周期側 (対戦中・プロンプト中でない周期) でも自己修復を回す
EDITS.append((
"""                run_sync(False)
                try:
                    maybe_restart_self()
                except Exception:
                    print("[sync] serve.py の自動再起動に失敗しました。次回同期時に再試行します", flush=True)""",
"""                run_sync(False)
                try:
                    maybe_restart_self()
                except Exception:
                    print("[sync] serve.py の自動再起動に失敗しました。次回同期時に再試行します", flush=True)
                _maybe_repair_missing_synced_files()"""))

apply = len(sys.argv) > 1 and sys.argv[1] == "apply"
bad = 0
for i, (old, new) in enumerate(EDITS):
    n = src.count(old)
    print(f"edit {i + 1}: anchor count = {n}")
    if n != 1:
        bad += 1
        continue
    if apply:
        src = src.replace(old, new, 1)
if bad:
    print(f"{bad} anchors not unique/found — aborting")
    sys.exit(1)
if apply:
    open(PATH, "w").write(src)
    print("applied all", len(EDITS), "edits")
else:
    print("dry run ok:", len(EDITS), "edits ready")
