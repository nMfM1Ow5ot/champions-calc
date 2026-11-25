#!/usr/bin/env python3
"""OCR→ログ化 精度検証ハーネスの生成器。

実コード (reader.swift から抽出した関数群 + 実辞書) に対して、
ゲームの正規メッセージ文に実測ベースの OCR ノイズモデルを適用した
検証ケースを流し、カテゴリ別に正答率を測る。

使い方: python3 eval_gen.py <seed> <count> <out_prefix>
  -> <out_prefix>.swift と <out_prefix>_cases.json を書く
"""
import importlib.util
import json
import random
import re
import sys

BASE = "/home/hatch/workspace/champions_calc"
DATA = BASE + "/data"

spec = importlib.util.spec_from_file_location("mh", "/home/hatch/workspace/logfix_test/make_harness.py")
mh = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mh)  # harness.swift を再生成する (無害)

# resetAll を driver 文字列から波括弧マッチで抽出する
dsrc = mh.driver
i = dsrc.index("func resetAll()")
depth = 0
j = dsrc.index("{", i)
k = j
while True:
    if dsrc[k] == "{":
        depth += 1
    elif dsrc[k] == "}":
        depth -= 1
        if depth == 0:
            break
    k += 1
reset_all_src = dsrc[i:k + 1]
e_helper = 'func E(_ ja: String, _ en: String) -> SpeciesEntry { SpeciesEntry(ja: ja, en: en, id: en.lowercased(), norm: normalize(ja)) }'


def sw(s: str) -> str:
    """Swift 文字列リテラル用エスケープ"""
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


# ---------- 実辞書の読み込み ----------
names_index = json.load(open(DATA + "/names_index.json"))["species"]
champ_species = set(json.load(open(DATA + "/champions_dex.json"))["species"])
species_pool = [s for s in names_index if s["en"] in champ_species]
log_names = json.load(open(DATA + "/log_names.json"))
move_ja2en = log_names["moves"]          # JA -> EN
move_en2ja = {v: k for k, v in move_ja2en.items()}
item_ja2en = log_names["items"]
ability_ja2en = log_names["abilities"]
species_moves = json.load(open(DATA + "/species_moves.json"))
species_abilities = json.load(open(DATA + "/species_abilities.json"))

# ---------- OCR ノイズモデル (実戦ログで観測された崩れ) ----------
DAKU_STRIP = {"ガ": "カ", "ギ": "キ", "グ": "ク", "ゲ": "ケ", "ゴ": "コ",
              "ザ": "サ", "ジ": "シ", "ズ": "ス", "ゼ": "セ", "ゾ": "ソ",
              "ダ": "タ", "ヂ": "チ", "ヅ": "ツ", "デ": "テ", "ド": "ト",
              "バ": "パ", "ビ": "ピ", "ブ": "プ", "ベ": "ペ", "ボ": "ポ"}
DAKU_ADD = {"カ": "ガ", "キ": "ギ", "ク": "グ", "ケ": "ゲ", "コ": "ゴ",
            "サ": "ザ", "シ": "ジ", "ス": "ズ", "セ": "ゼ", "ソ": "ゾ",
            "タ": "ダ", "チ": "ヂ", "ツ": "ヅ", "テ": "デ", "ト": "ド",
            "ハ": "バ", "ヒ": "ビ", "フ": "ブ", "ヘ": "ベ", "ホ": "ボ"}


def kata_to_hira(s):
    return "".join(chr(ord(c) - 0x60) if "ァ" <= c <= "ヶ" else c for c in s)


