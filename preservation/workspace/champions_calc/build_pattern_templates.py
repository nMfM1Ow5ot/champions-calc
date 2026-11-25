#!/usr/bin/env python3
"""ビビヨンの模様テンプレートを data/preview_features.json に登録する。

ビビヨンは模様 (全 18 種) で翼の色が全く異なり、参照特徴は Meadow 模様
1 種しか表せない。別模様の個体は色相ヒストグラムが参照と無相関になり、
照合が成立しない (実例: 2026-11-23 battle_20261123_230349 枠4、
High Plains 模様が Farfetch'd に敗れた)。
そこで Pokémon Showdown の dex スプライトから各模様の特徴量を
参照と同じ手順 (build_preview_features.features_from_sprite) で計算し、
Vivillon の templates に tag="pattern" として登録する。
Meadow は参照そのものなので除く。Fancy / Pokeball は別種族エントリで
模様が固定のため対象外。

冪等: tag="pattern" の既存エントリは置き換える。
スプライトのキャッシュは preview_eval/sprites/patterns/ (同期対象外)。
"""
import json
import os
import urllib.request

BASE = os.path.dirname(os.path.abspath(__file__))
CACHE = os.path.join(BASE, "preview_eval", "sprites", "patterns")
DATA = os.path.join(BASE, "data", "preview_features.json")

PATTERNS = [
    "archipelago", "continental", "elegant", "garden", "highplains",
    "icysnow", "jungle", "marine", "modern", "monsoon", "ocean",
    "polar", "river", "sandstorm", "savanna", "sun", "tundra",
]


def sprite(slug):
    path = os.path.join(CACHE, f"vivillon-{slug}.png")
    if not os.path.exists(path):
        os.makedirs(CACHE, exist_ok=True)
        url = f"https://play.pokemonshowdown.com/sprites/dex/vivillon-{slug}.png"
        req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
        with urllib.request.urlopen(req) as r, open(path, "wb") as f:
            f.write(r.read())
    return path


def main():
    from build_preview_features import features_from_sprite

    with open(DATA, encoding="utf-8") as f:
        data = json.load(f)
    entry = data["Vivillon"]
    kept = [t for t in entry.get("templates", []) if t.get("tag") != "pattern"]
    added = []
    for slug in PATTERNS:
        feat = features_from_sprite(sprite(slug))
        if feat is None:
            print(f"  {slug}: 特徴なし (スキップ)")
            continue
        added.append({
            "hash": feat["hash"],
            "hue": feat["hue"],
            "aspect": feat["aspect"],
            "density": feat["density"],
            "src": f"pattern:{slug}",
            "gender": "",
            "tag": "pattern",
        })
    entry["templates"] = kept + added
    with open(DATA, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False)
    total = sum(len(v.get("templates", [])) for v in data.values())
    print(f"完了: 模様テンプレート {len(added)} 件を登録、テンプレート総数 {total} 件")


if __name__ == "__main__":
    main()
