#!/usr/bin/env python3
# Pins the per-battle folder layout of the Mac-side logs folder:
# new files land in logs/battle_<key>/, collection reads folders
# and the legacy flat layout, uploads keep flat names, and the
# startup migration moves the flat stock into folders (move only).
import importlib.util
import json
import os
import sys
import tempfile
from datetime import datetime, timedelta, timezone

HERE = os.path.dirname(os.path.abspath(__file__))
SERVE = os.path.join(HERE, "..", "serve.py")

spec = importlib.util.spec_from_file_location("serve", SERVE)
serve = importlib.util.module_from_spec(spec)
spec.loader.exec_module(serve)
# このスイートは保持された送信・備考機構を新しい配置で検証する
serve._NOTE_GATE_ENABLED = True
serve._AUTO_UPLOAD_ENABLED = True
serve._LIMIT_TERMINAL_OUTPUT = False

FAILURES = []


def check(name, cond):
    print(("PASS " if cond else "FAIL ") + name)
    if not cond:
        FAILURES.append(name)


class FakeGH:
    def __init__(self):
        self.puts = []

    def get_file(self, path, token):
        return None, None

    def put_file(self, path, data, token, msg, sha=None):
        self.puts.append(path)
        return "sha-" + path


KEY = (datetime.now(timezone(timedelta(hours=9)))
       + timedelta(seconds=10)).strftime("%Y%m%d_%H%M%S")
FLAT_FINAL = f"battle_{KEY}_final.log"
FLAT_PROTO = f"battle_{KEY}_final_protocol.log"

tmp = tempfile.mkdtemp()
serve.LOG_DIR = tmp
folder = os.path.join(tmp, f"battle_{KEY}")
os.makedirs(folder)


def write(path, text="x\n"):
    with open(path, "w", encoding="utf-8") as f:
        f.write(text)


# --- the map: folders first, legacy flat accepted ---------------------------
write(os.path.join(folder, FLAT_FINAL))
write(os.path.join(folder, FLAT_PROTO))
write(os.path.join(tmp, f"battle_{KEY}_debug01.jpg"))
paths = serve._log_file_map()
check("folder file is mapped by its flat name",
      paths.get(FLAT_FINAL) == os.path.join(folder, FLAT_FINAL))
check("legacy flat file is mapped too",
      paths.get(f"battle_{KEY}_debug01.jpg")
      == os.path.join(tmp, f"battle_{KEY}_debug01.jpg"))
write(os.path.join(tmp, FLAT_PROTO), "legacy\n")
paths = serve._log_file_map()
check("folder wins over a flat namesake",
      paths.get(FLAT_PROTO) == os.path.join(folder, FLAT_PROTO))
os.remove(os.path.join(tmp, FLAT_PROTO))

check("gate holds the folder battle before its note",
      KEY not in serve._unsent_ready_battle_keys())

# --- uploads keep flat names --------------------------------------------------
gh = FakeGH()
serve._gh_get_file = gh.get_file
serve._gh_put_file = gh.put_file
serve._log_token = lambda: "token"
serve._encrypt_log = lambda data: b"enc:" + data
serve._note_prompt_waiting = False
serve.save_log_note(KEY, "メモ")
check("note is written into the folder",
      os.path.exists(os.path.join(folder, f"battle_{KEY}_note.txt")))
check("note is found in the folder", serve._note_exists(KEY))
check("folder battle is sendable-ready once noted",
      KEY in serve._unsent_ready_battle_keys())
serve._upload_logs_once_locked(session_only=True)
sent_names = [p.rsplit("/", 1)[-1].removesuffix(".enc") for p in gh.puts]
check("folder files are uploaded", FLAT_FINAL in sent_names)
check("upload names stay flat",
      all(f"battle_{KEY}/" not in p for p in gh.puts))

# --- writers land in the folder ----------------------------------------------
serve._save_inference_log(json.dumps(
    {"battle": KEY, "entries": []}).encode())
check("inference log is written into the folder",
      os.path.exists(os.path.join(folder, f"battle_{KEY}_inference.json")))
serve._save_calc_log(json.dumps({"battle": KEY, "entries": []}).encode())
check("calc log is written into the folder",
      os.path.exists(os.path.join(folder, f"battle_{KEY}_calclog.json")))

# --- migration ------------------------------------------------------------------
tmp2 = tempfile.mkdtemp()
serve.LOG_DIR = tmp2
OLD = "20261120_010203"
write(os.path.join(tmp2, f"battle_{OLD}_final.log"))
write(os.path.join(tmp2, f"battle_{OLD}_obs.jsonl"))
write(os.path.join(tmp2, "preview_test_20261120_020000.jpg"))
write(os.path.join(tmp2, "preview_test_20261120_020000.json"))
write(os.path.join(tmp2, "serve_crashes.log"))
write(os.path.join(tmp2, "sent_battles.json"), "[]")
serve._migrate_logs_into_folders()
check("migration moves battle files into the folder",
      os.path.exists(os.path.join(tmp2, f"battle_{OLD}",
                                  f"battle_{OLD}_final.log"))
      and not os.path.exists(os.path.join(tmp2, f"battle_{OLD}_final.log")))
check("migration moves preview tests into their folder",
      os.path.exists(os.path.join(tmp2, "preview_test_20261120_020000",
                                  "preview_test_20261120_020000.jpg")))
check("non-battle files stay at the root",
      os.path.exists(os.path.join(tmp2, "serve_crashes.log"))
      and os.path.exists(os.path.join(tmp2, "sent_battles.json")))
write(os.path.join(tmp2, f"battle_{OLD}_final_protocol.log"))
write(os.path.join(tmp2, f"battle_{OLD}", f"battle_{OLD}_final_protocol.log"),
      "folder version\n")
serve._migrate_logs_into_folders()
check("migration never overwrites a folder file",
      open(os.path.join(tmp2, f"battle_{OLD}",
                        f"battle_{OLD}_final_protocol.log")).read()
      == "folder version\n"
      and os.path.exists(os.path.join(tmp2,
                                      f"battle_{OLD}_final_protocol.log")))
serve._migrate_logs_into_folders()
check("migration is idempotent",
      os.path.exists(os.path.join(tmp2, f"battle_{OLD}",
                                  f"battle_{OLD}_obs.jsonl")))

print(f"FAILURES: {len(FAILURES)}")
sys.exit(1 if FAILURES else 0)
