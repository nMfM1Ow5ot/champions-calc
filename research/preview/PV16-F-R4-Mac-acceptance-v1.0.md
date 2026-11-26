# PV16-F-R4 Mac limited acceptance v1.0
2026-11-26 JST. Status: MAC_CONTRACT_PASS; HISTORICAL_STILL_AGGREGATE_REPRODUCTION_PASS; INDEPENDENT_ACCEPTANCE_BLOCKED.
Evidence: user-provided Terminal stdout; no direct Mac access or independent inspection of local result files. Preflight: commit 7f13791fb3617a456c44cfbab333a5b022b20bc8, research/preview/PV16-F-R4-preflight-review-v1.0.md. User log reports both bundle and screenshot archive verified by pinned SHA256 before extraction. Earlier pilot output is separate and not pooled. No new experiment, Codex, production change, or private data publication in this review.

## Results
Mac arm64, Python 3.9.6, OpenCV 4.11.0, NumPy 1.26.4. 18/18 contract tests PASS in 0.249s. 29 previously examined stills, 174 attempts, 173 labeled slots, 27 proxy groups, 328 type patches, 130 supplemental gallery examples across 44 IDs, all 27 folds cover all 18 types. Same development scope as Linux.
| Metric | Base | Integrated |
|---|---:|---:|
| Top1 |160/173|166/173|
| Top3 |167/173|167/173|
| Top5 |167/173|167/173|
| No rank |5|5|
| Complete rosters |18/28|22/28|
| First5 Top1 |30/30|30/30|
| Extra24 Top1 |130/143|136/143|
| Mac median ms/screen |11.482417|13.771708|
| Mac p95 ms/screen |12.652175|14.186767|
All recognition aggregate counts match Linux preflight, including 6 recovered and 0 regressed, type compatible exact set 163/164. This is aggregate reproduction, not byte-exact per-slot equivalence. Integrated Top1 95.95%, full rosters 78.57%, +3.47 percentage points Top1. Seven labeled slots not correct, five of these no rank and two incorrect top-ranked among 168 ranked. Conditional top1 166/168 (98.81%) is descriptive, not acceptance risk. No rank must not be treated as incorrect confirmed observation.

## Performance and scope
One warmed pass; 29 screens. Integrated median 13.77ms, p95 14.19ms; excludes capture, decode, bank construction and UI. OpenCV reports 10 threads on Mac vs 1 on Linux; cannot infer controlled hardware speedup or actual thread utilization. Gallery overhead median difference 2.289291ms (~19.94%). No end-to-end latency guarantee.
No video, team legality constraint (verified map unavailable), calibration, confirmed observations, independent sample (n=0). Labels include provisional base species and weak type labels; no independent generalization or real unknown evidence. F-R4 limited acceptance only; no production integration.

## Next gate
Prioritize five width-guard rejections using existing development stills, compare foreground alternatives with paired controls and retain conservative rejection for uncertain inputs. Analyze two residual ranked errors; review verified species-group mapping separately. Do not relax guard solely to improve coverage; verify new genuine negative cases, scene/geometry and frozen calibration before F-R5. Stop repeated speed-only experiments unless meaningful new pipeline cost appears. Central ledger/dashboard sync deferred to F-R6; aggregate report only on research branch. No change to main or private repositories.
