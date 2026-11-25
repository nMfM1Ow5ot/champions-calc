#!/usr/bin/env python3
"""選出同定 (見せあい画面でのポケモン判定) の精度測定。

使い方: python3 tests/preview_eval.py [--download] [--frames-only] [--quick]

2 つの測定モードがある。

1. 実フレーム測定 (preview_eval/frames/)
   preview_eval/frames/ に見せあい画面のスクリーンショット (PNG) と
   frames.json ({"ファイル名": [相手6体の種族名(英語), ...]}) を置くと、
   reader.swift の identifyPreview と同じ手順 (パネル検出・アイコン分類・
   モデル照合・タイプ関門の緩和・枠間割り当て) を Python で再現して
   フレーム単位の同定率を測る。正解付きフレームが無い場合はスキップする。
   自分のチームの見せあい画面は種族が既知なので、検証材料に最適。

2. スプライト代理測定 (preview_eval/sprites/)
   HOME スプライトをパネル風に描画 (縮小・明るさ・位置のゆらぎ付き) して
   「4 フレーム分のパネル」を作り、同定率を構成別に比較する。実フレームの
   代替ではなく、方式変更 (参照の全種カバー / 関門の緩和 / 投票マージ /
   ハッシュ縮小方式) の効果を数値で比較するための代理指標。
   スプライトは PokéAPI から取得し preview_eval/sprites/ にキャッシュする
   (--download で不足分を取得。取得したスプライトは参照特徴との照合で
   正しい種族のものか検証し、検証できない種族は測定から除外して明示する)。

reader.swift との対応:
   - pvScore / pvModelFeatures (最大連結成分・背景差分) を等価実装している
   - ハッシュ縮小は面積平均 (旧 reader) とバイリニア (参照生成方式・
     修正後の reader) の両方を測れる
   - タイプ関門の緩和 (pvSoftGateScore = 0.25) と投票マージは
     reader.swift の実装と同じ規則で再現する
   - 性別マーク (♂♀) の読み取りと候補の絞り込み、全種族へ広げた際の
     採用マージン (0.20) も reader.swift と同じ規則で再現する
     (2026-11-21 の実フレームで較正)
"""
import itertools
import json
import math
import os
import random
import subprocess
import zlib
import sys

import numpy as np
from PIL import Image

BASE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA = os.path.join(BASE, "data")
SPRITES = os.path.join(BASE, "preview_eval", "sprites")
FRAMES = os.path.join(BASE, "preview_eval", "frames")
BG = (238, 238, 232)
SOFT_GATE = 0.25
# 全種族へ広げた再照合を採用する条件: 広げた先の最良が元の最良より
# この値以上良いこと。実フレーム (2026-11-21) では正しいプールの
# スコアが HOME 参照とのポーズ差で 0.4 前後まで悪化し、従来の 0.03
# では無関係な種族への飛び移りが起きた。代理測定では読み違い時の
# 救済率を下げないことも確認済み
EXPAND_MARGIN = 0.20
ALL_TYPES = ["Normal", "Fire", "Water", "Electric", "Grass", "Ice", "Fighting",
             "Poison", "Ground", "Flying", "Psychic", "Bug", "Rock", "Ghost",
             "Dragon", "Dark", "Steel", "Fairy"]

# ---------- 基本ユーティリティ (reader.swift の pv* と等価) ----------

def resize_area(src, dw, dh):
    """Swift pvResizeGray (面積平均) と等価。"""
    sh, sw = src.shape
    out = np.zeros((dh, dw))
    for dy in range(dh):
        y0 = dy * sh / dh
        y1 = (dy + 1) * sh / dh
        for dx in range(dw):
            x0 = dx * sw / dw
            x1 = (dx + 1) * sw / dw
            s = 0.0
            yy = int(y0)
            while yy < int(math.ceil(y1)) and yy < sh:
                wy = min(y1, yy + 1) - max(y0, yy)
                xx = int(x0)
                while xx < int(math.ceil(x1)) and xx < sw:
                    wx = min(x1, xx + 1) - max(x0, xx)
                    s += src[yy, xx] * wx * wy
                    xx += 1
                yy += 1
            out[dy, dx] = s / ((x1 - x0) * (y1 - y0))
    return out


def resize_bilinear(src, dw, dh):
    """cv2.INTER_LINEAR 相当 (参照特徴の生成方式)。"""
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


def hue_hist(rgb, sel):
    r = rgb[:, :, 0] / 255.0
    g = rgb[:, :, 1] / 255.0
    b = rgb[:, :, 2] / 255.0
    mx = np.maximum(np.maximum(r, g), b)
    mn = np.minimum(np.minimum(r, g), b)
    d = mx - mn
    dd = np.where(d == 0, 1, d)
    hdeg = np.zeros_like(mx)
    idx = (mx == r) & (d > 0)
    hdeg[idx] = (60 * ((g - b) / dd) % 360)[idx]
    idx = (mx == g) & (d > 0)
    hdeg[idx] = (60 * ((b - r) / dd) + 120)[idx]
    idx = (mx == b) & (d > 0)
    hdeg[idx] = (60 * ((r - g) / dd) + 240)[idx]
    hue = np.zeros(24)
    bins = np.minimum((hdeg[sel] / 15).astype(int), 23)
    for bb in bins:
        hue[bb] += 1
    n = hue.sum()
    if n > 0:
        hue /= n
    return hue


def hash_from_gray(gray, mode):
    small = (resize_area if mode == "area" else resize_bilinear)(gray, 17, 16)
    bits = [1 if small[yy, xx + 1] > small[yy, xx] else 0
            for yy in range(16) for xx in range(16)]
    out = []
    for i in range(0, 256, 8):
        v = 0
        for bit in bits[i:i + 8]:
            v = (v << 1) | bit
        out.append(v)
    return "".join(f"{v:02x}" for v in out)


def features_from_sprite(path):
    """参照生成方式 (全画素・バイリニア)。build_preview_features.py と同一。"""
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
    return {"hash": hash_from_gray(gray, "bilinear"), "hue": hue_hist(rgb, mask),
            "aspect": sw / sh, "density": float(mask.sum() / (sw * sh))}


