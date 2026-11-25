#!/usr/bin/env python3
"""serve.py の手動フラグ受け口 (POST /battle_flag) のテスト。

検証すること:
- 制御ファイルが無い場合は出荷状態 (manual、連番 0) を返す
- start / end の要求で連番が増え、応答の phase は見込み値になる
- mode の変更が保存され、不正な mode・action・JSON は 400
- toggle は state.json の battlePhase で作用が決まり、phase 不明
  なら連番を増やさず 409 (phase_unknown) を返す
- HTTP 経由の POST でも同じく動き、応答 JSON の形が契約どおり

実行: python3 tests/test_battle_flag.py (全て PASS で終了コード 0)
"""
import http.client
import importlib.util
import json
import os
import sys
import tempfile
import threading

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


tmp = tempfile.mkdtemp()
serve.FLAG_CONTROL_PATH = os.path.join(tmp, "flag_control.json")
serve.STATE_JSON_PATH = os.path.join(tmp, "state.json")

# 1. ファイルが無い場合は出荷状態
ctrl = serve._read_flag_control()
check("absent file -> manual defaults",
      ctrl == {"mode": "manual", "startSeq": 0, "endSeq": 0})
resp = serve._flag_response()
check("response defaults", resp["ok"] and resp["phase"] == "idle"
      and resp["mode"] == "manual" and resp["startSeq"] == 0)

# 2. start で連番が増え、見込み phase は inBattle
status, resp = serve._apply_battle_flag(b'{"action": "start"}')
check("start ok", status == 200 and resp["phase"] == "inBattle"
      and resp["startSeq"] == 1)
status, resp = serve._apply_battle_flag(b'{"action": "start"}')
check("start again increments", status == 200 and resp["startSeq"] == 2)
ctrl = serve._read_flag_control()
check("start persisted", ctrl["startSeq"] == 2 and ctrl["endSeq"] == 0)

# 3. end で連番が増え、見込み phase は idle
status, resp = serve._apply_battle_flag(b'{"action": "end"}')
check("end ok", status == 200 and resp["phase"] == "idle"
      and resp["endSeq"] == 1)

# 4. mode の変更と検証
status, resp = serve._apply_battle_flag(b'{"action": "mode", "mode": "auto"}')
check("mode auto", status == 200 and resp["mode"] == "auto")
check("mode persisted", serve._read_flag_control()["mode"] == "auto")
status, _ = serve._apply_battle_flag(b'{"action": "mode", "mode": "x"}')
check("invalid mode -> 400", status == 400)
status, _ = serve._apply_battle_flag(b'{"action": "bogus"}')
check("unknown action -> 400", status == 400)
status, _ = serve._apply_battle_flag(b'not json')
check("invalid json -> 400", status == 400)

# 5. state.json の battlePhase が応答に反映される (mode の応答)
with open(serve.STATE_JSON_PATH, "w", encoding="utf-8") as f:
    json.dump({"battlePhase": "inBattle"}, f)
status, resp = serve._apply_battle_flag(b'{"action": "mode", "mode": "manual"}')
check("reported phase used", status == 200 and resp["phase"] == "inBattle")

# 6. toggle: 作用は state.json の battlePhase (権威ある値) で決まる
#    (この時点の連番は start 2 / end 1、state.json は inBattle)
status, resp = serve._apply_battle_flag(b'{"action": "toggle"}')
check("toggle inBattle -> end", status == 200 and resp["phase"] == "idle"
      and resp["endSeq"] == 2 and resp["startSeq"] == 2)
with open(serve.STATE_JSON_PATH, "w", encoding="utf-8") as f:
    json.dump({"battlePhase": "idle"}, f)
status, resp = serve._apply_battle_flag(b'{"action": "toggle"}')
check("toggle idle -> start", status == 200 and resp["phase"] == "inBattle"
      and resp["startSeq"] == 3 and resp["endSeq"] == 2)
os.remove(serve.STATE_JSON_PATH)
status, resp = serve._apply_battle_flag(b'{"action": "toggle"}')
check("toggle phase unknown -> 409", status == 409
      and resp == {"ok": False, "error": "phase_unknown"})
ctrl = serve._read_flag_control()
check("toggle 409 keeps seqs", ctrl["startSeq"] == 3 and ctrl["endSeq"] == 2)
with open(serve.STATE_JSON_PATH, "w", encoding="utf-8") as f:
    json.dump({"battlePhase": "weird"}, f)
status, _ = serve._apply_battle_flag(b'{"action": "toggle"}')
check("toggle invalid phase -> 409", status == 409)
ctrl = serve._read_flag_control()
check("toggle invalid phase keeps seqs",
      ctrl["startSeq"] == 3 and ctrl["endSeq"] == 2)
os.remove(serve.STATE_JSON_PATH)

# 7. HTTP 経由
server = serve.QuietHTTPServer(("127.0.0.1", 0), serve.QuietHandler)
port = server.server_address[1]
th = threading.Thread(target=server.serve_forever, daemon=True)
th.start()
try:
    conn = http.client.HTTPConnection("127.0.0.1", port, timeout=10)
    conn.request("POST", "/battle_flag", body=b'{"action": "start"}',
                 headers={"Content-Type": "application/json"})
    r = conn.getresponse()
    payload = json.loads(r.read().decode("utf-8"))
    check("http start", r.status == 200 and payload["ok"]
          and payload["phase"] == "inBattle" and payload["startSeq"] == 4)
    conn.request("POST", "/battle_flag", body=b'{"action": "bogus"}',
                 headers={"Content-Type": "application/json"})
    r = conn.getresponse()
    r.read()
    check("http bogus -> 400", r.status == 400)
    # state.json が無い状態での toggle は 409 (phase_unknown)
    conn.request("POST", "/battle_flag", body=b'{"action": "toggle"}',
                 headers={"Content-Type": "application/json"})
    r = conn.getresponse()
    payload = json.loads(r.read().decode("utf-8"))
    check("http toggle unknown -> 409", r.status == 409
          and payload == {"ok": False, "error": "phase_unknown"})
    conn.close()
finally:
    server.shutdown()

print("FAILURES: " + str(len(failures)))
sys.exit(1 if failures else 0)
