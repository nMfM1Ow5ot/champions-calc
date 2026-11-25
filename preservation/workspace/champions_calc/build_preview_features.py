#!/usr/bin/env python3
"""選出同定の参照データ (data/species_types.json / data/preview_features.json) を
チャンピオンズ実装種族の全種分そろえるための生成スクリプト。

使い方: python3 build_preview_features.py [--check]

- 対象は champions_dex.json の species (368 種) のうち、species_types.json /
  preview_features.json に未収録の種族 (従来は全メガフォルム 82 種が欠落していた)
- タイプと基本種族は @smogon/calc の gen9 データから取る (計算側の正本と一致させる)
- 参照特徴は Pokémon HOME スプライト (PokéAPI 経由) から、既存 286 種の生成方式と
  同一のアルゴリズムで計算する:
    alpha>0 のマスク → 外接矩形で切り出し → 背景グレー 128 で 17x16 に
    バイリニア縮小して dHash (右隣より大きければ 1)、色相 24 ビン ヒストグラム
    (無彩色は hue=0 でビン 0)、縦横比 = 矩形 w/h、密度 = マスク面積 / 矩形面積
  既存エントリに対する再現検証: ハッシュのハミング距離 1〜4 ビット、
  色相ヒストグラム相関 0.999 以上、縦横比は完全一致 (2026-11-21 検証済み)
- スプライトは preview_eval/sprites/ にキャッシュする (同期対象外。
  tests/preview_eval.py の精度測定でも再利用する)
- 既存エントリは変更しない。書き出し形式 (キー順 = dex 順、整形) は既存ファイルと同一
"""
import json
import math
import os
import subprocess
import sys
import urllib.request

BASE = os.path.dirname(os.path.abspath(__file__))
DATA = os.path.join(BASE, "data")
CACHE = os.path.join(BASE, "preview_eval", "sprites")
UA = {"User-Agent": "champions-calc-preview-feature-builder"}

# PokéAPI のポケモン名が champions_dex の種族名と異なるもの
SLUG_OVERRIDES = {
    "Meowstic-F-Mega": "meowstic-female-mega",
    "Meowstic-M-Mega": "meowstic-male-mega",
}


def load_json(path):
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def smogon_species():
    """@smogon/calc gen9 の全種族 {name: {types, base}} を node 経由で取得する。"""
    code = (
        "import { Generations } from '@smogon/calc';"
        "const gen = Generations.get(9);"
        "const out = {};"
        "for (const sp of gen.species) out[sp.name] = {types: sp.types, base: sp.baseSpecies || sp.name};"
        "console.log(JSON.stringify(out));"
    )
    p = subprocess.run(["node", "--input-type", "module", "-e", code],
                       cwd=BASE, capture_output=True, text=True, timeout=120)
    if p.returncode != 0:
        raise RuntimeError(f"node での種族データ取得に失敗: {p.stderr[:400]}")
    return json.loads(p.stdout)


def fetch_json(url):
    # urllib では pokeapi.co の応答が途中で切れることがあるため curl を使う
    # (fetch_champions_dex.mjs 等の既存スクリプトと同じ方式)
    p = subprocess.run(["curl", "-sL", "--max-time", "60", "-A", UA["User-Agent"], url],
                       capture_output=True, timeout=90)
    if p.returncode != 0:
        raise RuntimeError(f"取得に失敗しました: {url}")
    return json.loads(p.stdout.decode("utf-8"))


def fetch_bytes(url, path):
    p = subprocess.run(["curl", "-sL", "--max-time", "60", "-A", UA["User-Agent"], "-o", path, url],
                       capture_output=True, timeout=90)
    if p.returncode != 0 or not os.path.exists(path) or os.path.getsize(path) == 0:
        raise RuntimeError(f"取得に失敗しました: {url}")
    return path


def sprite_path(name):
    slug = SLUG_OVERRIDES.get(name, name.lower())
    path = os.path.join(CACHE, slug + ".png")
    if os.path.exists(path):
        return path
    info = fetch_json(f"https://pokeapi.co/api/v2/pokemon/{slug}")
    url = info["sprites"]["other"]["home"]["front_default"]
    if not url:
        raise RuntimeError(f"{name}: HOME スプライトがありません")
    os.makedirs(CACHE, exist_ok=True)
    fetch_bytes(url, path)
    return path


# --- 特徴量計算 (tests/preview_eval.py と同一実装) ---

def resize_bilinear(src, dw, dh):
    import numpy as np
    sh, sw = src.shape
    xs = (np.arange(dw) + 0.5) * (sw / dw) - 0.5
    ys = (np.arange(dh) + 0.5) * (sh / dh) - 0.5
    x0 = np.floor(xs).astype(int)
    y0 = np.floor(ys).astype(int)
    wx = xs - x0
    wy = ys - y0
    x0c = np.clip(x0, 0, sw - 1)
    x1c = np.clip(x0 + 1, 0, sw - 1)
    y0c = np.clip(y0, 0, sh - 1)
    y1c = np.clip(y0 + 1, 0, sh - 1)
    top = src[np.ix_(y0c, x0c)] * (1 - wx) + src[np.ix_(y0c, x1c)] * wx
    bot = src[np.ix_(y1c, x0c)] * (1 - wx) + src[np.ix_(y1c, x1c)] * wx
    return top * (1 - wy)[:, None] + bot * wy[:, None]