def features_from_rendered(img_rgb, hash_mode, bg=BG):
    """Swift pvModelFeatures と等価 (背景差分 → 最大連結成分)。"""
    from scipy import ndimage
    a = img_rgb.astype(int)
    diff = np.abs(a[:, :, 0] - bg[0]) + np.abs(a[:, :, 1] - bg[1]) + np.abs(a[:, :, 2] - bg[2])
    mask = diff > 90
    lab, n = ndimage.label(mask, structure=np.ones((3, 3), int))
    if n == 0:
        return None
    sizes = ndimage.sum(mask, lab, range(1, n + 1))
    cc = lab == (int(np.argmax(sizes)) + 1)
    if sizes.max() < 20:
        return None
    ys, xs = np.where(cc)
    x0, x1, y0, y1 = xs.min(), xs.max(), ys.min(), ys.max()
    sw, sh = x1 - x0 + 1, y1 - y0 + 1
    rgb = img_rgb.astype(float)
    g = 0.299 * rgb[:, :, 0] + 0.587 * rgb[:, :, 1] + 0.114 * rgb[:, :, 2]
    gray = np.full((sh, sw), 128.0)
    m2 = cc[y0:y1 + 1, x0:x1 + 1]
    gray[m2] = g[y0:y1 + 1, x0:x1 + 1][m2]
    return {"hash": hash_from_gray(gray, hash_mode), "hue": hue_hist(rgb, cc),
            "aspect": sw / sh, "density": float(cc.sum() / (sw * sh))}


def pearson(a, b):
    a = np.asarray(a, float)
    b = np.asarray(b, float)
    if a.std() == 0 or b.std() == 0:
        return 0.0
    return float(np.corrcoef(a, b)[0, 1])


def pv_score(f, ref):
    diff = sum(bin(x ^ y).count("1")
               for x, y in zip(bytes.fromhex(f["hash"]), bytes.fromhex(ref["hash"])))
    hd = diff / 256.0
    hc = pearson(f["hue"], ref["hue"])
    return (hd - 0.35 * hc + 0.15 * abs(math.log(f["aspect"] / ref["aspect"]))
            + 0.25 * abs(f["density"] - ref["density"]))


def ref_from_json(d):
    return {"hash": d["hash"], "hue": np.array(d["hue"], float),
            "aspect": float(d["aspect"]), "density": float(d["density"])}


def templates_from_json(feat_obj):
    """preview_features.json の各エントリの "templates" を
    {種族: [{feat, gender, src, tag}]} に変換する。"""
    out = {}
    for name, d in feat_obj.items():
        ts = []
        for t in d.get("templates", []) if isinstance(d, dict) else []:
            ts.append({"feat": ref_from_json(t), "gender": t.get("gender", ""),
                       "src": t.get("src", ""), "tag": t.get("tag", "frame")})
        if ts:
            out[name] = ts
    return out


# 姿・色に実質的な性別差がある種族 (フォルム自体が雌雄を表す
# Meowstic / Indeedee / Basculegion 等は除く)。これらの種族でのみ、
# テンプレートの性別で絞り込む
PV_GENDER_DIMORPHIC = {"Hippowdon", "Pyroar", "Pikachu", "Scizor",
                       "Heracross", "Weavile"}


def pv_best_score(f, name, refs, templates, gender=None, exclude_src=None):
    """種族のスコア = 本参照と、適格なテンプレート群の最小スコア。
    性別による絞り込みは、性別差のある種族で雌雄両方のテンプレートが
    あるときだけ行う (性別差の無い種族では、個体の性別タグは見た目と
    無関係なため絞り込まない)。exclude_src は同一フレーム由来の
    自己参照を避ける評価用。"""
    best = pv_score(f, refs[name]) if name in refs else None
    ts = [t for t in templates.get(name, [])
          if not (exclude_src and t["src"] == exclude_src)]
    # 色違い個体のテンプレートは通常照合に使わない (reader.swift と同じ。
    # 色相特徴が通常個体と異なり通常側の照合を汚染するため、2026-11-24 の恒常ルール)
    ts = [t for t in ts if t["tag"] != "shiny"]
    if gender and name in PV_GENDER_DIMORPHIC:
        genders = {t["gender"] for t in ts if t["gender"]}
        if gender in genders and len(genders) >= 2:
            ts = [t for t in ts if t["gender"] in ("", gender)]
    for t in ts:
        s = pv_score(f, t["feat"])
        if best is None or s < best:
            best = s
    return best


# ---------- スプライト取得 (スラッグ候補 + 参照との照合で検証) ----------

def slug_candidates(name):
    base = name.lower().replace("’", "").replace("'", "").replace(".", "").replace(" ", "-")
    cands = [base]
    if base.endswith("-f"):
        cands.append(base[:-2] + "-female")
    if base.endswith("-m"):
        cands.append(base[:-2] + "-male")
    if base.startswith("tauros-paldea-"):
        cands.append(base + "-breed")
    if base.startswith("meowstic-f-"):
        cands.append("meowstic-female-mega")
    if base.startswith("meowstic-m-"):
        cands.append("meowstic-male-mega")
    if base == "toxtricity":
        cands.append("toxtricity-amped")
    if base == "palafin":
        cands.append("palafin-zero")
    if base.startswith("pikachu-"):
        cands.append(base + "-cap")
    # 模様・フォルム違いは基本種のスプライトで検証する
    for suffix in ("-fancy", "-pokeball", "-antique", "-masterpiece"):
        if base.endswith(suffix):
            cands.append(base[: -len(suffix)])
    return cands


def ensure_sprite(name, ref):
    """検証済みスプライトのパスを返す。取得・検証できない場合は None。"""
    for slug in slug_candidates(name):
        path = os.path.join(SPRITES, slug + ".png")
        if not os.path.exists(path):
            try:
                info = subprocess.run(
                    ["curl", "-sL", "--max-time", "30", "-A",
                     "champions-calc-preview-eval",
                     f"https://pokeapi.co/api/v2/pokemon/{slug}"],
                    capture_output=True, timeout=40)
                d = json.loads(info.stdout.decode("utf-8"))
                url = d["sprites"]["other"]["home"]["front_default"]
                if not url:
                    continue
                os.makedirs(SPRITES, exist_ok=True)
                subprocess.run(["curl", "-sL", "--max-time", "30", "-A",
                                "champions-calc-preview-eval", "-o", path, url],
                               capture_output=True, timeout=40)
            except Exception:
                continue
        if not os.path.exists(path):
            continue
        f = features_from_sprite(path)
        if f is None:
            continue
        ham = sum(bin(x ^ y).count("1")
                  for x, y in zip(bytes.fromhex(f["hash"]), bytes.fromhex(ref["hash"])))
        # ハッシュが近ければ同一種のスプライトとみなす (色相は赤系の
        # ラップアラウンド等で参照側とずれる種族があるため補助扱い)
        if ham < 40 or (ham < 80 and pearson(f["hue"], ref["hue"]) > 0.9):
            return path
    return None