def corrupt(text, rng):
    """1 回の崩れを適用。(text, kind) を返す。適用できなければ (text, 'none')"""
    ops = []
    for idx, ch in enumerate(text):
        if ch in DAKU_STRIP:
            ops.append(("daku_strip", idx))
        if ch in DAKU_ADD:
            ops.append(("daku_add", idx))
        if ch in "っッ":
            ops.append(("small_tsu", idx))
        if ch == "ー":
            ops.append(("long_vowel", idx))
    kata_idx = [idx for idx, ch in enumerate(text) if "ァ" <= ch <= "ヶ"]
    if len(kata_idx) >= 3:
        ops.append(("kana_flip", -1))
    if not ops:
        return text, "none"
    kind, idx = ops[rng.randrange(len(ops))]
    if kind == "daku_strip":
        return text[:idx] + DAKU_STRIP[text[idx]] + text[idx + 1:], kind
    if kind == "daku_add":
        return text[:idx] + DAKU_ADD[text[idx]] + text[idx + 1:], kind
    if kind == "small_tsu":
        return text[:idx] + ("つ" if text[idx] == "っ" else "ツ") + text[idx + 1:], kind
    if kind == "long_vowel":
        return text[:idx] + text[idx + 1:], kind
    if kind == "kana_flip":
        # 最長のカタカナ連続 (種族名/技名相当) をひらがな化
        runs = re.findall(r"[ァ-ヶー]{3,}", text)
        if not runs:
            return text, "none"
        w = max(runs, key=len)
        return text.replace(w, kata_to_hira(w), 1), kind
    return text, "none"


MODE = sys.argv[4] if len(sys.argv) > 4 else ""
HARD = MODE == "hard"


def apply_noise(text, rng):
    r = rng.random()
    if MODE == "vhard":
        n = 1 if r < 0.20 else (2 if r < 0.60 else 3)
    elif HARD:
        n = 0 if r < 0.10 else (1 if r < 0.50 else 2)
    else:
        n = 0 if r < 0.30 else (1 if r < 0.75 else 2)
    kinds = []
    for _ in range(n):
        text, kind = corrupt(text, rng)
        if kind != "none":
            kinds.append(kind)
    return text, kinds


# ---------- ケース生成 ----------
STATS = [("こうげき", "atk"), ("ぼうぎょ", "def"), ("とくこう", "spa"), ("とくぼう", "spd"), ("すばやさ", "spe")]
STATS_KATA = [("コウゲキ", "atk"), ("ボウギョ", "def"), ("トクコウ", "spa"), ("トクボウ", "spd"), ("スバヤサ", "spe")]
STATUS = [("どくにおかされた", "psn"), ("もうどくにおかされた", "tox"), ("やけどをおった", "brn"),
          ("まひしてしまった", "par"), ("ねむってしまった", "slp"), ("こおりついてしまった", "frz")]
CURE_WORD = {"psn": "どく", "tox": "どく", "brn": "やけど", "par": "まひ", "slp": "ねむり", "frz": "こおり"}
FIELD = [
    ("足下が不思議な感じになった！", "|-fieldstart|move: Psychic Terrain", None),
    ("足下に電気がかけめぐった！", "|-fieldstart|move: Electric Terrain", None),
    ("足下に草が生い茂った！", "|-fieldstart|move: Grassy Terrain", None),
    ("足下が霧に包まれた！", "|-fieldstart|move: Misty Terrain", None),
    ("日差しが強くなった！", "|-weather|Sunny Day", None),
    ("雨が降り始めた！", "|-weather|Rain Dance", None),
    ("砂あらしが吹き始めた！", "|-weather|Sandstorm", None),
    ("雪が降り始めた！", "|-weather|Snow", None),
    ("時空がゆがめられた！", "|-fieldstart|move: Trick Room", None),
    ("草がなくなった！", "|-fieldend|move: Grassy Terrain", "|-fieldstart|move: Grassy Terrain"),
    ("雨がやんだ！", "|-weather|none", "|-weather|Rain Dance"),
]
BERRIES = [(ja, en) for ja, en in item_ja2en.items() if ("のみ" in ja or "シード" in ja) and en.endswith(("Berry", "Seed"))]


