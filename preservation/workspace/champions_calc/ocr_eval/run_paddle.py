#!/usr/bin/env python3
"""Run PaddleOCR (Japanese) on the same regions Vision read, for each paired
debug image. Appends results to paddle.jsonl (resumable): one record per
(image, pass): {image, pass, texts:[{s,x,y,w,h,score}], elapsed_ms}.
Coordinates are region-relative fractions, same convention as obs boxes.
"""
import json, os, sys, time
import numpy as np
from PIL import Image

BASE = os.path.dirname(os.path.abspath(__file__))
LOGS = os.path.expanduser("~/workspace/champions_calc/logs_received")
PAIRS = os.path.join(BASE, "pairs.jsonl")
OUT = os.path.join(BASE, "paddle.jsonl")
TMP = "/tmp/ocr_eval_crops"
os.makedirs(TMP, exist_ok=True)

def load_done():
    done = set()
    if os.path.exists(OUT):
        with open(OUT) as f:
            for line in f:
                try:
                    r = json.loads(line)
                    done.add((r["image"], r["pass"]))
                except Exception:
                    pass
    return done

def main():
    from paddleocr import PaddleOCR
    # enable_mkldnn=False: paddle 3.3 oneDNN path raises NotImplementedError
    # (ConvertPirAttribute2RuntimeAttribute). Doc orientation/unwarping and
    # textline orientation are off: game frames are upright, horizontal text.
    ocr = PaddleOCR(lang="japan", enable_mkldnn=False,
                    use_doc_orientation_classify=False, use_doc_unwarping=False,
                    use_textline_orientation=False,
                    text_detection_model_name="PP-OCRv6_small_det",
                    text_recognition_model_name="PP-OCRv6_small_rec")
    pairs = [json.loads(l) for l in open(PAIRS)]
    done = load_done()
    todo = [p for p in pairs if (p["image"], p["pass"]) not in done]
    print(f"total={len(pairs)} done={len(done)} todo={len(todo)}", flush=True)
    fout = open(OUT, "a")
    imgs = {}
    for i, p in enumerate(todo):
        img = imgs.get(p["image"])
        if img is None:
            img = Image.open(os.path.join(LOGS, p["image"])).convert("RGB")
            imgs[p["image"]] = img
        W, H = img.size
        x0, y0, x1, y1 = p["region"]
        crop = img.crop((int(x0 * W), int(y0 * H), int(x1 * W), int(y1 * H)))
        if p["region"] == [0, 0, 1, 1]:
            # Full frames are downscaled to 0.75x to keep this throttled VM's
            # runtime sane; coordinates are fractions, so metrics are unaffected
            # in form (disclosed in the report as a Paddle-side handicap).
            crop = crop.resize((crop.size[0] * 3 // 4, crop.size[1] * 3 // 4), Image.LANCZOS)
        cw, ch = crop.size
        tmp = os.path.join(TMP, "crop.png")
        crop.save(tmp)
        t0 = time.time()
        try:
            res = ocr.predict(tmp)
        except Exception as e:
            print(f"ERR {p['image']} {p['pass']}: {e}", flush=True)
            continue
        elapsed = int((time.time() - t0) * 1000)
        texts = []
        if res:
            r = res[0]
            polys = r.get("rec_polys") or r.get("dt_polys") or []
            for txt, sc, poly in zip(r.get("rec_texts", []), r.get("rec_scores", []), polys):
                xs = [pt[0] for pt in poly]; ys = [pt[1] for pt in poly]
                texts.append({
                    "s": txt,
                    "x": round(min(xs) / cw, 4), "y": round(min(ys) / ch, 4),
                    "w": round((max(xs) - min(xs)) / cw, 4), "h": round((max(ys) - min(ys)) / ch, 4),
                    "score": round(float(sc), 3),
                })
        fout.write(json.dumps({"image": p["image"], "pass": p["pass"],
                               "texts": texts, "elapsed_ms": elapsed}, ensure_ascii=False) + "\n")
        fout.flush()
        if (i + 1) % 20 == 0:
            print(f"{i+1}/{len(todo)}", flush=True)
    fout.close()
    print("DONE", flush=True)

if __name__ == "__main__":
    main()
