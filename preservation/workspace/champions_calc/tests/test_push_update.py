#!/usr/bin/env python3
# push_update.py の引き継ぎ方式マニフェストと中止系の検証。
# ネットワークには出ない (gh_put / 公開マニフェスト取得 / ゲート /
# セキュリティ確認をすべてスタブに差し替える)。
# 実行: python3 tests/test_push_update.py  (最後に ALL PASS と出す)
import copy
import hashlib
import io
import json
import os
import subprocess
import sys
import tempfile
from contextlib import redirect_stdout

BASE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, BASE)

import push_update
import security_check
import sync_ui

FAIL = []


def check(name, cond, detail=""):
    print(("PASS " if cond else "FAIL ") + name + (f" ({detail})" if detail and not cond else ""))
    if not cond:
        FAIL.append(name)


def sha(b):
    return hashlib.sha256(b).hexdigest()


# --- 作業用の一時 BASE (対象ファイルの実物を置く) ---
TMP = tempfile.mkdtemp(prefix="push_update_test_")
for rel, content in (("serve.py", b"# dummy serve\n"),
                     ("preview_test.sh", b"#!/bin/bash\ntrue\n"),
                     ("ui.html", b"<html>locally modified</html>\n")):
    with open(os.path.join(TMP, rel), "wb") as f:
        f.write(content)

BASE_FILES = {rel: "basehash:" + rel for rel in sync_ui.MANIFEST}
BASE_DOC = {"rev": "20261121_0000", "files": dict(BASE_FILES)}

real_run = subprocess.run
real_base = push_update.BASE


def run_main(argv, fetch_impl, put_hook=None, claims=None):
    """スタブ環境で main() を実行し、(SystemExit のコード or None,
    gh_put の記録 [(repo_path, 内容 or None)], 出力) を返す。"""
    puts = []

    def fake_put(repo_path, local_path, message):
        content = None
        if repo_path in ("ui_manifest.json", "ui_rev.txt"):
            content = open(local_path, "rb").read()
        puts.append((repo_path, content))
        print(f"  ↑ {repo_path}")
        if put_hook:
            put_hook(repo_path)

    def fake_run(cmd, *a, **kw):
        if any("run_checks.py" in str(x) for x in cmd):
            return subprocess.CompletedProcess(cmd, 0)
        return real_run(cmd, *a, **kw)

    state_path = os.path.join(TMP, ".edit_state.json")
    if claims is None:
        if os.path.exists(state_path):
            os.unlink(state_path)
    else:
        with open(state_path, "w", encoding="utf-8") as f:
            json.dump({"claims": claims}, f)

    saved = (push_update.BASE, push_update.gh_put,
             push_update.fetch_published_manifest,
             security_check.scan_files, subprocess.run, sys.argv)
    push_update.BASE = TMP
    push_update.gh_put = fake_put
    push_update.fetch_published_manifest = fetch_impl
    security_check.scan_files = lambda targets: []
    subprocess.run = fake_run
    sys.argv = ["push_update.py"] + argv
    out = io.StringIO()
    code = None
    try:
        with redirect_stdout(out):
            push_update.main()
    except SystemExit as e:
        code = e.code
    finally:
        (push_update.BASE, push_update.gh_put,
         push_update.fetch_published_manifest,
         security_check.scan_files, subprocess.run, sys.argv) = saved
    return code, puts, out.getvalue()


def fetch_ok():
    return copy.deepcopy(BASE_DOC)


# 1. 引き継ぎ: 対象外ファイル (ui.html) をローカルで書き換えた状態でも、
#    新マニフェストには公開中のハッシュが引き継がれ、対象 (serve.py) は
#    ローカル現物のハッシュになる。
code, puts, out = run_main(["serve.py", "--msg", "t"], fetch_ok)
check("通常 push が完了する", code is None, f"code={code} out={out[-300:]}")
paths = [p for p, _ in puts]
check("アップロード順序が 本体→マニフェスト→rev",
      paths == ["serve.py", "ui_manifest.json", "ui_rev.txt"], str(paths))
man = json.loads(dict(puts)["ui_manifest.json"].decode())
local_serve = sha(open(os.path.join(TMP, "serve.py"), "rb").read())
local_ui = sha(open(os.path.join(TMP, "ui.html"), "rb").read())
check("対象ファイルはローカル現物のハッシュ", man["files"]["serve.py"] == local_serve)
check("対象外の改変ファイルは公開ハッシュを引き継ぐ",
      man["files"]["ui.html"] == BASE_FILES["ui.html"] and local_ui != BASE_FILES["ui.html"])
