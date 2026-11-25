#!/usr/bin/env python3
"""実フレームテンプレートの抽出・登録 (ローカル専用ツール)。

preview_eval/frames/frames.json に登録された「正解が確定済み」の
見せ合いフレームから、各枠のモデル特徴を reader と同じ手順
(パネル検出 → cropW での切り出し → pv_model_features_frame) で抽出し、
data/preview_features.json の各対象種族の "templates" に登録する。

- 再実行は冪等: 同じ src (フレームファイル名) のテンプレートは置き換える。
- ラベルは frames.json の正解のみを根拠にする (未確定の画像は登録しない)。
- バリエーションのタグは TAG_OVERRIDES で明示する (例: 色違い)。

使い方: python3 build_frame_templates.py
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
FEATURES_PATH = os.path.join(BASE, "data", "preview_features.json")

# (フレーム名, 種族) -> タグ。視覚確認できたバリエーションのみ。
TAG_OVERRIDES = {
    ("vs_jose_20261121.jpg", "Salamence"): "shiny",  # 緑色の体+橙色の翼を画像で確認
    ("vs_trainer_20261124.jpg", "Charizard"): "shiny",  # 黒い体+赤い翼+クリーム色の腹を画像で確認 (2026-11-24)
    ("vs_snowball_20261124.jpg", "Dragonite"): "shiny",  # 緑色の体+紫色の翼膜+クリーム色の腹を画像で確認 (2026-11-24)
    ("vs_grayson_20261124.jpg", "Meowstic"): "shiny",  # 淡黄色の体+白い耳帯・前髪・スカーフ+青緑の目 (色違いオスの配色) を画像で確認 (2026-11-24)
}

# 特徴が画面全体のアーティファクト (光の筋) に支配され、種族の特徴を
# 表していないことが実測で確認できたテンプレートは、登録から除外する
# (フレーム自体と真実の記録は frames.json に残る)。除外はここに理由と
# 実測値を残し、ログ分析チャットへ報告する。
# - Kingambit <- vs_eggmiral_20261123.jpg (2026-11-24): 当該テンプレートが
#   他種パネルに異常に低スコアで一致する (vs_benn_test1 の Gholdengo
#   パネルに 0.073 — 本人の最良 0.417 を 0.34 下回る; vs_kusa の
#   Excadrill パネルに -0.181)。ミラー全件で benn_test1 が 6/6 → 5/6 に
#   悪化した唯一の原因。
EXCLUDED_TEMPLATES = {
    ("vs_eggmiral_20261123.jpg", "Kingambit"),
}


def main():
    registry = json.load(open(os.path.join(FRAMES_DIR, "frames.json")))
    features = json.load(open(FEATURES_PATH))
    processed = set()
    added = 0
    for fname, truth in sorted(registry.items()):
        img = np.array(Image.open(os.path.join(FRAMES_DIR, fname)).convert("RGB"))
        buf = img.astype(float)
        panels = pe.pv_detect_panels(buf)
        if len(panels) != 6:
            print(f"SKIP {fname}: パネルが6つ取れません")
            continue
        processed.add(fname)
        for panel, species in zip(panels, truth):
            if (fname, species) in EXCLUDED_TEMPLATES:
                cur = features.setdefault(species, {})
                cur["templates"] = [t for t in cur.get("templates", [])
                                    if t.get("src") != fname]
                print(f"EXCLUDED {fname} {species}: 特徴テンプレートを登録しません")
                continue
            px, py, pw, ph, cropw = panel
            f = pe.pv_model_features_frame(buf, (px, py, cropw, ph))
            if f is None:
                print(f"SKIP {fname} {species}: 特徴が取れません")
                continue
            gender = pe.pv_read_gender(buf, (px, py, pw, ph))[0]
            entry = {
                "hash": f["hash"],
                "hue": [round(float(v), 4) for v in f["hue"]],
                "aspect": round(float(f["aspect"]), 4),
                "density": round(float(f["density"]), 4),
                "src": fname,
                "gender": gender or "",
                "tag": TAG_OVERRIDES.get((fname, species), "frame"),
            }
            cur = features.setdefault(species, {})
            templates = [t for t in cur.get("templates", []) if t.get("src") != fname]
            templates.append(entry)
            cur["templates"] = templates
            added += 1
            print(f"  {species}: <- {fname} (gender={entry['gender'] or '-'}, tag={entry['tag']})")
    # 処理したフレーム由来の古いテンプレートで、今回抽出できなかった
    # ものが残らないよう、対象フレームの src を持つ既存分は差し替える
    # (上の置換で同種族分は処理済み。他種族に誤って付いた分は無い前提)
    json.dump(features, open(FEATURES_PATH, "w"), ensure_ascii=False)
    total = sum(len(v.get("templates", [])) for v in features.values())
    print(f"完了: 今回 {added} 件を登録、テンプレート総数 {total} 件")


if __name__ == "__main__":
    main()
