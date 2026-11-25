#!/usr/bin/env python3
"""Video-measurement pilot: HP-bar settle tracking + message boundary detection.

Usage: analyze_battle_video.py <video> <obs.jsonl> <protocol.log> <out.json>
Compares video-derived bar plateaus against protocol-log HP events, and
video message-boundary times against obs frame brackets.
"""
import sys, json, re, math
import cv2
import numpy as np

VIDEO, OBS, PROTO, OUT = sys.argv[1:5]

cap = cv2.VideoCapture(VIDEO)
FPS = cap.get(cv2.CAP_PROP_FPS) or 30.0
W = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH)); H = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
NFRAMES = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
print(f"video {W}x{H} fps={FPS:.2f} frames={NFRAMES}", flush=True)

def hp_mask(bgr):
    hsv = cv2.cvtColor(bgr, cv2.COLOR_BGR2HSV)
    h, s, v = hsv[:, :, 0], hsv[:, :, 1], hsv[:, :, 2]
    return ((s > 80) & (v > 80) & (h <= 95)).astype(np.uint8)

def longest_run(rowmask, minlen=40):
    best = (0, -1, -1); cur = 0; start = 0
    for i, x in enumerate(rowmask):
        if x: 
            if cur == 0: start = i
            cur += 1
            if cur > best[0]: best = (cur, start, i)
        else: cur = 0
    return best if best[0] >= minlen else None

ZONES = {  # (x0, y0, x1, y1) as fractions
    'opp':  (0.55, 0.03, 1.00, 0.30),
    'mine': (0.00, 0.80, 0.46, 1.00),
}

def detect_bars(frame):
    """Return list of (zone, y, x0, x1) bar runs found in this frame."""
    found = []
    mask = hp_mask(frame)
    for zone, (fx0, fy0, fx1, fy1) in ZONES.items():
        x0, y0, x1, y1 = int(fx0*W), int(fy0*H), int(fx1*W), int(fy1*H)
        sub = mask[y0:y1, x0:x1]
        for ry in range(sub.shape[0]):
            r = longest_run(sub[ry], minlen=50)
            if r:
                ln, sx, ex = r
                found.append((zone, y0+ry, x0+sx, x0+ex))
    return found

# ---------- bar geometry: calibrated 2026-11-22 against ground truth
# (t=107s first command phase, all four at 100%: run=76px each; cross-checked
#  at t=700s against displayed 65% / 70-202 / 42-157)
bars = [
    {'slot': 'oppL',  'y': 40,  'x0': 408, 'full': 76},
    {'slot': 'oppR',  'y': 40,  'x0': 540, 'full': 76},
    {'slot': 'mineL', 'y': 392, 'x0': 60,  'full': 76},
    {'slot': 'mineR', 'y': 392, 'x0': 192, 'full': 76},
]
print("bars:", json.dumps(bars), flush=True)

# ---------- full pass: per-frame bar fractions + message-strip diff
cap.set(cv2.CAP_PROP_POS_FRAMES, 0)
series = {b['slot']: [] for b in bars}   # fraction or nan per frame
strip_diff = []
prev_strip = None
STRIP = (slice(int(0.66*H), int(0.78*H)), slice(int(0.01*W), int(0.99*W)))
fidx = 0
while True:
    ok, fr = cap.read()
    if not ok: break
    mask = hp_mask(fr)
    runs = {}
    for b in bars:
        y, x0 = b['y'], b['x0']
        rowruns = []
        for yy in (y-1, y, y+1):
            if 0 <= yy < H:
                row = mask[yy, x0:x0+b['full']+30]
                run = 0; gap = 0
                for px in row:
                    if px: run += 1; gap = 0
                    else:
                        gap += 1
                        if gap > 2: break
                rowruns.append(run)
        runs[b['slot']] = float(np.median(rowruns))
    for b in bars:
        slot = b['slot']
        pair = {'oppL': 'oppR', 'oppR': 'oppL', 'mineL': 'mineR', 'mineR': 'mineL'}[slot]
        run = runs[slot]
        if run >= 2:
            series[slot].append(round(float(min(run / b['full'], 1.05)), 3))
        elif runs[pair] >= 10:
            series[slot].append(0.0)  # pair plate visible -> this bar is truly empty
        else:
            series[slot].append(float('nan'))
    g = cv2.cvtColor(fr[STRIP], cv2.COLOR_BGR2GRAY)
    g = cv2.resize(g, (160, 12)).astype(np.float32)
    if prev_strip is not None:
        strip_diff.append(float(np.mean(np.abs(g-prev_strip))))
    prev_strip = g
    fidx += 1
    if fidx % 3000 == 0: print(f"  frame {fidx}/{NFRAMES}", flush=True)