def features_from_sprite(path):
    import numpy as np
    from PIL import Image
    im = Image.open(path).convert("RGBA")
    a = np.array(im)
    mask = a[:, :, 3] > 0
    if mask.sum() < 20:
        return None
    rgb = a[:, :, :3].astype(float)
    g = 0.299 * rgb[:, :, 0] + 0.587 * rgb[:, :, 1] + 0.114 * rgb[:, :, 2]
    ys, xs = np.where(mask)
    x0, x1, y0, y1 = xs.min(), xs.max(), ys.min(), ys.max()
    sw, sh = x1 - x0 + 1, y1 - y0 + 1
    gray = np.full((sh, sw), 128.0)
    m2 = mask[y0:y1 + 1, x0:x1 + 1]
    gray[m2] = g[y0:y1 + 1, x0:x1 + 1][m2]
    small = resize_bilinear(gray, 17, 16)
    bits = []
    for yy in range(16):
        for xx in range(16):
            bits.append(1 if small[yy, xx + 1] > small[yy, xx] else 0)
    hash_bytes = []
    for i in range(0, 256, 8):
        v = 0
        for bit in bits[i:i + 8]:
            v = (v << 1) | bit
        hash_bytes.append(v)
    hx = "".join(f"{v:02x}" for v in hash_bytes)
    # 色相ヒストグラム (24 ビン、全マスク画素。無彩色は hue=0)
    r = rgb[:, :, 0] / 255.0
    gg = rgb[:, :, 1] / 255.0
    b = rgb[:, :, 2] / 255.0
    mx = np.maximum(np.maximum(r, gg), b)
    mn = np.minimum(np.minimum(r, gg), b)
    d = mx - mn
    dd = np.where(d == 0, 1, d)
    hdeg = np.zeros_like(mx)
    idx = (mx == r) & (d > 0)
    hdeg[idx] = (60 * ((gg - b) / dd) % 360)[idx]
    idx = (mx == gg) & (d > 0)
    hdeg[idx] = (60 * ((b - r) / dd) + 120)[idx]
    idx = (mx == b) & (d > 0)
    hdeg[idx] = (60 * ((r - gg) / dd) + 240)[idx]
    hue = np.zeros(24)
    bins = np.minimum((hdeg[mask] / 15).astype(int), 23)
    for bb in bins:
        hue[bb] += 1
    if hue.sum() > 0:
        hue /= hue.sum()
    return {
        "hash": hx,
        "hue": [round(float(v), 4) for v in hue],
        "aspect": round(sw / sh, 3),
        "density": round(float(mask.sum() / (sw * sh)), 3),
    }


def load_scope():
    """再生成の対象スコープ。原則は regulation.json の species スコープ
    (Champions 実装範囲)。champions_dex.json は全種族ユニバース化されるため、
    スコープが regulation.json に無い間だけ暫定で dex の species を使う。"""
    reg = load_json(os.path.join(DATA, "regulation.json"))
    scope = reg.get("species")
    if isinstance(scope, list) and scope:
        return scope
    return load_json(os.path.join(DATA, "champions_dex.json"))["species"]


def main():
    check_only = "--check" in sys.argv
    dex = load_scope()
    types = load_json(os.path.join(DATA, "species_types.json"))
    feats = load_json(os.path.join(DATA, "preview_features.json"))
    missing = [s for s in dex if s not in types or s not in feats]
    print(f"dex {len(dex)} 種 / types {len(types)} / features {len(feats)} / 未収録 {len(missing)}")
    if not missing:
        print("全種収録済みです")
        return
    if check_only:
        print("未収録:", ", ".join(missing))
        return
    smogon = smogon_species()
    added = []
    for name in missing:
        info = smogon.get(name)
        if info is None:
            raise RuntimeError(f"{name}: @smogon/calc に種族データがありません")
        path = sprite_path(name)
        f = features_from_sprite(path)
        if f is None:
            raise RuntimeError(f"{name}: スプライトから特徴を計算できませんでした")
        entry = {"types": info["types"]}
        if info["base"] != name:
            entry["base"] = info["base"]
        types[name] = entry
        feats[name] = f
        added.append(name)
        print(f"  + {name} (types={info['types']})")
    # キー順は dex 順、整形は既存ファイルと同一にそろえて書き出す
    types = {s: types[s] for s in dex if s in types}
    feats = {s: feats[s] for s in dex if s in feats}
    # 整形の既存形式に合わせる: types は indent=1 + UTF-8 のまま、
    # features は 1 行 + 非 ASCII を \uXXXX エスケープ (どちらも末尾改行なし)
    with open(os.path.join(DATA, "species_types.json"), "w", encoding="utf-8") as fp:
        fp.write(json.dumps(types, indent=1, ensure_ascii=False))
    with open(os.path.join(DATA, "preview_features.json"), "w", encoding="utf-8") as fp:
        fp.write(json.dumps(feats))
    print(f"追加 {len(added)} 種 -> types {len(types)} / features {len(feats)}")


if __name__ == "__main__":
    main()