def gen_cases(seed, count):
    rng = random.Random(seed)
    cases = []
    # カテゴリ配分
    plan = []
    weights = [("move", 24), ("boost", 20), ("status", 12), ("field", 14),
               ("item", 8), ("faint", 8), ("cure", 4), ("other", 10)]
    total_w = sum(w for _, w in weights)
    for cat, w in weights:
        plan += [cat] * max(1, round(count * w / total_w))
    rng.shuffle(plan)
    plan = plan[:count]

    for cid, cat in enumerate(plan):
        # 種族条項: 同一サイドに同ーフォルム違いは実在しない (ロトム2体等)。
        # 生成側でも同ーファミリーのペアを避ける (検証 vhard R9 で検出)
        def family(en):
            if en in ("Ho-Oh", "Porygon-Z", "Jangmo-o", "Hakamo-o", "Kommo-o"):
                return en
            return en.split("-")[0]
        while True:
            p2a, p2b = rng.sample(species_pool, 2)
            if family(p2a["en"]) != family(p2b["en"]):
                break
        # 辞書の表示名にある （ガラル）等の注記は実機の文には出ないため落とす
        strip = lambda s: re.sub(r"（[^）]*）", "", s)
        field = {"p1a": ("サーナイト", "Gardevoir"), "p1b": ("イエッサン", "Indeedee-F"),
                 "p2a": (strip(p2a["ja"]), p2a["en"]), "p2b": (strip(p2b["ja"]), p2b["en"])}
        case = {"id": cid, "cat": cat, "p2a": p2a["en"], "p2b": p2b["en"], "preset": "", "faint_slot": ""}
        if cat == "move":
            slot = rng.choice(list(field.keys()))
            ja, en = field[slot]
            moves = [mv for mv in species_moves.get(en, []) if mv in move_en2ja]
            if not moves:
                moves = list(move_en2ja.keys())
            mv_en = rng.choice(moves)
            mv_ja = move_en2ja[mv_en]
            pfx = "相手の" if slot.startswith("p2") else ""
            text = f"{pfx}{ja}の{mv_ja}！"
            case["expect"] = f"|move|{slot}: {en}|{mv_en}"
        elif cat == "boost":
            slot = rng.choice(list(field.keys()))
            ja, en = field[slot]
            stat_ja, stat_en = rng.choice(STATS + STATS_KATA)
            stage = rng.choice([("上がった", "boost", 1), ("ぐーんと上がった", "boost", 2),
                                ("下がった", "unboost", 1), ("がくっと下がった", "unboost", 2)])
            pfx = "相手の" if slot.startswith("p2") else ""
            text = f"{pfx}{ja}の{stat_ja}が{stage[0]}！"
            case["expect"] = f"|-{stage[1]}|{slot}: {en}|{stat_en}|{stage[2]}"
        elif cat == "status":
            slot = rng.choice(list(field.keys()))
            ja, en = field[slot]
            form, code = rng.choice(STATUS)
            pfx = "相手の" if slot.startswith("p2") else ""
            text = f"{pfx}{ja}は{form}！"
            case["expect"] = f"|-status|{slot}: {en}|{code}"
        elif cat == "cure":
            slot = rng.choice(list(field.keys()))
            ja, en = field[slot]
            code = rng.choice(list(CURE_WORD.keys()))
            case["preset"] = f"|-status|{slot}: {en}|{code}"
            pfx = "相手の" if slot.startswith("p2") else ""
            text = f"{pfx}{ja}の{CURE_WORD[code]}がなおった！"
            case["expect"] = f"|-curestatus|{slot}: {en}|{code}"
        elif cat == "field":
            text, expect, preset = rng.choice(FIELD)
            case["expect"] = expect
            if preset:
                case["preset"] = preset
        elif cat == "item":
            slot = rng.choice(["p2a", "p2b", "p1a", "p1b"])
            ja, en = field[slot]
            pfx = "相手の" if slot.startswith("p2") else ""
            if rng.random() < 0.7 and BERRIES:
                item_ja, item_en = rng.choice(BERRIES)
                text = f"{pfx}{ja}は{item_ja}を食べた！"
            else:
                item_ja, item_en = "だっしゅつボタン", "Eject Button"
                text = f"{pfx}{ja}は{item_ja}でもどっていく！"
            case["expect"] = f"|-item|{slot}: {en}|{item_en}"
        elif cat == "faint":
            slot = rng.choice(list(field.keys()))
            ja, en = field[slot]
            case["faint_slot"] = slot
            pfx = "相手の" if slot.startswith("p2") else ""
            text = f"{pfx}{ja}はたおれた！"
            case["expect"] = f"|faint|{slot}: {en}"
        else:  # other: 勝敗・急所・効果文 (行が出ない/勝敗行のみ)
            kind = rng.choice(["win", "forfeit", "effect", "crit"])
            if kind == "win":
                text = "Oppとの勝負に勝った！"
                case["expect"] = "|win|"
            elif kind == "forfeit":
                text = "相手は勝負をあきらめた！"
                case["expect"] = "|win|"
            elif kind == "effect":
                slot = rng.choice(["p2a", "p2b"])
                ja, en = field[slot]
                text = f"相手の{ja}に効果はバツグンだ！"
                case["expect"] = f"|-supereffective|{slot}: {en}"
            else:
                slot = rng.choice(["p2a", "p2b"])
                ja, en = field[slot]
                text = f"相手の{ja}の急所に当たった！"
                case["expect"] = f"|-crit|{slot}: {en}"
        text, kinds = apply_noise(text, rng)
        case["text"] = text
        case["noise"] = kinds
        cases.append(case)
    return cases