# ---------- 同定ミラー (identifyPreview の 1 枠分) ----------

def battle_only_formes(names):
    """見せ合い画面に現れないフォルム (メガ + 対戦中だけの姿)。
    reader.swift の pvBattleOnlyFormes と同じ定義。"""
    out = {n for n in names
           if n.endswith("-Mega") or n.endswith("-Mega-X") or n.endswith("-Mega-Y")
           or n.endswith("-Mega-Z")}
    out |= {n for n in ("Greninja-Bond", "Palafin-Hero", "Mimikyu-Busted",
                        "Morpeko-Hangry") if n in names}
    return out


def identify_slot(f, types_read, types_map, refs, gate, verify_decisive,
                  exclude_battle=False, templates=None, gender=None,
                  exclude_src=None):
    templates = templates or {}
    """1 枠分の同定。(pick, score, decisive) を返す。pick は None のことがある。"""
    pool = []
    if len(types_read) == 2:
        pool = [n for n, t in types_map.items() if set(t) == set(types_read)]
    elif len(types_read) == 1:
        pool = [n for n, t in types_map.items() if t == types_read]
    expanded = False
    if not pool and types_read:
        pool = list(refs.keys())
        expanded = True
    if exclude_battle:
        bo = battle_only_formes(types_map.keys())
        pool = [n for n in pool if n not in bo]
    if not pool:
        return (None, 9.0, False)
    ranked = sorted(((pv_best_score(f, n, refs, templates, gender, exclude_src), n)
                     for n in pool if n in refs))
    if not ranked:
        return (None, 9.0, False)
    decisive = False
    if len(pool) == 1 and not expanded:
        if not verify_decisive or ranked[0][0] <= SOFT_GATE:
            decisive = True
        # スコアが悪くても展開で上書きしない (小プール保護)
    elif gate == "soft" and ranked[0][0] > SOFT_GATE and len(pool) > 2:
        allr = sorted(((pv_best_score(f, n, refs, templates, gender, exclude_src), n)
                       for n in refs
                       if not exclude_battle or n not in battle_only_formes(types_map.keys())))
        if allr and allr[0][0] < ranked[0][0] - EXPAND_MARGIN:
            ranked = allr
    score, pick = ranked[0]
    return (pick, score, decisive)


def merge_frames(frame_picks, merge):
    """frame_picks: [(pick, score, decisive), ...] を最終 pick にまとめる。"""
    if merge == "last":
        for pick, _, _ in reversed(frame_picks):
            if pick is not None:
                return pick
        return None
    # voting: reader.swift の投票マージと同一規則
    votes = {}
    best = {}
    locked = None
    for pick, score, decisive in frame_picks:
        if pick is None:
            continue
        votes[pick] = votes.get(pick, 0) + 1
        if score < best.get(pick, float("inf")):
            best[pick] = score
        if locked is None and (decisive or votes[pick] >= 2):
            locked = pick
    if locked is not None:
        return locked
    if not votes:
        return None
    return sorted(votes.keys(),
                  key=lambda n: (-votes[n], best.get(n, 9.0), n))[0]


# ---------- スプライト代理測定 ----------

def render_frame(sprite_path, rng):
    spr = Image.open(sprite_path).convert("RGBA")
    target_h = rng.uniform(115, 150)
    scale = target_h / spr.height
    nw, nh = max(8, int(spr.width * scale)), max(8, int(spr.height * scale))
    s2 = spr.resize((nw, nh), Image.LANCZOS)
    bright = rng.uniform(0.92, 1.08)
    arr = np.array(s2).astype(float)
    arr[:, :, :3] = np.clip(arr[:, :, :3] * bright, 0, 255)
    s2 = Image.fromarray(arr.astype(np.uint8), "RGBA")
    canvas = Image.new("RGB", (220, 180), BG)
    x = (220 - nw) // 2 + rng.randint(-6, 6)
    y = (180 - nh) // 2 + rng.randint(-4, 4)
    canvas.paste(s2, (x, y), s2)
    return np.array(canvas)


def corrupt_types(types, rng):
    """アイコン読み違いの模擬: 複合タイプは第2タイプを別タイプに、
    単タイプは別タイプへの置き換え、を deterministic に行う。"""
    others = [t for t in ALL_TYPES if t not in types]
    wrong = others[rng.randrange(len(others))]
    if len(types) == 2:
        return [types[0], wrong]
    return [wrong]


CONFIGS = [
    # (名前, 参照368か, 関門, マージ, ハッシュ方式, 確定の照合検証, 対戦中フォルム除外)
    ("A 旧方式 (286種/硬い関門/後勝ち/面積平均)", False, "hard", "last", "area", False, False),
    ("B 全種+緩和 (面積平均のまま/後勝ち)", True, "soft", "last", "area", True, False),
    ("C 全種+緩和+ハッシュ修正 (後勝ち)", True, "soft", "last", "bilinear", True, False),
    # D は現在の出荷形: 対戦中だけのフォルム (メガ等) を候補から除外し、
    # 対象も見せ合いに出る種族だけに数える (実画面の分布に合わせた定義)
    ("D 現在の出荷形 (全種+緩和+ハッシュ修正+投票+対戦中フォルム除外)", True, "soft", "vote", "bilinear", True, True),
]

