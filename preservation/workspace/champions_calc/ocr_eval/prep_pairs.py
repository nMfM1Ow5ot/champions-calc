#!/usr/bin/env python3
"""Pair each debug image (in battles that have obs.jsonl) with the Vision OCR
readings nearest in time, per pass/region. Output: pairs.jsonl with one record
per (image, pass): {battle, image, at_ms, pass, region, dt_ms, vision:[{s,x,y,w,h,c}]}.
Coordinates in obs are region-relative; region is [x0,y0,x1,y1] in frame fractions.
"""
import json, glob, os, sys
from datetime import datetime

LOGS = os.path.expanduser("~/workspace/champions_calc/logs_received")
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "pairs.jsonl")

PASSES = [
    ("boxes", [0, 0, 1, 1]),          # full frame
    ("boxes", [0, 0.66, 1, 1]),       # message strip
    ("plate:mineA", [0.012, 0.855, 0.238, 0.972]),
    ("plate:mineB", [0.218, 0.85, 0.442, 0.972]),
    ("plate:oppA", [0.56, 0.025, 0.78, 0.135]),
    ("plate:oppB", [0.762, 0.025, 0.988, 0.135]),
]
MAX_DT_MS = 1500

def main():
    out = []
    battles = sorted({os.path.basename(p).split("_obs")[0].replace("battle_", "")
                      for p in glob.glob(os.path.join(LOGS, "battle_*_obs.jsonl"))})
    for b in battles:
        obs_path = os.path.join(LOGS, f"battle_{b}_obs.jsonl")
        by_pass = {}
        with open(obs_path) as f:
            for line in f:
                try:
                    r = json.loads(line)
                except Exception:
                    continue
                key = (r.get("pass"), json.dumps(r.get("region")))
                by_pass.setdefault(key, []).append(r)
        for key in by_pass:
            by_pass[key].sort(key=lambda r: r.get("t", 0))
        for img_path in sorted(glob.glob(os.path.join(LOGS, f"battle_{b}_debug*.jpg"))):
            meta_path = img_path[:-4] + ".json"
            if not os.path.exists(meta_path):
                continue
            with open(meta_path) as f:
                meta = json.load(f)
            at = datetime.fromisoformat(meta["at"]).timestamp() * 1000
            for pname, region in PASSES:
                entries = by_pass.get((pname, json.dumps(region)), [])
                if not entries:
                    continue
                best = min(entries, key=lambda r: abs(r.get("t", 0) - at))
                dt = abs(best.get("t", 0) - at)
                if dt > MAX_DT_MS:
                    continue
                out.append({
                    "battle": b,
                    "image": os.path.basename(img_path),
                    "kind": meta.get("kind"),
                    "at_ms": int(at),
                    "pass": pname if pname != "boxes" else ("full" if region == [0, 0, 1, 1] else "strip"),
                    "region": region,
                    "dt_ms": int(dt),
                    "vision": best.get("boxes", []),
                })
    with open(OUT, "w") as f:
        for r in out:
            f.write(json.dumps(r, ensure_ascii=False) + "\n")
    import collections
    c = collections.Counter(r["pass"] for r in out)
    imgs = len({r["image"] for r in out})
    print(f"pairs={len(out)} images={imgs} by_pass={dict(c)}")
    dts = sorted(r["dt_ms"] for r in out)
    if dts:
        print(f"dt_ms median={dts[len(dts)//2]} p90={dts[int(len(dts)*0.9)]} max={dts[-1]}")

if __name__ == "__main__":
    main()
