#!/usr/bin/env python3
"""PaddleOCR auxiliary-channel sidecar (evidence only).

Launched and supervised by reader.swift. Reads crop requests the reader
appends to <spool>/requests.jsonl, runs PaddleOCR (PP-OCRv6 small,
Japanese) over the crops in <spool>/crops/, and appends one result per
request to <spool>/results.jsonl: {"reqid", "status": "done", "texts":
[{s, x, y, w, h, score}], "elapsed_ms"} or {"reqid", "status":
"dropped", "reason"}. Processed crops are deleted. A heartbeat file
(<spool>/heartbeat.json) is refreshed every ~2 seconds.

The sidecar never writes to the project's logs/ directory and never
takes part in any state decision: the reader assembles the evidence
file from the results. If PaddleOCR is unavailable, it records
"unavailable" in the heartbeat and exits with code 3.

Configuration is fixed by the step-0 design (PADDLE_DESIGN.md):
paddleocr 3.7.0 / paddlepaddle 3.3.1, lang=japan, enable_mkldnn=False,
document orientation / unwarping / textline orientation off.
"""
import argparse, hashlib, json, os, sys, threading, time

# NOTE: thread-count env caps (OMP_NUM_THREADS etc.) were removed on
# 2026-11-23: the Mac crash report showed a SIGSEGV in paddle's native
# ThreadPool worker (EventCount::Park) with the caps in place, while
# the step-0 measurement — same venv, no caps — ran stably. Load is
# controlled by nice -n 10 (reader side) and the supply throttles.

BACKLOG_CAP = 80          # pending requests beyond this drop the oldest
POLL_SEC = 0.25
HEARTBEAT_SEC = 2.0

def write_heartbeat(spool, battle, status, model="PP-OCRv6_small", resolved=-1):
    hb = {"pid": os.getpid(), "battle": battle, "status": status,
          "model": model, "at": time.time()}
    if resolved >= 0:
        hb["resolved"] = resolved
    tmp = os.path.join(spool, "heartbeat.json.tmp")
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(hb, f, ensure_ascii=False)
    os.replace(tmp, os.path.join(spool, "heartbeat.json"))