# 優先確認対象: 実戦で見落としが確認された種族は、全体の同定率とは別に
# 個別結果を常時表示し、参照や方式の変更で悪化したらすぐ分かるようにする。
# - Samurott / Samurott-Hisui: 2026-11-20 の vs Ryzz 戦 2 試合
#   (battle_20261120_122653 / battle_20261120_124322) で、相手の実際の
#   ダイケンキ (通常フォルム) が見せ合い同定の 6 体に入らなかった。
#   ログ分析チャットからの委任 (2026-11-21) で優先確認対象に追加
# - Typhlosion / Typhlosion-Hisui: 2026-11-21 の vs KAM 戦
#   (battle_20261121_140658) で、相手のバクフーン (特性おみとおし =
#   ヒスイフォルムの証拠) が見せ合い同定の 6 体に入らず、交代行も
#   通常フォルムで記録された。フォルム区別の確認対象として追加
#   (ログ分析チャットからの確認依頼、2026-11-21)
# - Froslass: 2026-11-21 の vs KaguyaFalls 戦 (battle_20261121_144858)
#   で、相手の先発ユキメノコが見せ合い同定の 6 体に入らなかった
#   (誤認先は証拠保存の不具合で特定できず)。実フレームでも正解
#   スコアが関門近くまで悪化する枠があったため、個別に追跡する
#   (ログ分析チャットからの指示、2026-11-21)
PRIORITY_SPECIES = ["Samurott", "Samurott-Hisui", "Typhlosion", "Typhlosion-Hisui", "Froslass",
                    "Floette-Eternal"]


def load_scope():
    """評価対象のスコープ: regulation.json の species (Champions 実装範囲)。
    champions_dex は全種族ユニバース化されるため、スコープが無い間だけ
    暫定で dex の species を使う (build_preview_features.py と同じ規則)。"""
    reg = json.load(open(os.path.join(DATA, "regulation.json")))
    scope = reg.get("species")
    if isinstance(scope, list) and scope:
        return scope
    return json.load(open(os.path.join(DATA, "champions_dex.json")))["species"]


def run_proxy(quick=False):
    dex = load_scope()
    types_new = {k: v["types"] for k, v in
                 json.load(open(os.path.join(DATA, "species_types.json"))).items()}
    feat_obj = json.load(open(os.path.join(DATA, "preview_features.json")))
    feats_new = {k: ref_from_json(v) for k, v in feat_obj.items()}
    templates_new = templates_from_json(feat_obj)
    # 旧 286 種の参照は、新ファイルから「メガでない種族」で再構成する
    # (旧エントリは新ファイルにそのまま保存されているため等価)
    base_species = [s for s in dex if "Mega" not in s]
    types_old = {k: types_new[k] for k in base_species if k in types_new}
    feats_old = {k: feats_new[k] for k in base_species if k in feats_new}

    species = dex if not quick else dex[::6]
    if quick:
        # 優先確認対象は quick 測定でも必ず対象に含める
        species = species + [p for p in PRIORITY_SPECIES
                             if p in dex and p not in species]
    verified = {}
    excluded = []
    for name in species:
        p = ensure_sprite(name, feats_new[name])
        if p:
            verified[name] = p
        else:
            excluded.append(name)
    print(f"検証済みスプライト: {len(verified)} / {len(species)} 種"
          + (f" (除外: {', '.join(excluded)})" if excluded else ""))

    # フレーム特徴を先に計算する (構成間で共通)。
    # 描画の乱数は種族ごとに固定する: 検証済みスプライトの集合が
    # 実行ごとに変わっても (取得の成否等)、各種族のフレームが
    # 他種族の採否に影響されず、測定が再現可能になる
    frames = {}  # name -> [(feat_area, feat_bilinear), ...] x4
    for name, path in verified.items():
        rng = random.Random(zlib.crc32(name.encode()))
        per = []
        for _ in range(4):
            img = render_frame(path, rng)
            per.append((features_from_rendered(img, "area"),
                        features_from_rendered(img, "bilinear")))
        frames[name] = per

    # 正解スコアの分布 (関門閾値の較正用、バイリニア・正しいタイプ)
    true_scores = []
    for name, per in frames.items():
        f = per[0][1]
        if f is not None:
            true_scores.append(pv_score(f, feats_new[name]))
    true_scores.sort()
    if true_scores:
        n = len(true_scores)
        print(f"正解種族のスコア (frame1, bilinear): p50={true_scores[n//2]:.3f} "
              f"p90={true_scores[int(n*0.9)]:.3f} p99={true_scores[int(n*0.99)]:.3f} "
              f">{SOFT_GATE} の割合={sum(1 for s in true_scores if s > SOFT_GATE)/n:.1%}")

    def evaluate(cfg, scenario):
        _, use_new, gate, merge, hash_mode, verify_dec, excl_battle = cfg
        types_map = types_new if use_new else types_old
        refs = feats_new if use_new else feats_old
        hi = 0 if hash_mode == "area" else 1
        bo = battle_only_formes(types_new.keys())
        ok = 0
        total = 0
        ok_base = 0
        total_base = 0
        for name, per in frames.items():
            if excl_battle and name in bo:
                continue  # 見せ合いに出ないフォルムは対象に数えない
            rng2 = random.Random(zlib.crc32(name.encode()) & 0xFFFF)
            t_read = types_new[name]
            if scenario == "misread":
                t_read = corrupt_types(t_read, rng2)
            picks = []
            for pair in per:
                f = pair[hi]
                if f is None:
                    picks.append((None, 9.0, False))
                else:
                    picks.append(identify_slot(f, t_read, types_map, refs, gate, verify_dec,
                                               exclude_battle=excl_battle,
                                               templates=templates_new if use_new else None))
            if not use_new and name not in types_old:
                continue  # 旧参照に無い種族 (メガ) は旧方式の対象外として数えない
            final = merge_frames(picks, merge)
            total += 1
            if name in base_species:
                total_base += 1
            if final == name:
                ok += 1
                if name in base_species:
                    ok_base += 1
        return ok, total, ok_base, total_base

    for scenario in ("correct", "misread"):
        print(f"\n--- アイコン読み: {'正しい' if scenario == 'correct' else '1つ読み違い'} ---")
        print(f"{'構成':<46} {'全体':>12} {"非メガ":>14}")
        for cfg in CONFIGS:
            ok, total, okb, totalb = evaluate(cfg, scenario)
            print(f"{cfg[0]:<44} {ok:>4}/{total:<4} {ok/total:>5.1%} "
                  f"{okb:>4}/{totalb:<4} {okb/totalb:>5.1%}")

    # 優先確認対象の個別結果 (構成 D = 出荷形のみ。全体率に埋もれさせない)
    print("\n--- 優先確認対象 (構成D・個別) ---")
    for name in PRIORITY_SPECIES:
        if name not in frames:
            print(f"{name}: 検証済みスプライトが無いため未測定")
            continue
        for scenario in ("correct", "misread"):
            rng2 = random.Random(zlib.crc32(name.encode()) & 0xFFFF)
            t_read = types_new[name]
            if scenario == "misread":
                t_read = corrupt_types(t_read, rng2)
            picks = []
            for pair in frames[name]:
                f = pair[1]  # bilinear
                picks.append(identify_slot(f, t_read, types_new, feats_new,
                                           "soft", True, exclude_battle=True) if f else (None, 9.0, False))
            final = merge_frames(picks, "vote")
            mark = "○" if final == name else "×"
            desc = ", ".join(f"{p}({s:.2f})" if p else "-" for p, s, _ in picks)
            print(f"{name} [{'正しい' if scenario == 'correct' else '読み違い'}] "
                  f"最終={final} {mark} フレーム別: {desc}")


