"""マッチング待機画面の視覚検出 (reader.swift matchingDialogPresent の
ミラー) の回帰確認。登録フレームで発火し、見せ合いフレームでは
発火しないことを見る。OCR はこの環境では実行できないため、
紫ダイアログ判定のみを対象にする。"""
import os
import numpy as np
from PIL import Image

FRAMES = os.path.join(os.path.dirname(os.path.abspath(__file__)), "frames")


def dialog_present(path):
    img = np.array(Image.open(path).convert("RGB")).astype(int)
    H, W = img.shape[:2]
    hits = total = 0
    for fy in (0.38, 0.44, 0.50, 0.58):
        for fx in (0.20, 0.30, 0.40, 0.60, 0.70, 0.80):
            r, g, b = img[int(fy * H), int(fx * W)]
            total += 1
            if b > r > g and b >= 110 and r >= 70:
                hits += 1
    return hits * 4 >= total * 3, hits, total


def main():
    ok = True
    hit, h, t = dialog_present(os.path.join(FRAMES, "matching_wait_20261121.png"))
    print(f"matching_wait_20261121.png: 発火={hit} ({h}/{t})")
    ok &= hit
    for name in sorted(os.listdir(FRAMES)):
        if not name.startswith("vs_"):
            continue
        hit, h, t = dialog_present(os.path.join(FRAMES, name))
        print(f"{name}: 発火={hit} ({h}/{t})  <- 発火しないこと")
        ok &= not hit
    print("OK" if ok else "NG")
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