def sha256_of(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()

# A single predict can stall for minutes inside native code (seen on
# the Mac in battle_20261123_034434: results stopped for ~7 minutes,
# then a SIGSEGV in paddle's thread pool). A daemon watchdog exits
# the process when one request runs too long; the reader relaunches
# the sidecar and the poison guard drops the offending request as
# crash_suspect, so the channel self-heals.
WATCHDOG_SEC = float(os.environ.get("PADDLE_WATCHDOG_SEC", "30"))
_current = {"reqid": None, "since": 0.0}


def _watchdog():
    while True:
        time.sleep(2)
        since = _current["since"]
        if _current["reqid"] is not None and since and time.time() - since > WATCHDOG_SEC:
            print(f"[watchdog] request {_current['reqid']} exceeded "
                  f"{WATCHDOG_SEC:.0f}s; exiting for relaunch", file=sys.stderr, flush=True)
            os._exit(43)


def main():
    threading.Thread(target=_watchdog, daemon=True).start()
    ap = argparse.ArgumentParser()
    ap.add_argument("--spool", required=True)
    ap.add_argument("--battle", required=True)
    args = ap.parse_args()
    spool = args.spool
    crops_dir = os.path.join(spool, "crops")
    os.makedirs(crops_dir, exist_ok=True)
    requests_path = os.path.join(spool, "requests.jsonl")
    results_path = os.path.join(spool, "results.jsonl")
    offset_path = os.path.join(spool, "offset.txt")

    write_heartbeat(spool, args.battle, "loading")
    try:
        from paddleocr import PaddleOCR
        ocr = PaddleOCR(lang="japan", enable_mkldnn=False,
                        use_doc_orientation_classify=False,
                        use_doc_unwarping=False,
                        use_textline_orientation=False,
                        text_detection_model_name="PP-OCRv6_small_det",
                        text_recognition_model_name="PP-OCRv6_small_rec")
    except Exception as e:
        write_heartbeat(spool, args.battle, "unavailable")
        print(f"paddle unavailable: {e}", flush=True)
        return 3
    write_heartbeat(spool, args.battle, "ready")

    # Read offset is kept in memory only, starting from 0 on every
    # launch: requests a previous incarnation read but never resolved
    # (neither done nor dropped, and never marked started) must become
    # pending again after a relaunch. A persisted offset would orphan
    # them (found by the crash desk test, 2026-11-23).
    offset = 0
    if not os.path.exists(requests_path):
        open(requests_path, "a").close()

    resolved = set()
    if os.path.exists(results_path):
        with open(results_path, encoding="utf-8") as f:
            for line in f:
                try:
                    resolved.add(json.loads(line)["reqid"])
                except Exception:
                    pass

    fout = open(results_path, "a", encoding="utf-8")
    last_hb = time.time()

    def emit(rec):
        fout.write(json.dumps(rec, ensure_ascii=False) + "\n")
        fout.flush()
        resolved.add(rec["reqid"])

    # Poison-pill guard: a crop that crashes the process (native
    # segfault cannot be caught) would otherwise be retried after every
    # relaunch, killing the sidecar in a loop. Requests are recorded in
    # started.jsonl BEFORE processing; on startup, any started but
    # unresolved request is dropped as crash_suspect and skipped.
    started_path = os.path.join(spool, "started.jsonl")
    started = set()
    if os.path.exists(started_path):
        with open(started_path, encoding="utf-8") as f:
            for line in f:
                try:
                    started.add(int(line.strip()))
                except Exception:
                    pass
    for rid in sorted(started - resolved):
        emit({"reqid": rid, "status": "dropped", "reason": "crash_suspect"})
        started.discard(rid)
    started_fout = open(started_path, "a", encoding="utf-8")

    def mark_started(reqid):
        started_fout.write(f"{reqid}\n")
        started_fout.flush()
        started.add(reqid)

    while True:
        # Read newly appended requests.
        pending = []
        with open(requests_path, encoding="utf-8") as f:
            f.seek(offset)
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    req = json.loads(line)
                except Exception:
                    continue
                if req.get("reqid") in resolved:
                    continue
                pending.append(req)
            offset = f.tell()
        with open(offset_path, "w") as f:
            f.write(str(offset))  # observability only; never read back

        # Backlog control: beyond the cap, drop the oldest non-priority.
        if len(pending) > BACKLOG_CAP:
            pending.sort(key=lambda r: r.get("reqid", 0))
            excess = len(pending) - BACKLOG_CAP
            keep = []
            for req in pending:
                if excess > 0 and not req.get("priority"):
                    emit({"reqid": req["reqid"], "status": "dropped",
                          "reason": "backlog"})
                    try:
                        os.remove(os.path.join(crops_dir, req["file"]))
                    except OSError:
                        pass
                    excess -= 1
                else:
                    keep.append(req)
            pending = keep

        # Priority requests first, then by reqid (stable order).
        pending.sort(key=lambda r: (0 if r.get("priority") else 1, r.get("reqid", 0)))

        if not pending:
            now = time.time()
            if now - last_hb >= HEARTBEAT_SEC:
                write_heartbeat(spool, args.battle, "ready", resolved=len(resolved))
                last_hb = now
            time.sleep(POLL_SEC)
            continue

        for req in pending:
            # The WHOLE per-request body is guarded: no single-request
            # failure may ever kill the sidecar. (2026-11-23: an
            # unguarded Image.open after predict let a FileNotFoundError
            # — the reader deleted the crop mid-flight — terminate the
            # process in battle_20261123_032804.)
            try:
                mark_started(req["reqid"])
                path = os.path.join(crops_dir, req["file"])
                if not os.path.exists(path):
                    emit({"reqid": req["reqid"], "status": "dropped",
                          "reason": "crop_missing"})
                    continue
                if req.get("sha256") and sha256_of(path) != req["sha256"]:
                    emit({"reqid": req["reqid"], "status": "dropped",
                          "reason": "crop_overwritten"})
                    continue
                from PIL import Image
                with Image.open(path) as im:
                    cw, ch = im.size
                t0 = time.time()
                _current["reqid"] = req["reqid"]; _current["since"] = t0
                try:
                    res = ocr.predict(path)
                finally:
                    _current["reqid"] = None; _current["since"] = 0.0
                elapsed = int((time.time() - t0) * 1000)
                texts = []
                if res:
                    r = res[0]
                    polys = r.get("rec_polys") or r.get("dt_polys") or []
                    for txt, sc, poly in zip(r.get("rec_texts", []), r.get("rec_scores", []), polys):
                        xs = [pt[0] for pt in poly]; ys = [pt[1] for pt in poly]
                        texts.append({"s": txt,
                                      "x": round(min(xs) / cw, 4), "y": round(min(ys) / ch, 4),
                                      "w": round((max(xs) - min(xs)) / cw, 4),
                                      "h": round((max(ys) - min(ys)) / ch, 4),
                                      "score": round(float(sc), 3)})
                emit({"reqid": req["reqid"], "status": "done",
                      "texts": texts, "elapsed_ms": elapsed})
            except FileNotFoundError:
                emit({"reqid": req["reqid"], "status": "dropped",
                      "reason": "crop_missing"})
            except Exception as e:
                emit({"reqid": req["reqid"], "status": "dropped",
                      "reason": f"error:{type(e).__name__}"})
            try:
                os.remove(os.path.join(crops_dir, req["file"]))
            except OSError:
                pass
            now = time.time()
            if now - last_hb >= HEARTBEAT_SEC:
                write_heartbeat(spool, args.battle, "ready", resolved=len(resolved))
                last_hb = now

if __name__ == "__main__":
    sys.exit(main())