# ---------- 実フレーム測定 (reader.swift の identifyPreview を全面ミラー) ----------

def pv_detect_panels(buf):
    """Swift pvDetectPanels と等価。buf は (H, W, 3) float 配列。"""
    H, W = buf.shape[:2]
    r = buf[:, :, 0]
    g = buf[:, :, 1]
    b = buf[:, :, 2]
    maroon = (r > 90) & (r - g > 45) & (r - b > 15)
    xs, xe = int(0.55 * W), int(0.995 * W)
    groups = []
    start = None
    last = 0
    row_counts = []
    for y in range(H):
        cnt = int(maroon[y, xs:xe:2].sum())
        row_counts.append(cnt)
        if cnt > (xe - xs) / 20:
            if start is None:
                start = y
            last = y
        elif start is not None and y - last > 4:
            groups.append((start, last))
            start = None
    if start is not None:
        groups.append((start, last))
    raw = [gr for gr in groups if gr[1] - gr[0] >= int(0.05 * H)]
    # 異常に背の高い帯は、エフェクト等でつながった 2 枚のパネルとして
    # 内部の最小カウント行で分割する (Swift と同ロジック)
    for _ in range(3):
        if len(raw) < 2:
            break
        hs = sorted(gr[1] - gr[0] + 1 for gr in raw)
        med = hs[len(hs) // 2]
        tall = max(raw, key=lambda gr: gr[1] - gr[0] + 1)
        if tall[1] - tall[0] + 1 <= 1.6 * med:
            break
        lo = tall[0] + (tall[1] - tall[0]) // 5
        hi = tall[1] - (tall[1] - tall[0]) // 5
        if hi <= lo:
            break
        split_row = min(range(lo, hi + 1), key=lambda y: row_counts[y])
        raw.remove(tall)
        raw += [(tall[0], split_row), (split_row + 1, tall[1])]
        raw = sorted(gr for gr in raw if gr[1] - gr[0] >= int(0.05 * H))
    if len(raw) > 6:
        # コスト = 間隔の分散 + 高さ偏差の二乗和 (Swift と同ロジック)
        from itertools import combinations
        hs = sorted(gr[1] - gr[0] + 1 for gr in raw)
        med = hs[len(hs) // 2]
        best = None
        for combo in combinations(range(len(raw)), 6):
            ys = [raw[i][0] for i in combo]
            diffs = [ys[k + 1] - ys[k] for k in range(5)]
            mean = sum(diffs) / 5.0
            var = sum((d - mean) ** 2 for d in diffs)
            hdev_sq = sum(((raw[i][1] - raw[i][0] + 1) - med) ** 2 for i in combo)
            key = var + hdev_sq
            if best is None or key < best[0]:
                best = (key, combo)
        raw = [raw[i] for i in best[1]]
    if len(raw) == 6:
        x0s, x1s = [], []
        for (gy0, gy1) in raw:
            need = (gy1 - gy0 + 1) / 2
            colcnt = maroon[gy0:gy1 + 1, xs:xe].sum(axis=0)
            cols = np.where(colcnt > need)[0]
            if len(cols):
                x0s.append(xs + int(cols.min()))
                x1s.append(xs + int(cols.max()))
        if len(x0s) == 6:
            mx0 = sorted(x0s)[3]
            mx1 = sorted(x1s)[3]
            maroon_w = mx1 - mx0 + 1
            hs = sorted(gr[1] - gr[0] + 1 for gr in raw)
            med_h = hs[3]
            uniform = all(abs((gr[1] - gr[0] + 1) - med_h) <= 0.35 * med_h for gr in raw)
            sample_w = max(maroon_w, int(med_h * 2.6 + 0.5))
            if (uniform and int(0.50 * W) <= mx0 <= int(0.92 * W)
                    and int(0.08 * W) <= sample_w <= int(0.30 * W)):
                return [(mx0, y0, sample_w, y1 - y0 + 1, maroon_w) for (y0, y1) in raw]
        pw, px = int(0.154 * W), int(0.811 * W)
        return [(px, y0, pw, y1 - y0 + 1, pw) for (y0, y1) in raw]
    pw, px = int(0.154 * W), int(0.811 * W)
    return [(px, int(f * H), pw, int(0.094 * H), pw)
            for f in (0.180, 0.279, 0.378, 0.473, 0.576, 0.670)]


PV_ICON_AMBIG_DELTA = 0.05


def pv_classify_icon(buf, x0in, y0in, s, type_icons, exclude_src=None):
    """Swift pvClassifyIcon と等価。(type|None, present, score, alt, gap) を返す。
    alt/gap は採用窓での2位タイプとその距離差 (近接時の曖昧さ)。
    タイプごとの距離は単一参照と実サンプル群 (samples) の最小値
    (テンプレート照合、2026-11-24)。exclude_src のフレーム由来の
    サンプルは同定対象から除く (種族テンプレートの exclude と同じ)。"""
    H, W = buf.shape[:2]
    x0 = max(0, min(x0in, W - s))
    y0 = max(0, min(y0in, H - s))
    cell = buf[y0:y0 + s, x0:x0 + s]
    gray = 0.299 * cell[:, :, 0] + 0.587 * cell[:, :, 1] + 0.114 * cell[:, :, 2]
    std = float(gray.std())
    if std <= 30:
        return (None, False, 999.0, None, 999.0)
    flat = cell.reshape(-1, 3)
    kept = flat[flat.mean(axis=1) < 210]
    src = kept if len(kept) else flat
    rgb = [float(np.median(src[:, i])) for i in range(3)]
    if (rgb[0] >= 195 and rgb[1] >= 145 and rgb[2] <= 135
            and rgb[0] - rgb[2] >= 110 and rgb[1] - rgb[2] >= 50
            and rgb[0] >= rgb[1] - 10):
        cd = math.sqrt((rgb[0] - 247) ** 2 + (rgb[1] - 197) ** 2 + (rgb[2] - 28) ** 2) / 441.7
        return ("Electric", True, 0.05 + cd * 0.3, None, 999.0)
    grid = resize_area(gray, 12, 12).reshape(-1)
    scored = []
    for t, tp in type_icons.items():
        if len(tp["rgb"]) < 3 or len(tp["glyph"]) != 144:
            continue
        cands = [(tp["rgb"], tp["glyph"])]
        for smp in tp.get("samples", []):
            if exclude_src is not None and smp.get("src") == exclude_src:
                continue
            if len(smp["rgb"]) >= 3 and len(smp["glyph"]) == 144:
                cands.append((smp["rgb"], smp["glyph"]))
        td = None
        for crgb, glyph in cands:
            corr = pearson(grid, glyph)
            cd = math.sqrt(sum((rgb[i] - crgb[i]) ** 2 for i in range(3))) / 441.7
            d = ((1 - corr) / 2) * 0.7 + cd * 0.3
            if td is None or d < td:
                td = d
        scored.append((t, td))
    scored.sort(key=lambda kv: kv[1])
    if not scored:
        return (None, True, 999.0, None, 999.0)
    best, bs = scored[0]
    if bs >= 0.42:
        return (None, True, bs, None, 999.0)
    alt, gap = None, 999.0
    if len(scored) > 1:
        alt, gap = scored[1][0], scored[1][1] - bs
    return (best, True, bs, alt, gap)


def pv_classify_icon_search(buf, x0, y0, s, type_icons, exclude_src=None):
    center = pv_classify_icon(buf, x0, y0, s, type_icons, exclude_src)
    if not center[1]:
        return center
    best = center
    for dy in (-s // 5, 0, s // 5):
        for dx in (-s // 6, 0, s // 6):
            r = pv_classify_icon(buf, x0 + dx, y0 + dy, s, type_icons, exclude_src)
            if r[2] < best[2]:
                best = r
    return best


def _pv_features_with_bg(buf, panel, bg):
    """指定した背景色で特徴抽出する (Swift pvFeaturesWithBg と等価)。
    (特徴, cover, widthRatio) を返す。"""
    from scipy import ndimage
    px, py, pw, ph = panel
    H, W = buf.shape[:2]
    cw, ch = int(0.52 * pw), ph
    if cw <= 0 or ch <= 0:
        return None
    region = buf[py:py + ch, px:px + cw].astype(int)
    diff = np.abs(region[:, :, 0] - bg[0]) + np.abs(region[:, :, 1] - bg[1]) + np.abs(region[:, :, 2] - bg[2])
    mask = diff > 90
    lab, n = ndimage.label(mask, structure=np.ones((3, 3), int))
    if n == 0:
        return None
    sizes = ndimage.sum(mask, lab, range(1, n + 1))
    if sizes.max() < 20:
        return None
    cc = lab == (int(np.argmax(sizes)) + 1)
    ys, xs = np.where(cc)
    x0, x1, y0, y1 = xs.min(), xs.max(), ys.min(), ys.max()
    sw, sh = x1 - x0 + 1, y1 - y0 + 1
    rgb = region.astype(float)
    g = 0.299 * rgb[:, :, 0] + 0.587 * rgb[:, :, 1] + 0.114 * rgb[:, :, 2]
    gray = np.full((sh, sw), 128.0)
    m2 = cc[y0:y1 + 1, x0:x1 + 1]
    gray[m2] = g[y0:y1 + 1, x0:x1 + 1][m2]
    feat = {"hash": hash_from_gray(gray, "bilinear"), "hue": hue_hist(rgb, cc),
            "aspect": sw / sh, "density": float(cc.sum() / (sw * sh))}
    return (feat, float(cc.sum() / (cw * ch)), sw / cw)


def pv_model_features_frame(buf, panel):
    """Swift pvModelFeatures と等価。背景はまず 1 点サンプルで推定し、
    成分が切り出し幅いっぱい (98% 以上) か面積の 6 割以上なら推定失敗
    とみなして、切り出し内の最頻色 (パネル地の色) で抽出をやり直す。
    両方とも失敗なら特徴なし (None)。"""
    px, py, pw, ph = panel
    H, W = buf.shape[:2]
    cw = int(0.52 * pw)
    if cw <= 0 or ph <= 0:
        return None
    bgx = max(0, min(px + int(0.55 * pw), W - 1))
    bgy = max(0, min(py + 4, H - 1))
    bg_point = buf[bgy, bgx].astype(int)
    first = _pv_features_with_bg(buf, panel, bg_point)
    if first is not None and first[2] < 0.98 and first[1] < 0.60:
        return first[0]
    region = buf[py:py + ph, px:px + cw].astype(int)
    q = region // 32
    keys = q[:, :, 0] * 64 + q[:, :, 1] * 8 + q[:, :, 2]
    vals, counts = np.unique(keys, return_counts=True)
    bg_mode = region[keys == vals[np.argmax(counts)]].mean(axis=0)
    second = _pv_features_with_bg(buf, panel, bg_mode)
    if second is not None and second[2] >= 0.98 and second[1] >= 0.60:
        return None
    if second is not None:
        return second[0]
    return first[0] if first is not None else None


def pv_read_gender(buf, panel):
    """Swift pvReadGender と等価。パネル右下の性別マーク (♂=青 / ♀=赤)
    を読む。位置は実フレームで実測 (中心はパネル相対 x=0.716, y=0.75)。
    読めない場合は None (性別なしの種族はマーク自体が出ないため、
    絞り込みには使わない)。"""
    px, py, pw, ph = panel
    cx, cy = px + int(0.716 * pw), py + int(0.75 * ph)
    half = int(0.08 * pw)
    win = buf[max(0, cy - half):cy + half, max(0, cx - half):cx + half]
    if win.size == 0:
        return None
    R, G, B = win[:, :, 0], win[:, :, 1], win[:, :, 2]
    red = int(((R > 180) & (G < 110) & (B < 110)).sum())
    blue = int(((B > 150) & (R < 110) & ((B - R) > 60)).sum())
    best = max(red, blue)
    if best < 25 or best < 2 * min(red, blue):
        return (None, red, blue)
    return ("F" if red > blue else "M", red, blue)


def identify_preview_frame(img_rgb, types_map, refs, type_icons, gender_map,
                           templates=None, src_name=None):
    """Swift identifyPreview (第1段の出荷形 + 性別絞り込み) と等価。
    team (6枠) を返す。templates は実フレームテンプレート (任意)。
    src_name を渡すと、そのフレーム由来のテンプレートを除外する
    (同一フレームでの自己参照を避ける評価用)。"""
    templates = templates or {}
    buf = img_rgb.astype(float)
    panels = pv_detect_panels(buf)
    bo = battle_only_formes(types_map.keys())
    slot_ranked, slot_dec, slot_pool, slot_margin, slot_exp = [], [], [], [], []
    for panel in panels:
        px, py, pw, ph, cropw = panel
        gender = pv_read_gender(buf, (px, py, pw, ph))[0]
        types = []
        icon_cands = []
        icon_dists = []
        unknown = False
        icon_s = int(0.403 * ph)
        for slot in range(2):
            ix = px + int((0.620 if slot == 0 else 0.810) * pw)
            iy = py + int(0.050 * ph)
            t, present, _sc, alt, gap = pv_classify_icon_search(buf, ix, iy, icon_s, type_icons, exclude_src=src_name)
            if t:
                types.append(t)
                icon_dists.append(_sc)
                cands = [t]
                # 1位と2位が近接している場合は分類を確定とみなさず、
                # 両タイプのプールを統合する (距離逆転での誤固定の防止)
                if alt and gap < PV_ICON_AMBIG_DELTA:
                    cands.append(alt)
                icon_cands.append(cands)
            elif present:
                unknown = True
        # 幻像タイプの棄却 (Swift 側と等価): 片方が確実 (距離 0.15
        # 以下) で、もう片方が 0.30 以上なら、悪い方はアイコンの
        # 無い位置の背景を拾った幻像とみなして捨てる
        if len(icon_cands) == 2:
            if icon_dists[0] >= 0.30 and icon_dists[1] <= 0.15:
                types.pop(0)
                icon_cands.pop(0)
                icon_dists.pop(0)
            elif icon_dists[1] >= 0.30 and icon_dists[0] <= 0.15:
                types.pop()
                icon_cands.pop()
                icon_dists.pop()
        pool = []
        strict_pool = set()
        if icon_cands:
            combos = [set(c) for c in itertools.product(*icon_cands)]
            strict_combos = [set(c) for c in itertools.product(*[[c[0]] for c in icon_cands])]
            if unknown:
                pool = [n for n, tt in types_map.items()
                        if any(set(tt) >= c for c in combos)]
                strict_pool = {n for n, tt in types_map.items()
                               if any(set(tt) >= c for c in strict_combos)}
            else:
                pool = [n for n, tt in types_map.items() if set(tt) in combos]
                strict_pool = {n for n, tt in types_map.items() if set(tt) in strict_combos}
        expanded = False
        if not pool and types:
            pool = list(refs.keys())
            expanded = True
        if gender:
            gpool = [n for n in pool if gender in gender_map.get(n, ("M", "F", "N"))]
            if gpool:
                pool = gpool
        pool = [n for n in pool if n not in bo]
        if not pool:
            slot_ranked.append([]); slot_dec.append(False); slot_pool.append(0)
            slot_margin.append(0.0); slot_exp.append(False)
            continue
        f = pv_model_features_frame(buf, (px, py, cropw, ph))
        if f is None:
            if len(pool) == 1 and not expanded:
                slot_ranked.append([(pool[0], 0.0)]); slot_dec.append(True)
                slot_pool.append(1); slot_margin.append(9.0); slot_exp.append(False)
            else:
                slot_ranked.append([]); slot_dec.append(False)
                slot_pool.append(len(pool)); slot_margin.append(0.0); slot_exp.append(expanded)
            continue
        ranked = sorted(((pv_best_score(f, n, refs, templates, gender, src_name), n)
                         for n in pool if n in refs))
        ranked = [(n, s) for (s, n) in ranked]
        if not ranked:
            slot_ranked.append([]); slot_dec.append(False); slot_pool.append(len(pool))
            slot_margin.append(0.0); slot_exp.append(expanded)
            continue
        # アイコン近接で広げたプール側の種族が 1 位の場合、厳密プールの
        # 最良に対して展開マージン以上の差があるときだけ認める
        # (reader.swift の identifyPreview と同じ)
        strict_pool = {n for n in strict_pool if n not in bo}
        if strict_pool and ranked[0][0] not in strict_pool:
            sb = next((x for x in ranked if x[0] in strict_pool), None)
            if sb and ranked[0][1] > sb[1] - EXPAND_MARGIN:
                ranked = [sb] + [x for x in ranked if x[0] != sb[0]]
        decisive = False

        def all_ranked():
            allr = sorted(((pv_best_score(f, n, refs, templates, gender, src_name), n)
                           for n in refs if n not in bo))
            allr = [(n, s) for (s, n) in allr]
            if gender:
                gallr = [x for x in allr if gender in gender_map.get(x[0], ("M", "F", "N"))]
                if gallr:
                    allr = gallr
            return allr

        if len(pool) == 1 and not expanded:
            if ranked[0][1] <= SOFT_GATE:
                decisive = True
            # スコアが悪くても展開で上書きしない (小プール保護、
            # reader.swift の identifyPreview と同じ)
        elif ranked[0][1] > SOFT_GATE and len(pool) > 2:
            allr = all_ranked()
            if allr and allr[0][1] < ranked[0][1] - EXPAND_MARGIN:
                # タイプ読みと 1 つも重ならない展開先は、テンプレート級
                # (負値) の一致のときだけ採用する。タイプが正しく
                # 読めている枠で、無関係な種族の偶然の低スコアに
                # プールを捨てさせる事故の防止 (reader.swift と同じ)
                top_name, top_score = allr[0]
                if not (types and not (set(types_map.get(top_name, [])) & set(types)) and top_score >= 0.0):
                    ranked = allr
                    expanded = True
        slot_ranked.append(ranked); slot_dec.append(decisive); slot_exp.append(expanded)
        slot_pool.append(len(refs) if expanded else len(pool))
        slot_margin.append(ranked[1][1] - ranked[0][1] if len(ranked) > 1 else 1.0)
    used = set()
    team = [None] * len(panels)
    order = [i for i in range(len(panels)) if slot_ranked[i]]
    order.sort(key=lambda i: (not slot_dec[i], -slot_margin[i]))
    for i in order:
        pick = next((c for c in slot_ranked[i] if c[0] not in used), None)
        if pick is None:
            continue
        used.add(pick[0])
        team[i] = pick[0]
    return team


def run_frames():
    truth_path = os.path.join(FRAMES, "frames.json")
    if not os.path.isdir(FRAMES) or not os.path.exists(truth_path):
        print("実フレーム: preview_eval/frames/ に正解付きフレームが無いためスキップ"
              " (見せあい画面のスクリーンショットと frames.json を置くと測定できます)")
        return
    truth = json.load(open(truth_path))
    types_map = {k: v["types"] for k, v in
                 json.load(open(os.path.join(DATA, "species_types.json"))).items()}
    feat_obj = json.load(open(os.path.join(DATA, "preview_features.json")))
    refs = {k: ref_from_json(v) for k, v in feat_obj.items()}
    templates = templates_from_json(feat_obj)
    type_icons = json.load(open(os.path.join(DATA, "type_icons.json")))
    # 性別は species_types.json の "gender" に同梱されている
    gender_map = {k: tuple(v["gender"]) if v.get("gender") else ("M", "F", "N")
                  for k, v in json.load(open(os.path.join(DATA, "species_types.json"))).items()}
    total = 0
    correct = 0
    for fname, want in truth.items():
        path = os.path.join(FRAMES, fname)
        if not os.path.exists(path):
            print(f"実フレーム {fname}: ファイルがありません")
            continue
        img = np.array(Image.open(path).convert("RGB"))
        team = identify_preview_frame(img, types_map, refs, type_icons, gender_map,
                                      templates=templates, src_name=fname)
        hits = sum(1 for a, b in zip(team, want) if a == b)
        total += len(want)
        correct += hits
        print(f"実フレーム {fname}: {hits}/{len(want)} "
              f"(推定: {', '.join(x or '?' for x in team)})")
    if total:
        print(f"実フレーム合計: {correct}/{total} = {correct/total:.1%}")


def run_calibrate(quick=False):
    """関門閾値の較正: 正しいプール / 誤ったプール / 全種族での最良スコアの
    分布と、閾値ごとの単フレーム同定率 (アイコン正解・読み違い両方) を出す。"""
    dex = load_scope()
    types_new = {k: v["types"] for k, v in
                 json.load(open(os.path.join(DATA, "species_types.json"))).items()}
    refs = {k: ref_from_json(v) for k, v in
            json.load(open(os.path.join(DATA, "preview_features.json"))).items()}
    species = dex if not quick else dex[::6]
    rng = random.Random(20261121)
    rows = []  # (name, feat, types_true, types_misread)
    skipped = []
    for name in species:
        p = ensure_sprite(name, refs[name])
        if not p:
            skipped.append(name)
            continue
        img = render_frame(p, rng)
        f = features_from_rendered(img, "bilinear")
        if f is None:
            skipped.append(name)
            continue
        rng2 = random.Random(zlib.crc32(name.encode()) & 0xFFFF)
        rows.append((name, f, types_new[name], corrupt_types(types_new[name], rng2)))
    print(f"較正対象 {len(rows)} 種 (除外 {len(skipped)}: {', '.join(skipped)})")

    def pool_best(f, t_read):
        if len(t_read) == 2:
            pool = [n for n, t in types_new.items() if set(t) == set(t_read)]
        else:
            pool = [n for n, t in types_new.items() if t == t_read]
        if not pool:
            return None
        ranked = sorted((pv_score(f, refs[n]), n) for n in pool if n in refs)
        return ranked[0] if ranked else None

    dist_ok, dist_ng = [], []
    for name, f, t_ok, t_ng in rows:
        b = pool_best(f, t_ok)
        if b:
            dist_ok.append(b[0])
        b2 = pool_best(f, t_ng)
        if b2:
            dist_ng.append(b2[0])
    for label, dist in (("正しいプールの最良スコア", dist_ok), ("誤ったプールの最良スコア", dist_ng)):
        dist.sort()
        n = len(dist)
        if n:
            print(f"{label}: p10={dist[int(n*0.1)]:.3f} p50={dist[n//2]:.3f} p90={dist[int(n*0.9)]:.3f}")

    def acc(threshold, scenario):
        ok = 0
        for name, f, t_ok, t_ng in rows:
            t_read = t_ok if scenario == "correct" else t_ng
            b = pool_best(f, t_read)
            pick = b[1] if b else None
            bscore = b[0] if b else 9.0
            pool = []
            if len(t_read) == 2:
                pool = [n for n, t in types_new.items() if set(t) == set(t_read)]
            elif len(t_read) == 1:
                pool = [n for n, t in types_new.items() if t == t_read]
            if threshold is None:  # 常に全種族から最良を取る (関門なし)
                allr = sorted((pv_score(f, refs[n]), n) for n in refs)
                pick = allr[0][1] if allr else None
            elif (not pool) or bscore > threshold:
                allr = sorted((pv_score(f, refs[n]), n) for n in refs)
                if allr and (not pool or allr[0][0] < bscore - 0.03):
                    pick = allr[0][1]
            if pick == name:
                ok += 1
        return ok / len(rows) if rows else 0.0

    for scenario in ("correct", "misread"):
        for thr in (0.35, 0.25, 0.15, 0.05, None):
            label = "関門なし(全種族)" if thr is None else f"閾値 {thr:.2f}"
            print(f"  {scenario:<8} {label:<18} 単フレーム同定率 {acc(thr, scenario):.1%}")


def main():
    quick = "--quick" in sys.argv
    if "--frames-only" in sys.argv:
        run_frames()
        return
    if "--calibrate" in sys.argv:
        run_calibrate(quick=quick)
        return
    run_frames()
    run_proxy(quick=quick)


if __name__ == "__main__":
    main()
