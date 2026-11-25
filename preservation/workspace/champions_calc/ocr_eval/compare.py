#!/usr/bin/env python3
"""Compare Vision (obs) vs PaddleOCR readings per paired region.
Outputs a summary printed to stdout and detail rows to compare_detail.jsonl.
"""
import json, os, re, unicodedata
from difflib import SequenceMatcher

BASE = os.path.dirname(os.path.abspath(__file__))
KEEP = re.compile(r"[0-9A-Za-zぁ-んァ-ヶ一-龥ー・%％]")

def norm(s):
    s = unicodedata.normalize("NFKC", s or "")
    return "".join(ch for ch in s if KEEP.match(ch)).lower()

def region_text(boxes):
    bs = sorted(boxes, key=lambda b: (round(b.get("y", 0), 1), b.get("x", 0)))
    return "".join(norm(b.get("s", "")) for b in bs)

def ratio(a, b):
    if not a and not b:
        return 1.0
    if not a or not b:
        return 0.0
    return SequenceMatcher(None, a, b).ratio()

def box_match(vboxes, pboxes):
    """Greedy best-match between normalized box texts; returns
    (vision boxes with a >=0.7 match, paddle boxes with a >=0.7 match)."""
    vt = [norm(b.get("s", "")) for b in vboxes]
    pt = [norm(b.get("s", "")) for b in pboxes]
    pairs = []
    for i, a in enumerate(vt):
        for j, b in enumerate(pt):
            if a and b:
                pairs.append((ratio(a, b), i, j))
    pairs.sort(reverse=True)
    used_v, used_p = set(), set()
    for r, i, j in pairs:
        if r >= 0.7 and i not in used_v and j not in used_p:
            used_v.add(i); used_p.add(j)
    return len(used_v), len(used_p), len(vt), len(pt)

SPECIES = []
def load_species():
    d = json.load(open(os.path.expanduser("~/workspace/champions_calc/data/names_ja.json")))
    for ja in d["species"].values():
        n = norm(ja)
        if len(n) >= 2:
            SPECIES.append((n, ja))
    SPECIES.sort(key=lambda t: -len(t[0]))

def find_species(text):
    for n, ja in SPECIES:
        if n in text:
            return ja
    return None

PLATES = {
    "mineA": [0.012, 0.855, 0.238, 0.972],
    "mineB": [0.218, 0.85, 0.442, 0.972],
    "oppA": [0.56, 0.025, 0.78, 0.135],
    "oppB": [0.762, 0.025, 0.988, 0.135],
}

def in_rect(b, rect):
    cx = b.get("x", 0) + b.get("w", 0) / 2
    cy = b.get("y", 0) + b.get("h", 0) / 2
    return rect[0] <= cx <= rect[2] and rect[1] <= cy <= rect[3]

def agg(rows):
    n = len(rows)
    if not n:
        return None
    both_empty = sum(1 for r in rows if not r["vtext"] and not r["ptext"])
    v_only = sum(1 for r in rows if r["vtext"] and not r["ptext"])
    p_only = sum(1 for r in rows if not r["vtext"] and r["ptext"])
    both = [r for r in rows if r["vtext"] and r["ptext"]]
    exact = sum(1 for r in both if r["vtext"] == r["ptext"])
    mean_ratio = sum(r["ratio"] for r in both) / len(both) if both else 0.0
    vm = sum(r["vm"] for r in rows); vt = sum(r["vt"] for r in rows)
    pm = sum(r["pm"] for r in rows); pt = sum(r["pt"] for r in rows)
    return {
        "n": n, "both_nonempty": len(both), "exact": exact,
        "exact_rate": round(exact / len(both), 3) if both else None,
        "mean_ratio": round(mean_ratio, 3),
        "vision_empty_paddle_text": p_only, "paddle_empty_vision_text": v_only,
        "both_empty": both_empty,
        "vision_box_recall": round(vm / vt, 3) if vt else None,
        "paddle_box_recall": round(pm / pt, 3) if pt else None,
        "vision_boxes": vt, "paddle_boxes": pt,
    }

def main():
    load_species()
    pairs = [json.loads(l) for l in open(os.path.join(BASE, "pairs.jsonl"))]
    paddle = {}
    for l in open(os.path.join(BASE, "paddle.jsonl")):
        r = json.loads(l)
        paddle[(r["image"], r["pass"])] = r
    rows_by = {}
    details = []
    lat = {}
    for p in pairs:
        pr = paddle.get((p["image"], p["pass"]))
        if pr is None:
            continue
        lat.setdefault(p["pass"], []).append(pr["elapsed_ms"])
        vtext = region_text(p["vision"])
        ptext = region_text(pr["texts"])
        vm, pm, vt, pt = box_match(p["vision"], pr["texts"])
        row = {"image": p["image"], "battle": p["battle"], "kind": p["kind"],
               "pass": p["pass"], "dt_ms": p["dt_ms"], "vtext": vtext, "ptext": ptext,
               "ratio": round(ratio(vtext, ptext), 3), "vm": vm, "pm": pm, "vt": vt, "pt": pt}
        rows_by.setdefault(p["pass"], []).append(row)
        details.append(row)
        # plates derived from the full-frame pass
        if p["pass"] == "full":
            for slot, rect in PLATES.items():
                vb = [b for b in p["vision"] if in_rect(b, rect)]
                pb = [b for b in pr["texts"] if in_rect(b, rect)]
                if not vb and not pb:
                    continue
                vsp = find_species(region_text(vb))
                psp = find_species(region_text(pb))
                srow = {"image": p["image"], "battle": p["battle"], "slot": slot,
                        "vision_species": vsp, "paddle_species": psp}
                rows_by.setdefault("plate_from_full", []).append(srow)
                details.append({"pass": "plate_from_full", **srow})
    print("=== region text agreement (Vision vs PaddleOCR) ===")
    for k in ["full", "strip", "plate:mineA", "plate:mineB", "plate:oppA", "plate:oppB"]:
        a = agg(rows_by.get(k, []))
        if a:
            print(k, json.dumps(a, ensure_ascii=False))
    sp = rows_by.get("plate_from_full", [])
    if sp:
        both = [r for r in sp if r["vision_species"] and r["paddle_species"]]
        same = sum(1 for r in both if r["vision_species"] == r["paddle_species"])
        print("=== plate species (from full-frame pass) ===")
        print(json.dumps({
            "plate_instances": len(sp),
            "both_found": len(both),
            "same_species": same,
            "vision_only": sum(1 for r in sp if r["vision_species"] and not r["paddle_species"]),
            "paddle_only": sum(1 for r in sp if r["paddle_species"] and not r["vision_species"]),
            "neither": sum(1 for r in sp if not r["vision_species"] and not r["paddle_species"]),
        }, ensure_ascii=False))
    print("=== paddle latency ms (median) ===")
    for k, v in sorted(lat.items()):
        v.sort()
        print(k, "n=", len(v), "median=", v[len(v)//2], "p90=", v[int(len(v)*0.9)])
    with open(os.path.join(BASE, "compare_detail.jsonl"), "w") as f:
        for d in details:
            f.write(json.dumps(d, ensure_ascii=False) + "\n")

if __name__ == "__main__":
    main()
