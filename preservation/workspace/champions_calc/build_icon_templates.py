#!/usr/bin/env python3
"""タイプアイコンの実サンプル採取 (ローカル専用ツール)。

正解確定済みの登録フレーム (preview_eval/frames/frames.json) から、
各枠のタイプアイコン窓を分類器が実際に使う探索 (参照のみの分類で
最良スコアの窓位置) で特定し、その窓の特徴 (色中央値 + 12×12
グリフ) を真実のタイプのサンプルとして data/type_icons.json の
各タイプの "samples" に登録する。

- ラベルは frames.json の真実 (種族 → species_types.json のタイプ)
  のみを根拠にする。機械の読みは使わない。
- 単タイプ種族のアイコンは右側の位置に表示される (reader の実測
  コメントどおり)。左位置は「アイコンなし」でサンプルにしない。
- 上限: フレームあたり・タイプあたり 2 件まで、タイプあたり
  合計 30 件まで (登録順はフレーム名の辞書順で決定的)。
- 再実行は冪等: samples は毎回フレーム群から再構築する。

使い方: python3 build_icon_templates.py
"""
import json
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "tests"))
import numpy as np
from PIL import Image
import preview_eval as pe

BASE = os.path.dirname(os.path.abspath(__file__))
FRAMES_DIR = os.path.join(BASE, "preview_eval", "frames")
ICONS_PATH = os.path.join(BASE, "data", "type_icons.json")
TYPES_PATH = os.path.join(BASE, "data", "species_types.json")

PER_FRAME_TYPE_CAP = 2
PER_TYPE_CAP = 30


def window_features(buf, x0in, y0in, s):
    """pv_classify_icon と同じ手順で窓の (rgb, glyph grid) を返す。
    アイコンが無い (std <= 30) 窓は None。"""
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
    return rgb, [float(v) for v in grid]


def ref_type_distance(buf, x0in, y0in, s, ref_icons, label):
    """窓の特徴と、ラベルタイプの単一参照との複合距離。
    アイコンの無い窓 (std <= 30) は None。"""
    feat = window_features(buf, x0in, y0in, s)
    if feat is None:
        return None
    rgb, grid = feat
    tp = ref_icons[label]
    corr = pe.pearson(grid, tp["glyph"])
    cd = float(np.sqrt(sum((rgb[i] - tp["rgb"][i]) ** 2 for i in range(3)))) / 441.7
    return ((1 - corr) / 2) * 0.7 + cd * 0.3


def locate_icon_window(buf, x0, y0, s, ref_icons, label):
    """探索窓9点のうち、真実タイプの参照距離が最小の窓を選ぶ。
    分類器の探索 (全タイプ中の最良) で選ぶと、歪んだアイコンでは
    無関係な模様が低スコアになる位置に窓が流れ、その位置の特徴を
    ラベル付きサンプルとして採取してしまう (位置の汚染)。採取時は
    真実が既知なので、真実タイプへの近さで窓を固定する。
    中心窓にアイコンが無ければ None。選んだ窓での真実タイプ距離が
    分類の成立関門 (0.42) を超える場合も、特徴が参照とかけ離れた
    汚染サンプルとみなして None (採取しない)。"""
    if window_features(buf, x0, y0, s) is None:
        return None
    best_pos, best_d = None, None
    for dy in (-s // 5, 0, s // 5):
        for dx in (-s // 6, 0, s // 6):
            d = ref_type_distance(buf, x0 + dx, y0 + dy, s, ref_icons, label)
            if d is not None and (best_d is None or d < best_d):
                best_pos, best_d = (x0 + dx, y0 + dy), d
    if best_pos is None or best_d > 0.42:
        return None
    return best_pos


# アイコンサンプルの採取から除外するフレーム (実測に基づく除外。
# build_frame_templates.py の EXCLUDED_TEMPLATES と同じ考え方)。
# - vs_benn_windowed_20261121.jpg: ウィンドウ表示の preview_test 撮影で、
#   他の全画面撮影と幾何が異なる。このフレーム由来のサンプルが
#   他タイプの窓に異常に低いスコアで勝つ「万能吸着」になることを実測:
#   Ground サンプルが他タイプ窓に 0.10 未満で 4 件勝利、Water サンプルが
#   brim の Poison 窓に 0.013 で勝利して同定を反転させた (2026-11-24 測定)。
#   種族テンプレート側は実害の実測が無いため対象外 (アイコンのみ)。
EXCLUDED_ICON_SOURCES = {"vs_benn_windowed_20261121.jpg"}


def main():
    registry = json.load(open(os.path.join(FRAMES_DIR, "frames.json")))
    types_map = {k: v["types"] for k, v in
                 json.load(open(TYPES_PATH)).items()}
    icons = json.load(open(ICONS_PATH))
    ref_icons = {t: {"rgb": v["rgb"], "glyph": v["glyph"]}
                 for t, v in icons.items()}
    samples = {t: [] for t in icons}
    counts = {}
    for fname in sorted(registry):
        if fname == "matching_wait_20261121.png" or fname in EXCLUDED_ICON_SOURCES:
            continue
        truth = registry[fname]
        img = np.array(Image.open(os.path.join(FRAMES_DIR, fname)).convert("RGB"))
        buf = img.astype(float)
        panels = pe.pv_detect_panels(buf)
        if len(panels) != 6:
            print(f"SKIP {fname}: パネルが6つ取れません")
            continue
        per_frame = {}
        for panel, species in zip(panels, truth):
            px, py, pw, ph, cropw = panel
            types = types_map[species]
            icon_s = int(0.403 * ph)
            # (アイコン位置, ラベル): 単タイプは右位置のみ
            slots = [(0, types[0]), (1, types[1])] if len(types) == 2 \
                else [(1, types[0])]
            for slot, label in slots:
                if per_frame.get(label, 0) >= PER_FRAME_TYPE_CAP:
                    continue
                if len(samples[label]) >= PER_TYPE_CAP:
                    continue
                ix = px + int((0.620 if slot == 0 else 0.810) * pw)
                iy = py + int(0.050 * ph)
                pos = locate_icon_window(buf, ix, iy, icon_s, ref_icons, label)
                if pos is None:
                    print(f"SKIP {fname} {species} slot{slot}: 窓が特定できません")
                    continue
                feat = window_features(buf, pos[0], pos[1], icon_s)
                if feat is None:
                    continue
                rgb, glyph = feat
                samples[label].append({
                    "rgb": [round(v, 1) for v in rgb],
                    "glyph": [round(v, 2) for v in glyph],
                    "src": fname,
                })
                per_frame[label] = per_frame.get(label, 0) + 1
                counts[label] = counts.get(label, 0) + 1
    for t, ss in samples.items():
        icons[t]["samples"] = ss
    json.dump(icons, open(ICONS_PATH, "w"), ensure_ascii=False)
    total = sum(len(s) for s in samples.values())
    print(f"完了: アイコンサンプル {total} 件を登録")
    print("タイプ別:", dict(sorted(counts.items())))


if __name__ == "__main__":
    main()