cap.release()
print(f"full pass done: {fidx} frames", flush=True)

# ---------- plateau (settled value) extraction per slot
def plateaus(vals, fps):
    v = np.array(vals, dtype=float)
    # median filter window 5, NaN-aware (simple: forward/backward fill for filtering only)
    idx = np.arange(len(v))
    good = ~np.isnan(v)
    if good.sum() < 30: return []
    filled = np.interp(idx, idx[good], v[good])
    med = np.array([np.median(filled[max(0, i-2):i+3]) for i in range(len(v))])
    med[~good] = np.nan
    plats = []
    i = 0
    while i < len(med):
        if np.isnan(med[i]): i += 1; continue
        j = i
        while j+1 < len(med) and not np.isnan(med[j+1]) and abs(med[j+1]-med[i]) <= 0.02:
            j += 1
        if j-i+1 >= int(0.4*fps):
            seg = med[i:j+1]
            plats.append({'t0': round(i/fps, 2), 't1': round(j/fps, 2),
                          'value': round(float(np.median(seg)), 3)})
            i = j+1
        else:
            i += 1
    # merge plateaus separated by short gaps with near-equal values
    merged = []
    for p in plats:
        if merged and p['t0']-merged[-1]['t1'] < 1.5 and abs(p['value']-merged[-1]['value']) <= 0.015:
            merged[-1]['t1'] = p['t1']
        else:
            merged.append(dict(p))
    # drop consecutive duplicates (same value as previous plateau)
    out = []
    for p in merged:
        if out and abs(p['value']-out[-1]['value']) <= 0.015: continue
        out.append(p)
    return out

slot_plateaus = {slot: plateaus(vals, FPS) for slot, vals in series.items()}
for slot, ps in slot_plateaus.items():
    print(f"slot {slot}: {len(ps)} plateaus", flush=True)

# ---------- protocol HP event sequence per position
proto_events = {}  # pos -> list of pct floats in order (incl. switch-ins)
pos_re = re.compile(r'\|(-damage|-heal|-sethp|switch|drag|replace)\|p([12])([ab]): ([^|]+)\|(\d+)/(\d+)')
for line in open(PROTO, encoding='utf-8', errors='replace'):
    m = pos_re.search(line)
    if not m: continue
    kind, side, ab, name, cur, mx = m.groups()
    pos = ('p'+side+ab)
    proto_events.setdefault(pos, []).append(round(int(cur)/int(mx)*100, 1))

def align_score(expected, observed):
    """Greedy in-order match of observed plateau values to expected HP% events."""
    matches = 0; diffs = []; ei = 0
    for ov in observed:
        found = False
        for k in range(ei, len(expected)):
            if abs(expected[k]-ov*100) <= 3.0:
                matches += 1; diffs.append(abs(expected[k]-ov*100)); ei = k+1; found = True; break
        if not found: pass
    return matches, diffs

