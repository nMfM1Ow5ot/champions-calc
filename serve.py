#!/usr/bin/env python3
# Champions ダメージ計算UI用の静的サーバ。
# python3 -m http.server と違い、アクセスログを一切出さない
# (UI が state.json を 0.5 秒ごとにポーリングするため、標準サーバだとログが溢れる)。
# 起動時にオンライン版 UI ファイルへ自動同期し、その後も 15 秒ごとに同期する。
# 同期でファイルが変わると ui_version.txt が更新され、開いている UI が自動で再読込する。
import functools
import http.server
import subprocess
import sys
import threading
import time


def run_sync(show_output, force=False):
    cmd = [sys.executable, "sync_ui.py"] + (["--force"] if force else [])
    try:
        if show_output:
            subprocess.run(cmd, timeout=30)
        else:
            subprocess.run(cmd, timeout=30, capture_output=True)
    except Exception:
        pass


def sync_loop():
    while True:
        time.sleep(15)
        run_sync(False)


class QuietHandler(http.server.SimpleHTTPRequestHandler):
    def log_message(self, format, *args):
        pass

    def end_headers(self):
        self.send_header("Cache-Control", "no-store")
        super().end_headers()


if __name__ == "__main__":
    run_sync(True, force=True)
    threading.Thread(target=sync_loop, daemon=True).start()
    handler = functools.partial(QuietHandler, directory=".")
    try:
        server = http.server.ThreadingHTTPServer(("127.0.0.1", 8765), handler)
    except OSError:
        print("ポート 8765 は使用中です。別のターミナルで旧サーバが動いています。")
        print("そのターミナルで Ctrl+C を押して止めてから、もう一度実行してください。")
        print("見つからない場合は次のコマンドで止められます: lsof -ti tcp:8765 | xargs kill")
        raise SystemExit(1)
    with server as httpd:
        httpd.serve_forever()