# ---------- Swift ドライバ ----------
DRIVER_TMPL = r'''
// ---------- eval driver ----------
__RESET_ALL__
__E_HELPER__

func evalSetup(_ c: [String: String]) {
    resetAll()
    currentTurn = 3
    teamEntries["Gardevoir"] = [:]
    teamEntries["Indeedee-F"] = [:]
    oppTeamSeen = [c["p2a"]!, c["p2b"]!]
    trainerOpp = "Opp"
    emitLog("|switch|p1a: Gardevoir|Gardevoir|100/100")
    emitLog("|switch|p1b: Indeedee-F|Indeedee-F|100/100")
    emitLog("|switch|p2a: \(c["p2a"]!)|\(c["p2a"]!)|100/100")
    emitLog("|switch|p2b: \(c["p2b"]!)|\(c["p2b"]!)|100/100")
    lastSlots["mineA"] = SlotState(speciesEn: "Gardevoir", hpPercent: 100)
    lastSlots["mineB"] = SlotState(speciesEn: "Indeedee-F", hpPercent: 100)
    lastSlots["oppA"] = SlotState(speciesEn: c["p2a"]!, hpPercent: 100)
    lastSlots["oppB"] = SlotState(speciesEn: c["p2b"]!, hpPercent: 100)
    if let pre = c["preset"], !pre.isEmpty { emitLog(pre) }
    if let fs = c["faint_slot"], !fs.isEmpty {
        let key = fs == "p1a" ? "mineA" : fs == "p1b" ? "mineB" : fs == "p2a" ? "oppA" : "oppB"
        lastSlots[key] = SlotState(speciesEn: lastSlots[key]!.speciesEn, hpPercent: 0)
    }
    battleLog = []
}

var evalFailures = 0
func evalRun(_ id: Int, _ cat: String, _ noise: String, _ c: [String: String]) {
    evalSetup(c)
    let before = battleLog.count
    // 本番の呼び出し連鎖を再現する: 実況で拾えなければ救済層へ
    if !translateBattleMessage(c["text"]!) { _ = salvageFromText(c["text"]!) }
    emitPendingFaints()
    flushHeldBoosts(forKey: "p1:Gardevoir", slot: "p1a")
    flushHeldBoosts(forKey: "p1:Indeedee-F", slot: "p1b")
    flushHeldBoosts(forKey: "p2:\(c["p2a"]!)", slot: "p2a")
    flushHeldBoosts(forKey: "p2:\(c["p2b"]!)", slot: "p2b")
    flushHeldBoostsTimeout()
    let newLines = battleLog[before...].joined(separator: " ⏎ ")
    let expect = c["expect"]!
    let pass = expect.isEmpty ? battleLog.count == before : newLines.contains(expect)
    if !pass { evalFailures += 1 }
    print("CASE|\(id)|\(cat)|\(noise)|\(pass ? "PASS" : "FAIL")|expect=\(expect)|text=\(c["text"]!)|got=\(newLines)")
}
'''


