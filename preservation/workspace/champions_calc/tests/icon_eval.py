#!/usr/bin/env python3
"""タイプアイコン分類の単体評価 (ローカル専用)。

登録済みフレーム全枠のアイコン窓を真実ラベル付きで切り出し、
現行方式 (タイプごとの単一参照のみ) とテンプレート方式
(単一参照 + 実サンプル群。同一フレーム由来のサンプルは除外) で
アイコン単位の正解率を比較する。窓の探索 (中心 + 近傍8点) と
複合距離 (グリフ相関×0.7 + 色距離×0.3、成立関門 0.42) は
pv_classify_icon / pv_classify_icon_search と同一の手順を、
特徴を先に計算する形で再現する。再現が実関数と一致することは
実行時に全窓で照合する。

使い方: python3 tests/icon_eval.py
"""
import json
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np
from PIL import Image
import preview_eval as pe

BASE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FRAMES_DIR = os.path.join(BASE, "preview_eval", "frames")

# 既知の失敗窓 (フレーム, 枠番号1始まり, アイコン位置0/1, 正解)
KNOWN_FAILURES = [
    ("vs_joni_20261124.jpg", 1, 1, "Normal"),   # ノーマル→いわ
    ("vs_joni_20261124.jpg", 4, 1, "Fire"),     # ほのお→いわ (単タイプ右位置)
    ("vs_joni_20261124.jpg", 5, 1, "Normal"),   # ノーマル→いわ
    ("vs_kusa_20261123.jpg", 3, 1, "Dark"),     # あく→ゴースト
]


def window_features(buf, x0in, y0in, s):
    """pv_classify_icon と同じ手順で窓の (rgb, glyph grid) を返す。
    std <= 30 の窓は None (= アイコンなし)。"""
    H, W = buf.shape[:2]
    x0 = max(0, min(x0in, W - s))
    y0 = max(0, min(y0in, H - s))
    cell = buf[y0:y0 + s, x0:x0 + s]
    gray = 0.299 * cell[:, :, 0] + 0.587 * cell[:, :, 1] + 0.114 * cell[:, :, 2]
    if float(gray.std()) <= 30:
        return None
    flat = cell.reshape(-1, 3)
    kept = flat[flat.mean(axis=1) < 210]
    src = kept if len(kept) else flat
    rgb = [float(np.median(src[:, i])) for i in range(3)]
    grid = pe.resize_area(gray, 12, 12).reshape(-1)
    return rgb, grid


def score_position(feat, candidates):
    """1窓の特徴に対し (最良タイプ, 距離) を返す。candidates は
    (タイプ, rgb, glyph, src) の列。Electric の色ショートカットは
    pv_classify_icon と同一 (正規参照色との距離で固定式)。"""
    rgb, grid = feat
    if (rgb[0] >= 195 and rgb[1] >= 145 and rgb[2] <= 135
            and rgb[0] - rgb[2] >= 110 and rgb[1] - rgb[2] >= 50
            and rgb[0] >= rgb[1] - 10):
        cd = math.sqrt((rgb[0] - 247) ** 2 + (rgb[1] - 197) ** 2
                       + (rgb[2] - 28) ** 2) / 441.7
        return "Electric", 0.05 + cd * 0.3
    best_t, best_d = None, 999.0
    for t, crgb, glyph in candidates:
        corr = pe.pearson(grid, glyph)
        cd = math.sqrt(sum((rgb[i] - crgb[i]) ** 2 for i in range(3))) / 441.7
        d = ((1 - corr) / 2) * 0.7 + cd * 0.3
        if d < best_d:
            best_t, best_d = t, d
    return best_t, best_d


def classify_window(pos_feats, candidates):
    """探索込みの分類。pos_feats は [中心, 近傍8点] の特徴 (None 可)。
    中心が「なし」なら即 absent。pv_classify_icon_search と等価。"""
    if pos_feats[0] is None:
        return None
    best_t, best_d = None, 999.0
    for feat in pos_feats:
        if feat is None:
            continue
        t, d = score_position(feat, candidates)
        if d < best_d:
            best_t, best_d = t, d
    if best_d >= 0.42:
        return None
    return best_t


