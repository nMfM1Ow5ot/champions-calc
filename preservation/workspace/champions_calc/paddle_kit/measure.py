#!/usr/bin/env python3
"""Step-0 measurement: run PP-OCRv6 small and medium over the sample crops
(real battle-frame crops: plates and message strips) and record per-item
elapsed time and the raw recognized texts, alongside the Vision readings
for the same regions (samples/manifest.json).

Per the image-recognition consultation: plates are measured at 1x and 2x
upscale (small text), strips at 1x only; timings are summarized separately
for plates and strips. Output: measure_result.jsonl in this folder —
send that file back to the backend chat.

Run with the sidecar venv:
  ~/champions_paddle/.venv/bin/python measure.py
"""
import json, os, statistics, time
from PIL import Image

BASE = os.path.dirname(os.path.abspath(__file__))
SAMPLES = os.path.join(BASE, "samples")
OUT = os.path.join(BASE, "measure_result.jsonl")
TMP = os.path.join(BASE, "_measure_tmp.png")

def build(size):
    from paddleocr import PaddleOCR
    return PaddleOCR(lang="japan", enable_mkldnn=False,
                     use_doc_orientation_classify=False,
                     use_doc_unwarping=False,
                     use_textline_orientation=False,
                     text_detection_model_name=f"PP-OCRv6_{size}_det",
                     text_recognition_model_name=f"PP-OCRv6_{size}_rec")

def run_one(ocr, path):
    t0 = time.time()
    res = ocr.predict(path)
    elapsed = int((time.time() - t0) * 1000)
    texts = []
    if res:
        r = res[0]
        for txt, sc in zip(r.get("rec_texts", []), r.get("rec_scores", [])):
            texts.append({"s": txt, "score": round(float(sc), 3)})
    return elapsed, texts

def main():
    manifest = json.load(open(os.path.join(SAMPLES, "manifest.json"), encoding="utf-8"))
    fout = open(OUT, "w", encoding="utf-8")
    times = {}
    for size in ("small", "medium"):
        ocr = build(size)
        for m in manifest:
            path = os.path.join(SAMPLES, m["crop"])
            scales = (1, 2) if m["pass"].startswith("plate:") else (1,)
            for scale in scales:
                use = path
                if scale != 1:
                    img = Image.open(path)
                    img = img.resize((img.size[0] * scale, img.size[1] * scale), Image.LANCZOS)
                    img.save(TMP)
                    use = TMP
                try:
                    elapsed, texts = run_one(ocr, use)
                except Exception as e:
                    fout.write(json.dumps({"crop": m["crop"], "pass": m["pass"], "model": size,
                                           "scale": scale, "error": str(e)}, ensure_ascii=False) + "\n")
                    continue
                cat = "plate" if m["pass"].startswith("plate:") else "strip"
                times.setdefault((size, cat, scale), []).append(elapsed)
                fout.write(json.dumps({"crop": m["crop"], "pass": m["pass"], "model": size,
                                       "scale": scale, "elapsed_ms": elapsed, "texts": texts,
                                       "vision": m["vision"]}, ensure_ascii=False) + "\n")
                fout.flush()
        del ocr
    fout.close()
    if os.path.exists(TMP):
        os.remove(TMP)
    summary = {}
    for (size, cat, scale), ts in sorted(times.items()):
        summary[f"{size}/{cat}/x{scale}"] = {"n": len(ts), "median_ms": int(statistics.median(ts)),
                                             "mean_ms": int(statistics.mean(ts)), "max_ms": max(ts)}
    print(json.dumps({"summary": summary}, ensure_ascii=False, indent=1), flush=True)
    print(f"MEASURE_DONE -> {OUT}", flush=True)

if __name__ == "__main__":
    main()
