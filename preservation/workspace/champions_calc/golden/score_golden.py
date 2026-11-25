#!/usr/bin/env python3
"""ゴールデン試合の採点ツール（reader.swift 改善計画フェーズ1）。

正解ログ（truth）と reader 出力プロトコルを突き合わせ、次を数値化する。
- ヘッダー正確さ: 両軍の |poke| 行（集合一致と順序）
- 行レベル: ターン区間ごとの行集合（マルチセット）で 行種別の適合率・再現率・F1
- ターン整合: 正解の各行が、出力の同じターン区間に現れた割合（帰属の正しさ）
- 厳密順序（副指標）: 全行の完全一致率（最長共通部分列ベース）

使い方: python3 score_golden.py <truth.log> <output.log> [--json out.json]
"""
import json
import sys
from collections import Counter

CATEGORIES = [
    ("switch", ("|switch|", "|drag|")),
    ("move", ("|move|",)),
    ("damage", ("|-damage|",)),
    ("heal", ("|-heal|",)),
    ("boost", ("|-boost|",)),
    ("unboost", ("|-unboost|",)),
    ("ability", ("|-ability|",)),
    ("item", ("|-item|", "|-enditem|")),
    ("status", ("|-status|", "|-curestatus|", "|-start|", "|-end|")),
    ("faint", ("|faint|",)),
    ("weather", ("|-weather|",)),
    ("field", ("|-fieldstart|", "|-fieldend|", "|-sidestart|", "|-sideend|")),
    ("forme", ("|detailschange|", "|-mega|", "|-transform|")),
    ("effectiveness", ("|-supereffective|", "|-resisted|", "|-immune|", "|-crit|", "|-miss|", "|-fail|", "|-activate|", "|-cant|", "|-hint|", "|-blocked|")),
    ("message", ("|-message|",)),
    ("turn", ("|turn|",)),
]


def category(line: str) -> str:
    for name, prefixes in CATEGORIES:
        if any(line.startswith(p) for p in prefixes):
            return name
    return "other"


def parse(path: str):
    header = {"p1": [], "p2": []}
    segments = {0: []}  # 0 = 開幕区間（|turn| より前）
    turn = 0
    all_lines = []
    for raw in open(path, encoding="utf-8"):
        line = raw.rstrip("\n")
        if not line:
            continue
        if line.startswith("|poke|"):
            f = line.split("|")
            header[f[2]].append(f[3])
            continue
        if line.startswith("|gametype|") or line == "|start":
            continue
        if line.startswith("|turn|"):
            turn = int(line.split("|")[2])
            segments.setdefault(turn, [])
            all_lines.append(line)
            continue
        segments.setdefault(turn, []).append(line)
        all_lines.append(line)
    return header, segments, all_lines


def prf(tp: int, fp: int, fn: int):
    p = tp / (tp + fp) if tp + fp else 1.0
    r = tp / (tp + fn) if tp + fn else 1.0
    f1 = 2 * p * r / (p + r) if p + r else 0.0
    return round(p, 4), round(r, 4), round(f1, 4)


