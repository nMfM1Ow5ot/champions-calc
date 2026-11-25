#!/usr/bin/env python3
"""serve.py の QuietHTTPServer.handle_error のテスト。

検証すること:
- クライアント切断 (BrokenPipeError / ConnectionResetError /
  ConnectionAbortedError) は静かに処理する (表示もジャーナル記録も
  しない)
- それ以外の例外はクラッシュジャーナルへ記録する

実行: python3 tests/test_broken_pipe.py (全て PASS で終了コード 0)
"""
import importlib.util
import io
import os
import sys
from contextlib import redirect_stderr

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


srv = object.__new__(serve.QuietHTTPServer)
recorded = []
serve._record_crash = lambda where, exc=None: recorded.append((where, exc))

for exc_type in (BrokenPipeError, ConnectionResetError,
                 ConnectionAbortedError):
    buf = io.StringIO()
    try:
        raise exc_type(32, "Broken pipe")
    except exc_type:
        with redirect_stderr(buf):
            srv.handle_error(None, ("127.0.0.1", 0))
    check(f"{exc_type.__name__} は静かに処理する",
          buf.getvalue() == "" and recorded == [])

buf = io.StringIO()
try:
    raise ValueError("boom")
except ValueError:
    with redirect_stderr(buf):
        srv.handle_error(None, ("127.0.0.1", 0))
check("それ以外の例外はジャーナルへ記録する",
      len(recorded) == 1 and recorded[0][0] == "http_handler"
      and isinstance(recorded[0][1], ValueError))

print("---")
if failures:
    print(f"{len(failures)} FAILURES")
    sys.exit(1)
print("ALL PASS")