check("対象外の未改変ファイルも公開ハッシュを引き継ぐ",
      man["files"]["reader.swift"] == BASE_FILES["reader.swift"])

# 2. build_manifest_carryover の単体確認 (対象が公開側に無くても入る)
doc = push_update.build_manifest_carryover("R", {"new_file.sh": "H"}, {"a": "1"})
check("引き継ぎマージ (新規対象を含む)", doc == {"rev": "R", "files": {"a": "1", "new_file.sh": "H"}})

# 3. 公開マニフェスト取得失敗 → 中止 (何も上げない)
def fetch_fail():
    raise RuntimeError("network down")
code, puts, out = run_main(["serve.py"], fetch_fail)
check("取得失敗で中止", code == 1 and puts == [] and "中止" in out, f"code={code} puts={puts}")

# 4. push 中に対象ファイルが書き換わる → 本体は上がるがマニフェスト/rev は上げない
def mutate(repo_path):
    if repo_path == "serve.py":
        with open(os.path.join(TMP, "serve.py"), "ab") as f:
            f.write(b"# changed mid-push\n")
code, puts, out = run_main(["serve.py"], fetch_ok, put_hook=mutate)
paths = [p for p, _ in puts]
check("push 中の書き換わりで中止 (マニフェスト/rev なし)",
      code == 1 and paths == ["serve.py"] and "書き換わりました" in out,
      f"code={code} paths={paths}")
# 元に戻す
with open(os.path.join(TMP, "serve.py"), "wb") as f:
    f.write(b"# dummy serve\n")

# 5. 公開 rev の割り込み → マニフェスト/rev を上げずに中止
calls = {"n": 0}
def fetch_interleave():
    calls["n"] += 1
    doc = copy.deepcopy(BASE_DOC)
    if calls["n"] >= 2:
        doc["rev"] = "20261121_9999"
    return doc
code, puts, out = run_main(["serve.py"], fetch_interleave)
paths = [p for p, _ in puts]
check("rev 割り込みで中止 (マニフェスト/rev なし)",
      code == 1 and paths == ["serve.py"] and "割り込んだ" in out,
      f"code={code} paths={paths}")

# 6. 公開マニフェストに項目が無い対象外ファイル → 異常として中止
def fetch_missing():
    doc = copy.deepcopy(BASE_DOC)
    del doc["files"]["ui.html"]
    return doc
code, puts, out = run_main(["serve.py"], fetch_missing)
check("公開側に項目が無い対象外ファイルで中止",
      code == 1 and puts == [] and "ui.html" in out, f"code={code} puts={puts}")

# 7. 編集状態: 対象ファイルに他チャットの記録 → 競合として中止
claims = [{"file": "serve.py", "chat": "other-chat",
           "started": "2026-11-21T17:00:00+09:00", "memo": ""}]
code, puts, out = run_main(["serve.py", "--as", "919e769f"], fetch_ok, claims=claims)
check("他チャット編集中の対象ファイルは競合で中止",
      code == 1 and puts == [] and "競合" in out, f"code={code} puts={puts}")

# 8. 編集状態: 自分の記録なら push できる / 対象外の他チャット記録は警告のみ
claims_self = [{"file": "serve.py", "chat": "919e769f",
                "started": "2026-11-21T17:00:00+09:00", "memo": ""}]
code, puts, out = run_main(["serve.py", "--as", "919e769f"], fetch_ok, claims=claims_self)
check("自分の編集中記録がある対象ファイルは push できる", code is None, f"code={code}")
claims_other = [{"file": "ui.html", "chat": "other-chat",
                 "started": "2026-11-21T17:00:00+09:00", "memo": ""}]
code, puts, out = run_main(["serve.py", "--as", "919e769f"], fetch_ok, claims=claims_other)
check("対象外の編集中記録は警告のみで続行",
      code is None and "警告" in out, f"code={code} out={out[-200:]}")

push_update.BASE = real_base

print("FAILURES:", FAIL if FAIL else "none")
print("ALL PASS" if not FAIL else "SOME FAILED")
sys.exit(1 if FAIL else 0)