def _chunked(name, entries, is_dict):
    # 巨大な単一リテラルは Swift の型検査メモリを爆発させるため
    # (2026-11-22、辞書の成長で eval が OOM するようになった)、
    # 80 件ずつの塊に分けて代入・マージする
    chunks = [entries[i:i + 80] for i in range(0, len(entries), 80)] or [[]]
    out = [f"{name} = [{', '.join(chunks[0])}]"]
    for c in chunks[1:]:
        if is_dict:
            out.append(f"{name}.merge([{', '.join(c)}]) {{ cur, _ in cur }}")
        else:
            out.append(f"{name} += [{', '.join(c)}]")
    return out


def dict_injection():
    lines = []
    sp_entries = [
        f'SpeciesEntry(ja: {sw(s["ja"])}, en: {sw(s["en"])}, id: {sw(s["id"])}, norm: normalize({sw(s["ja"])}))'
        for s in species_pool]
    lines += _chunked("speciesDict", sp_entries, False)
    mv = [f"{sw(k)}: {sw(v)}" for k, v in move_ja2en.items()]
    lines += _chunked("moveJa2En", mv, True)
    lines.append("moveNameOrig = [:]")
    lines.append("for (ja, _) in moveJa2En { moveNameOrig[normalize(ja)] = ja }")
    it = [f"{sw(k)}: {sw(v)}" for k, v in item_ja2en.items()]
    lines += _chunked("itemJa2En", it, True)
    lines.append("itemDict = [:]")
    lines.append("for (ja, _) in itemJa2En { itemDict[normalize(ja)] = ja }")
    ab = [f"{sw(k)}: {sw(v)}" for k, v in ability_ja2en.items()]
    lines += _chunked("abilityJa2En", ab, True)
    sa = {k: v for k, v in species_abilities.items() if k in champ_species}
    sa_lit = [f"{sw(k)}: [{', '.join(sw(x) for x in v)}]" for k, v in sa.items()]
    lines += _chunked("speciesAbilityMap", sa_lit, True)
    # pvSpeciesTypes は本体の抽出関数が参照するが、宣言はハーネスの
    # テスト側にしか無いため、eval 側でも実データから注入する
    st = json.load(open(DATA + "/species_types.json"))
    lines.append("var pvSpeciesTypes: [String: [String]] = [:]")
    for name, d in st.items():
        ts = d.get("types") if isinstance(d, dict) else None
        if ts:
            lines.append(f"pvSpeciesTypes[{sw(name)}] = [{', '.join(sw(t) for t in ts)}]")
    return "\n".join(lines)


def main():
    seed = int(sys.argv[1])
    count = int(sys.argv[2])
    prefix = sys.argv[3]
    cases = gen_cases(seed, count)
    driver = DRIVER_TMPL.replace("__RESET_ALL__", reset_all_src).replace("__E_HELPER__", e_helper)
    runs = []
    for c in cases:
        d = {"p2a": c["p2a"], "p2b": c["p2b"], "text": c["text"], "expect": c["expect"],
             "preset": c["preset"], "faint_slot": c["faint_slot"]}
        lit = ", ".join(f"{sw(k)}: {sw(v)}" for k, v in d.items())
        runs.append(f'evalRun({c["id"]}, {sw(c["cat"])}, {sw(",".join(c["noise"]) or "clean")}, [{lit}])')
    driver += "\n" + "\n".join(runs) + '\nprint("EVALDONE|\\(evalFailures)")\n'
    src = mh.prelude + "\n" + mh.body + "\n" + dict_injection() + "\n" + driver
    open(prefix + ".swift", "w").write(src)
    json.dump(cases, open(prefix + "_cases.json", "w"), ensure_ascii=False, indent=1)
    print("generated", len(cases), "cases ->", prefix + ".swift")


if __name__ == "__main__":
    main()
