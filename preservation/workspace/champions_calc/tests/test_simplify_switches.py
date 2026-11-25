#!/usr/bin/env python3
# Pins the shipped (suspended) state of the 2026-11-23 simplification:
# the note gate is off (battles send without a note) and terminal
# output is limited to the send-completion log line. The retained
# gate machinery itself is verified by the older suites, which now
# enable the gate explicitly in their setup.
import contextlib
import importlib.util
import io
import os
import sys
import tempfile
from datetime import datetime, timedelta, timezone

HERE = os.path.dirname(os.path.abspath(__file__))
SERVE = os.path.join(HERE, "..", "serve.py")

spec = importlib.util.spec_from_file_location("serve", SERVE)
serve = importlib.util.module_from_spec(spec)
spec.loader.exec_module(serve)

FAILURES = []


def check(name, cond):
    print(("PASS " if cond else "FAIL ") + name)
    if not cond:
        FAILURES.append(name)


# --- note gate: shipped state is off -------------------------------------
check("gate switch shipped off", serve._NOTE_GATE_ENABLED is False)
# battle keys are JST stamps (the app's clock), regardless of this
# machine's timezone; a few seconds past the process start, as a
# real battle would be (key resolution is one second)
key = (datetime.now(timezone(timedelta(hours=9)))
       + timedelta(seconds=10)).strftime("%Y%m%d_%H%M%S")
check("gate does not apply to a post-cutoff battle",
      serve._note_gate_applies(key) is False)
check("gate does not apply to a pre-cutoff battle",
      serve._note_gate_applies("20261120_000000") is False)

tmp = tempfile.mkdtemp()
serve.LOG_DIR = tmp
for suffix in ("_final.log", "_final_protocol.log"):
    with open(os.path.join(tmp, f"battle_{key}{suffix}"), "w") as f:
        f.write("x\n")
check("no note file yet", not serve._note_exists_any(key))
check("battle is sendable without a note", key in serve._unsent_ready_battle_keys())
check("uploads are not blocked for a note", serve._note_blocking() is False)

# --- terminal output limiter ----------------------------------------------
check("limiter shipped on", serve._LIMIT_TERMINAL_OUTPUT is True)
buf = io.StringIO()
with contextlib.redirect_stdout(buf):
    serve.print("[sync] なにか")
    serve.print("通常の表示", flush=True)
check("ordinary output is suppressed", buf.getvalue() == "")

line = f"[log] battle_{key} の試合ログをすべて送信しました（2026-11-23 09:00:00）"
buf = io.StringIO()
with contextlib.redirect_stdout(buf):
    serve.print(line, flush=True)
check("completion log passes through", buf.getvalue() == line + "\n")

serve._LIMIT_TERMINAL_OUTPUT = False
buf = io.StringIO()
with contextlib.redirect_stdout(buf):
    serve.print("通常の表示")
check("limiter off restores output", buf.getvalue() == "通常の表示\n")
serve._LIMIT_TERMINAL_OUTPUT = True

# --- automatic uploads: shipped state is off -------------------------------


class FakeGH:
    def __init__(self):
        self.puts = []

    def get_file(self, path, token):
        return None, None

    def put_file(self, path, data, token, msg, sha=None):
        self.puts.append(path)
        return "sha-" + path


check("upload switch shipped off", serve._AUTO_UPLOAD_ENABLED is False)
gh = FakeGH()
serve._gh_get_file = gh.get_file
serve._gh_put_file = gh.put_file
serve._log_token = lambda: "token"
serve._encrypt_log = lambda data: b"enc:" + data
serve._note_prompt_waiting = False
serve._upload_logs_once_locked(session_only=True)
check("nothing is sent while uploads are off", gh.puts == [])
check("battle is not marked sent", key not in serve._load_sent_battles())
check("local files remain",
      os.path.exists(os.path.join(tmp, f"battle_{key}_final.log")))
serve._AUTO_UPLOAD_ENABLED = True
serve._upload_logs_once_locked(session_only=True)
check("the same setup sends once re-enabled", len(gh.puts) > 0)
serve._AUTO_UPLOAD_ENABLED = False

print(f"FAILURES: {len(FAILURES)}")
sys.exit(1 if FAILURES else 0)