def main():
    registry = json.load(open(os.path.join(FRAMES_DIR, "frames.json")))
    types_map = {k: v["types"] for k, v in
                 json.load(open(os.path.join(BASE, "data", "species_types.json"))).items()}
    icons = json.load(open(os.path.join(BASE, "data", "type_icons.json")))
    ref_cands = [(t, v["rgb"], v["glyph"]) for t, v in icons.items()]
    sample_cands = {}
    for t, v in icons.items():
        for s in v.get("samples", []):
            sample_cands.setdefault(s["src"], []).append((t, s["rgb"], s["glyph"]))

    windows = []  # (frame, slot, pos, truth or None, pos_feats, buf, ix, iy, s)
    for fname in sorted(registry):
        if fname == "matching_wait_20261121.png":
            continue
        truth = registry[fname]
        img = np.array(Image.open(os.path.join(FRAMES_DIR, fname)).convert("RGB"))
        buf = img.astype(float)
        panels = pe.pv_detect_panels(buf)
        if len(panels) != 6:
            print(f"SKIP {fname}: パネルが6つ取れません")
            continue
        for si, (panel, species) in enumerate(zip(panels, truth)):
            px, py, pw, ph, cropw = panel
            types = types_map[species]
            icon_s = int(0.403 * ph)
            labels = [(0, types[0]), (1, types[1])] if len(types) == 2 \
                else [(0, None), (1, types[0])]
            for slot, label in labels:
                ix = px + int((0.620 if slot == 0 else 0.810) * pw)
                iy = py + int(0.050 * ph)
                feats = [window_features(buf, ix, iy, icon_s)]
                for dy in (-icon_s // 5, 0, icon_s // 5):
                    for dx in (-icon_s // 6, 0, icon_s // 6):
                        if dx == 0 and dy == 0:
                            continue
                        feats.append(window_features(buf, ix + dx, iy + dy, icon_s))
                windows.append((fname, si + 1, slot, label, feats, buf, ix, iy, icon_s))

    # 再現照合: 参照のみの再現分類が実関数と全窓で一致すること
    mism = 0
    for fname, si, slot, label, feats, buf, ix, iy, icon_s in windows:
        real = pe.pv_classify_icon_search(buf, ix, iy, icon_s,
                                           {t: {"rgb": r, "glyph": g}
                                            for t, r, g in ref_cands})[0]
        mine = classify_window(feats, ref_cands)
        if real != mine:
            mism += 1
            if mism <= 5:
                print(f"再現不一致 {fname} slot{si} pos{slot}: 実関数={real} 再現={mine}")
    print(f"再現照合: {len(windows)} 窓中 不一致 {mism} 件")

    def evaluate(use_samples):
        ok = total = 0
        per_type = {}
        confusions = {}
        results = {}
        for fname, si, slot, label, feats, buf, ix, iy, icon_s in windows:
            if label is None:
                continue
            cands = list(ref_cands)
            if use_samples:
                for src, ss in sample_cands.items():
                    if src != fname:
                        cands.extend(ss)
            pred = classify_window(feats, cands)
            total += 1
            per_type.setdefault(label, [0, 0])
            per_type[label][1] += 1
            if pred == label:
                ok += 1
                per_type[label][0] += 1
            else:
                confusions[(label, pred)] = confusions.get((label, pred), 0) + 1
            results[(fname, si, slot)] = pred
        return ok, total, per_type, confusions, results

    ok_a, tot, pt_a, cf_a, res_a = evaluate(False)
    ok_b, _, pt_b, cf_b, res_b = evaluate(True)
    print(f"\nアイコン単体正解率 (アイコンのある窓 {tot} 件)")
    print(f"  現行方式 (単一参照):     {ok_a}/{tot} = {ok_a / tot:.3f}")
    print(f"  テンプレート方式:         {ok_b}/{tot} = {ok_b / tot:.3f}")
    print("\n既知の失敗窓:")
    for fname, si, slot, label in KNOWN_FAILURES:
        print(f"  {fname} slot{si} pos{slot} 正解 {label}: "
              f"現行={res_a.get((fname, si, slot))} → テンプレート={res_b.get((fname, si, slot))}")
    print("\nタイプ別 (現行 → テンプレート):")
    for t in sorted(pt_a):
        a, n = pt_a[t]
        b = pt_b[t][0]
        flag = " ← 悪化" if b < a else ""
        print(f"  {t}: {a}/{n} → {b}/{n}{flag}")
    print("\n混同 (正解→予測) 現行の上位:")
    for (lab, pred), c in sorted(cf_a.items(), key=lambda kv: -kv[1])[:8]:
        print(f"  {lab} → {pred}: {c} 件")
    print("混同 (正解→予測) テンプレート方式の上位:")
    for (lab, pred), c in sorted(cf_b.items(), key=lambda kv: -kv[1])[:8]:
        print(f"  {lab} → {pred}: {c} 件")


if __name__ == "__main__":
    main()
