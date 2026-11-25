#!/usr/bin/env python3
"""serve.py の「同期対象ファイルの自己修復」のテスト。

Mac 側の sync_ui.py が知らないファイル (公開マニフェストにあって
ローカルに無いファイル) を、serve.py が補えることを検証する
(2026-11-22、data/vgc_pastes.json が Mac に届かない問題)。

検証すること:
- 無いファイルはダウンロードされ、ハッシュ検証のうえで書かれる
- 内容が正しいファイルには触らない (ダウンロードもしない)
- 内容が違うファイルは取り直される
- my_team.json と serve.py は、無くても補わない (対象外)
- ダウンロード内容のハッシュが合わなければ書かない
- マニフェストの取得に失敗しても例外なく空で返る

実行: python3 tests/test_missing_repair.py (全て PASS で終了コード 0)
"""
import hashlib
import importlib.util
import json
import os
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location(
    "serve", os.path.join(HERE, "..", "serve.py"))
serve = importlib.util.module_from_spec(spec)
spec.loader.exec_module(serve)

failures = []


def check(name, cond):
    print(("PASS " if cond else "FAIL ") + name)
    if not cond:
        failures.append(name)


def sha(b):
    return hashlib.sha256(b).hexdigest()


class Resp:
    def __init__(self, data):
        self.data = data

    def read(self):
        return self.data

    def __enter__(self):
        return self

    def __exit__(self, *a):
        return False


BASE = "https://raw.githubusercontent.com/nMfM1Ow5ot/champions-calc/main/"
requested = []
routes = {}


def fake_urlopen(req, timeout=None):
    url = req.full_url
    requested.append(url)
    if url not in routes:
        raise OSError("no route: " + url)
    data = routes[url]
    if isinstance(data, Exception):
        raise data
    return Resp(data)


serve.urllib.request.urlopen = fake_urlopen

tmp = tempfile.mkdtemp()
serve._SYNC_BASE = tmp
serve._LIVE_SERVER = True
serve._note_prompt_waiting = False

corpus = b'{"teams": [], "sets": []}'
good = b"already here"
manifest = {"files": {
    "data/vgc_pastes.json": sha(corpus),
    "data/good.json": sha(good),
    "data/stale.json": sha(b"fresh content"),
    "my_team.json": sha(b"team"),
    "serve.py": sha(b"serve"),
    "data/broken.json": sha(b"expected bytes"),
}}
routes[BASE + "ui_manifest.json"] = json.dumps(manifest).encode()
routes[BASE + "data/vgc_pastes.json"] = corpus
routes[BASE + "data/good.json"] = good
routes[BASE + "data/stale.json"] = b"fresh content"
routes[BASE + "data/broken.json"] = b"different bytes"

os.makedirs(os.path.join(tmp, "data"))
with open(os.path.join(tmp, "data", "good.json"), "wb") as f:
    f.write(good)
with open(os.path.join(tmp, "data", "stale.json"), "wb") as f:
    f.write(b"old content")

repaired = serve._repair_missing_synced_files()

check("missing corpus repaired", "data/vgc_pastes.json" in repaired
      and open(os.path.join(tmp, "data", "vgc_pastes.json"), "rb").read() == corpus)
check("good file untouched", "data/good.json" not in repaired
      and (BASE + "data/good.json") not in requested)
check("stale file refreshed", "data/stale.json" in repaired
      and open(os.path.join(tmp, "data", "stale.json"), "rb").read() == b"fresh content")
check("excluded files not fetched", (BASE + "my_team.json") not in requested
      and (BASE + "serve.py") not in requested
      and not os.path.exists(os.path.join(tmp, "my_team.json")))
check("hash mismatch not written", "data/broken.json" not in repaired
      and not os.path.exists(os.path.join(tmp, "data", "broken.json")))

routes[BASE + "ui_manifest.json"] = OSError("network down")
check("manifest failure tolerated", serve._repair_missing_synced_files() == [])

print()
if failures:
    print(f"{len(failures)} FAILURES")
    sys.exit(1)
print("ALL PASS")
