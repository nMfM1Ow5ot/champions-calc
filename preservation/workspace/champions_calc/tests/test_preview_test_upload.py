#!/usr/bin/env python3
"""serve.py の見せ合いテスト成果物 (preview_test_*) の送信テスト。

検証すること:
- 既定 (通常起動) では preview_test_* は送信対象にならず、送られない
  (start_all.sh の起動時に過去のテスト結果が送られないこと)
- セッション有効化 (POST /preview_test_session) の後は送信対象になり、
  備考なしで送られる
- 備考待ちの一覧には現れない (備考ゲートの対象外)
- 関係ない拡張子は送信対象にならない
- 試合ログ・クラッシュ記録など他種別の送信対象は影響を受けない

実行: python3 tests/test_preview_test_upload.py (全て PASS で終了コード 0)
"""
import http.client
import importlib.util
import os
import sys
import threading

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location(
    "serve", os.path.join(HERE, "..", "serve.py"))
serve = importlib.util.module_from_spec(spec)
spec.loader.exec_module(serve)
# 自動送信は出荷状態では無効化されている (2026-11-23)。この
# スイートは保持された送信機構そのものを検証するため、明示的
# に有効化してから走らせる
serve._AUTO_UPLOAD_ENABLED = True

failures = []


def check(name, cond):
    print(("PASS " if cond else "FAIL ") + name)
    if not cond:
        failures.append(name)


class FakeGH:
    def __init__(self):
        self.puts = []

    def get_file(self, path, token):
        return None, None

    def put_file(self, path, data, token, msg, sha=None):
        self.puts.append(path)
        return "sha-" + path


def main():
    import tempfile
    with tempfile.TemporaryDirectory() as tmp:
        gh = FakeGH()
        serve.LOG_DIR = tmp
        serve.LOG_STATE_PATH = os.path.join(tmp, "uploaded.json")
        serve._log_token = lambda: "tok"
        serve._gh_get_file = gh.get_file
        serve._gh_put_file = gh.put_file
        serve._encrypt_log = lambda data: b"enc:" + data
        serve._note_prompt_waiting = False
        serve._preview_test_session = False

        # 既定では送信対象にならない (通常起動の挙動)
        check("default: jpg not target", not serve._is_upload_target(
            "preview_test_20261121_170000.jpg"))
        check("default: json not target", not serve._is_upload_target(
            "preview_test_20261121_170000.json"))
        # 他種別は影響を受けない
        check("battle log still target", serve._is_upload_target(
            "battle_20261121_170000.log"))
        check("crash log still target", serve._is_upload_target(
            serve._CRASH_LOG_NAME))
        check("debug_ui still target", serve._is_upload_target(
            "debug_ui_20261121_170000.json"))

        with open(os.path.join(tmp, "preview_test_20261121_170000.jpg"),
                  "wb") as f:
            f.write(b"jpg")
        with open(os.path.join(tmp, "preview_test_20261121_170000.json"),
                  "wb") as f:
            f.write(b"{}")

        serve.upload_logs_once()
        sent = [p for p in gh.puts if "preview_test_" in p]
        check("default: nothing uploaded", len(sent) == 0)

        # エンドポイントで有効化する
        server = serve.http.server.ThreadingHTTPServer(
            ("127.0.0.1", 0), serve.QuietHandler)
        port = server.server_address[1]
        t = threading.Thread(target=server.serve_forever, daemon=True)
        t.start()
        try:
            conn = http.client.HTTPConnection("127.0.0.1", port,
                                              timeout=10)
            conn.request("POST", "/preview_test_session")
            resp = conn.getresponse()
            resp.read()
            check("POST /preview_test_session is 200", resp.status == 200)
        finally:
            server.shutdown()
        check("session flag on", serve._preview_test_session is True)

        check("enabled: jpg is target", serve._is_upload_target(
            "preview_test_20261121_170000.jpg"))
        check("enabled: json is target", serve._is_upload_target(
            "preview_test_20261121_170000.json"))
        check("other ext not target", not serve._is_upload_target(
            "preview_test_20261121_170000.txt"))

        check("not in note pending",
              serve.list_pending_log_notes() == [])
        gh.puts.clear()
        serve.upload_logs_once()
        sent = [p for p in gh.puts if "preview_test_" in p]
        check("enabled: both files uploaded", len(sent) == 2)

    print("FAILURES:", failures if failures else "none")
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