comparison = {}
slotmap_options = [
    {'mineL': 'p1a', 'mineR': 'p1b', 'oppL': 'p2a', 'oppR': 'p2b'},
    {'mineL': 'p1b', 'mineR': 'p1a', 'oppL': 'p2b', 'oppR': 'p2a'},
]
best = None
for si, smap in enumerate(slotmap_options):
    total_m = 0; total_o = 0; all_diffs = []
    per = {}
    for slot, pos in smap.items():
        obs_vals = [p['value'] for p in slot_plateaus.get(slot, [])]
        exp = proto_events.get(pos, [])
        m, d = align_score(exp, obs_vals)
        per[slot] = {'pos': pos, 'observed': len(obs_vals), 'expected_events': len(exp),
                     'matched': m, 'mean_abs_diff_pct': round(float(np.mean(d)), 2) if d else None}
        total_m += m; total_o += len(obs_vals); all_diffs += d
    if best is None or total_m > best[0]:
        best = (total_m, si, per, all_diffs)
_, map_idx, comparison, all_diffs = best
comparison_summary = {
    'mapping': slotmap_options[map_idx],
    'total_matched': int(best[0]),
    'overall_mean_abs_diff_pct': round(float(np.mean(all_diffs)), 2) if all_diffs else None,
    'per_slot': comparison,
}
print("comparison:", json.dumps(comparison_summary, ensure_ascii=False), flush=True)

# ---------- message boundaries: video vs obs brackets
d = np.array(strip_diff)
peaks = []
for i in range(1, len(d)-1):
    if d[i] > 6 and d[i] >= d[i-1] and d[i] >= d[i+1]: peaks.append(i)
merged_peaks = []
for i in peaks:
    if merged_peaks and i-merged_peaks[-1][-1] <= int(0.4*FPS): merged_peaks[-1].append(i)
    else: merged_peaks.append([i])
video_bounds = sorted(round((max(g, key=lambda j: d[j])+1)/FPS, 2) for g in merged_peaks)

# obs: frame signatures of message-region texts + first hpbar time (anchor)
obs_frames = []  # (frame_idx, t_ms, signature)
t_anchor_obs = None
for line in open(OBS, encoding='utf-8', errors='replace'):
    try: rec = json.loads(line)
    except: continue
    if rec.get('pass') == 'hpbar' and t_anchor_obs is None:
        t_anchor_obs = rec['t']
    if rec.get('pass') != 'boxes': continue
    boxes = rec.get('boxes', [])
    msg = sorted([(round(b['y'], 2), round(b['x'], 2), b['s']) for b in boxes
                  if 0.60 <= b['y'] <= 0.85 and b['x'] < 0.78])
    obs_frames.append((rec['frame'], rec['t'], tuple(msg)))
obs_frames.sort()
# video anchor: first frame where >=3 bars are visible at once (plates appear)
t_anchor_vid = None
slots_list = list(series.keys())
for i in range(len(series[slots_list[0]])):
    nvis = sum(1 for s in slots_list if not math.isnan(series[s][i]))
    if nvis >= 3:
        t_anchor_vid = i/FPS
        break
def aligned(t_ms): return t_anchor_vid + (t_ms - t_anchor_obs)/1000.0
brackets = []
prev = None
for fr, t, sig in obs_frames:
    if prev is not None and sig != prev[2]:
        brackets.append((aligned(prev[1]), aligned(t)))
    prev = (fr, t, sig)
inside = 0; widths = []
for a, b in brackets:
    widths.append(b-a)
    if any(a-0.3 <= vb <= b+0.3 for vb in video_bounds): inside += 1
boundary_summary = {
    'video_boundaries': len(video_bounds),
    'obs_change_brackets': len(brackets),
    'brackets_with_video_boundary': inside,
    'median_bracket_width_s': round(float(np.median(widths)), 2) if widths else None,
    'video_anchor_s': round(t_anchor_vid, 2) if t_anchor_vid is not None else None,
}
print("boundaries:", json.dumps(boundary_summary), flush=True)

json.dump({'bars': bars, 'plateaus': slot_plateaus, 'comparison': comparison_summary,
           'boundaries': boundary_summary, 'video_bounds': video_bounds},
          open(OUT, 'w'), ensure_ascii=False, indent=1)
print("wrote", OUT, flush=True)
