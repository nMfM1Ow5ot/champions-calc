#!/usr/bin/env python3
"""Build both PaddleOCR configurations once (downloads the models into the
local cache) and run one prediction each, proving the environment starts
and reads offline afterwards. Mirrors the configuration verified in
ocr_eval/run_paddle.py: lang=japan, enable_mkldnn=False, document
orientation / unwarping / textline orientation all off."""
import os, sys, time

BASE = os.path.dirname(os.path.abspath(__file__))
SAMPLE = os.path.join(BASE, "samples", "crop_00_plate_mineA.png")

def build(size):
    from paddleocr import PaddleOCR
    return PaddleOCR(lang="japan", enable_mkldnn=False,
                     use_doc_orientation_classify=False,
                     use_doc_unwarping=False,
                     use_textline_orientation=False,
                     text_detection_model_name=f"PP-OCRv6_{size}_det",
                     text_recognition_model_name=f"PP-OCRv6_{size}_rec")

def main():
    sample = SAMPLE if os.path.exists(SAMPLE) else None
    for size in ("small", "medium"):
        t0 = time.time()
        ocr = build(size)
        print(f"[{size}] init ok in {time.time() - t0:.1f}s", flush=True)
        if sample:
            res = ocr.predict(sample)
            texts = res[0].get("rec_texts", []) if res else []
            print(f"[{size}] sample read: {texts}", flush=True)
        del ocr
    print("FETCH_MODELS_DONE", flush=True)

if __name__ == "__main__":
    main()
