#!/usr/bin/env python3
# serve.py patch: POST /battle_flag endpoint + flag_control.json helpers.
import sys

PATH = "/home/hatch/workspace/champions_calc/serve.py"
src = open(PATH, encoding="utf-8").read()
orig = src

def rep(old, new, tag):
    global src
    n = src.count(old)
    if n != 1:
        print(f"ABORT {tag}: anchor count = {n}")
        sys.exit(1)
    src = src.replace(old, new)
    print(f"OK {tag}")

rep('''STATE_JSON_PATH = os.path.join(BASE_DIR, "state.json")''',
    '''STATE_JSON_PATH = os.path.join(BASE_DIR, "state.json")
FLAG_CONTROL_PATH = os.path.join(BASE_DIR, "flag_control.json")''',
    "S1 control path")

rep('''def _save_calc_log(body):''',
    '''def _read_flag_control():
    """手動フラグの制御ファイル (flag_control.json) を読む。

    UI のボタン要求 (POST /battle_flag) を serve.py がここに記録し、
    reader が監視して取り込む。ファイルが無い・壊れている場合は
    出荷状態 (manual、連番 0) として扱う。同期・アップロードの
    対象外 (プロジェクトフォルダのローカルファイル)。
    """
    try:
        with open(FLAG_CONTROL_PATH, encoding="utf-8") as f:
            obj = json.load(f)
    except Exception:
        obj = {}
    if not isinstance(obj, dict):
        obj = {}
    mode = obj.get("mode")
    if mode not in ("manual", "auto"):
        mode = "manual"

    def _seq(v):
        return v if isinstance(v, int) and v >= 0 else 0

    return {"mode": mode, "startSeq": _seq(obj.get("startSeq")),
            "endSeq": _seq(obj.get("endSeq"))}


def _write_flag_control(ctrl):
    tmp = FLAG_CONTROL_PATH + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(ctrl, f)
    os.replace(tmp, FLAG_CONTROL_PATH)


def _reported_flag_phase():
    """reader が state.json に報告する権威ある phase。読めなければ None。"""
    try:
        with open(STATE_JSON_PATH, encoding="utf-8") as f:
            st = json.load(f)
        ph = st.get("battlePhase")
        return ph if ph in ("idle", "inBattle") else None
    except Exception:
        return None


def _flag_response(projected_phase=None):
    ctrl = _read_flag_control()
    phase = projected_phase or _reported_flag_phase() or "idle"
    return {"ok": True, "phase": phase, "mode": ctrl["mode"],
            "startSeq": ctrl["startSeq"], "endSeq": ctrl["endSeq"]}


def _apply_battle_flag(body):
    """POST /battle_flag の本体。 (status, payload_obj) を返す。

    応答の phase は要求を反映した見込み値 (start -> inBattle、
    end -> idle)。権威ある状態は reader が state.json の
    battlePhase に報告する方で、UI はそちらへ追従する。
    """
    try:
        obj = json.loads(body.decode("utf-8"))
    except Exception:
        return 400, {"ok": False, "error": "invalid json"}
    if not isinstance(obj, dict):
        return 400, {"ok": False, "error": "invalid body"}
    action = obj.get("action")
    ctrl = _read_flag_control()
    if action == "start":
        ctrl["startSeq"] += 1
        _write_flag_control(ctrl)
        return 200, _flag_response("inBattle")
    if action == "end":
        ctrl["endSeq"] += 1
        _write_flag_control(ctrl)
        return 200, _flag_response("idle")
    if action == "mode":
        mode = obj.get("mode")
        if mode not in ("manual", "auto"):
            return 400, {"ok": False, "error": "invalid mode"}
        ctrl["mode"] = mode
        _write_flag_control(ctrl)
        return 200, _flag_response()
    return 400, {"ok": False, "error": "unknown action"}


def _save_calc_log(body):''',
    "S2 flag helpers")

rep('''        if path == "/presets":''',
    '''        if path == "/battle_flag":
            # 手動フラグのボタン要求 (ダメ計 UI 上部の試合開始・
            # 終了ボタン)。制御ファイル flag_control.json に連番
            # つきで記録し、reader が取り込む。備考ゲートの対象外。
            # 結果は JSON で返す (UI は 2xx 以外を失敗として扱う)
            try:
                length = int(self.headers.get("Content-Length") or 0)
            except ValueError:
                length = 0
            if length <= 0:
                status, payload_obj = 400, {"ok": False, "error": "empty body"}
            elif length > 64 * 1024:
                status, payload_obj = 413, {"ok": False, "error": "too large"}
            else:
                body = self.rfile.read(length)
                try:
                    status, payload_obj = _apply_battle_flag(body)
                except Exception as e:
                    _record_crash("battle_flag", e)
                    status, payload_obj = 500, {"ok": False, "error": str(e)}
            payload = json.dumps(payload_obj).encode()
            self.send_response(status)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(payload)))
            self.end_headers()
            self.wfile.write(payload)
            return
        if path == "/presets":''',
    "S3 endpoint")

if src == orig:
    print("ABORT: no changes")
    sys.exit(1)
open(PATH, "w", encoding="utf-8").write(src)
print("WROTE", PATH)