def lcs_len(a, b):
    # 厳密順序の副指標用（行数 ~150 規模なので O(n*m) で十分）
    prev = [0] * (len(b) + 1)
    for x in a:
        cur = [0] * (len(b) + 1)
        for j, y in enumerate(b, 1):
            cur[j] = prev[j - 1] + 1 if x == y else max(prev[j], cur[j - 1])
        prev = cur
    return prev[-1]


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    truth_path, out_path = args[0], args[1]
    json_path = None
    if "--json" in sys.argv:
        json_path = sys.argv[sys.argv.index("--json") + 1]

    th, tseg, tall = parse(truth_path)
    oh, oseg, oall = parse(out_path)

    report = {}
    # ヘッダー
    hdr = {}
    for side in ("p1", "p2"):
        tset, oset = Counter(th[side]), Counter(oh[side])
        inter = sum((tset & oset).values())
        hdr[side] = {
            "set_match": inter,
            "of": len(th[side]),
            "order_exact": th[side] == oh[side],
        }
    report["header"] = hdr

    # 行レベル（ターン区間ごとのマルチセット合算 = 行種別）
    cat_stats = {}
    turns = sorted(set(tseg) | set(oseg))
    total_tp = total_fp = total_fn = 0
    for name, _ in CATEGORIES + [("other", ())]:
        tp = fp = fn = 0
        for t in turns:
            tc = Counter(l for l in tseg.get(t, []) if category(l) == name)
            oc = Counter(l for l in oseg.get(t, []) if category(l) == name)
            tp += sum((tc & oc).values())
            fp += sum((oc - tc).values())
            fn += sum((tc - oc).values())
        p, r, f1 = prf(tp, fp, fn)
        cat_stats[name] = {"tp": tp, "fp": fp, "fn": fn, "precision": p, "recall": r, "f1": f1}
        total_tp += tp; total_fp += fp; total_fn += fn
    p, r, f1 = prf(total_tp, total_fp, total_fn)
    report["lines_total"] = {"tp": total_tp, "fp": total_fp, "fn": total_fn,
                             "precision": p, "recall": r, "f1": f1}
    report["lines_by_category"] = cat_stats

    # ターン整合: 正解の行が同じターン区間に現れた割合（行種別を問わない全体）
    same = diff = 0
    for t in turns:
        tc = Counter(tseg.get(t, []))
        oc = Counter(oseg.get(t, []))
        same += sum((tc & oc).values())
    truth_total = sum(len(v) for v in tseg.values())
    out_elsewhere = 0
    all_out = Counter(oall)
    for t in turns:
        for line, n in Counter(tseg.get(t, [])).items():
            found_same = min(n, Counter(oseg.get(t, [])).get(line, 0))
            found_any = min(n, all_out.get(line, 0))
            out_elsewhere += max(0, found_any - found_same)
    report["turn_consistency"] = {
        "same_turn": same,
        "wrong_turn": out_elsewhere,
        "missing": truth_total - same - out_elsewhere,
        "of": truth_total,
        "rate": round(same / truth_total, 4) if truth_total else 1.0,
    }

    # 厳密順序（副指標）
    l = lcs_len(tall, oall)
    report["strict_sequence"] = {"lcs": l, "truth_lines": len(tall), "output_lines": len(oall),
                                 "rate": round(l / len(tall), 4) if tall else 1.0}

    print(f"== ゴールデン採点: truth={truth_path} output={out_path}")
    print(f"ヘッダー: p1 {hdr['p1']['set_match']}/{hdr['p1']['of']} (順序一致 {hdr['p1']['order_exact']}), "
          f"p2 {hdr['p2']['set_match']}/{hdr['p2']['of']} (順序一致 {hdr['p2']['order_exact']})")
    lt = report["lines_total"]
    print(f"行レベル全体: 適合率 {lt['precision']:.3f} / 再現率 {lt['recall']:.3f} / F1 {lt['f1']:.3f} "
          f"(一致 {lt['tp']}, 過剰 {lt['fp']}, 欠落 {lt['fn']})")
    for name, s in cat_stats.items():
        if s["tp"] + s["fp"] + s["fn"]:
            print(f"  {name:14s} P {s['precision']:.3f} R {s['recall']:.3f} F1 {s['f1']:.3f} "
                  f"(一致 {s['tp']}, 過剰 {s['fp']}, 欠落 {s['fn']})")
    tc = report["turn_consistency"]
    print(f"ターン整合: 同一ターン {tc['same_turn']}/{tc['of']} ({tc['rate']:.3f}), 別ターン {tc['wrong_turn']}, 欠落 {tc['missing']}")
    ss = report["strict_sequence"]
    print(f"厳密順序（副指標）: LCS {ss['lcs']}/{ss['truth_lines']} ({ss['rate']:.3f})")

    if json_path:
        with open(json_path, "w", encoding="utf-8") as f:
            json.dump(report, f, ensure_ascii=False, indent=1)
        print(f"JSON を保存しました: {json_path}")


if __name__ == "__main__":
    main()
