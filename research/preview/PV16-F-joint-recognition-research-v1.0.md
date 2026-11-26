# PV16-F joint recognition research v1.0
2026-11-26 JST. LIMITED_DEVELOPMENT_IMPROVEMENT; INDEPENDENT_ACCEPTANCE_BLOCKED. No production changes.
## Design and source
Fixed previous ranker/dependencies verified against freeze.sha256; original ZIP and 24 image hashes, five working image hashes, two video source hashes and 11 decoded frame hashes and geometry checked. All previously viewed material: 5 original screens (30 exact IDs), 24 additional screens (143 provisional base-species labels, one excluded), 11 frames from two videos (66 provisional IDs). 240 attempted, 239 evaluated, 40 screens. Reproduced all previous ranks for labeled extra/video slots, baseline 214/239. No new downloads. No holdout access. Leave-one-unordered-base-roster-group-out template generation, 29 proxy groups, all 18 types present in each training fold. Groups are not proven independent. Type labels: 30 explicit slots, 46 single-type inferred, 154 dual-type ordered by previous patch/glyph distances under known type set, 10 ambiguous omitted. These are weak labels, not independently annotated icons. Historical prototype bank lineage unknown; prior 5-screen bank used to infer ordering, so indirect leakage possible. No inference of independent accuracy. 
## Methods
All 18 compete jointly after old blank guard; local 8x8 BGR minimum RMS / .18 and glyph/RGB score / .42. Joint25 = .75*local+.25*glyph; accept best score <=1, otherwise UNKNOWN. Joint50 and min compared, margin guard .12 compared. All folds contain 18 local types; no hard candidate removal. Soft species penalty unchanged .4. Dynamic aspect weight = .15*min(1,foreground_area_fraction/.10)*exp(-2*max(abs(log(alternative_aspect/baseline_aspect)))); four alternative masks: nearby connected components union (9x9 dilation neighborhood, min component area 5), wider union, row-wise median background, 3x3 close. Invalid masks revert to baseline. This is a heuristic reliability measure, not calibrated confidence. Full ranker remains rank-only, no acceptance output. 
## Results
| arm | first5 /30 | extra24 /143 | video /66 | pooled /239 | full /39 |
|---|---:|---:|---:|---:|---:|
| fixed |30|123|61|214|18|
| local18 |30|128|61|219|22|
| joint25 |30|129|61|220|22|
| joint50 |30|129|61|220|22|
| jointmin |30|129|55|214|17|
| jointguard |30|129|61|220|22|
| union |28|130|57|215|19|
| wideunion |27|124|56|207|15|
| rowbg |26|117|56|199|13|
| close |26|122|57|205|12|
| aspect zero |30|129|61|220|22|
| dynamic |30|128|61|219|21|
| joint25 aspect zero |30|135|61|226|27|
| joint25 dynamic |30|134|61|225|26|
| joint25 union |28|136|57|221|23|
| joint25 dynamic union |29|136|57|222|24|
Joint25 dynamic is conservative research candidate: 11 recovered, zero regressed against baseline; Top3 236/239, Top5 238/239; video Top5 64->66, Top1 unchanged; first detected frame 11/12 unchanged. Static aspect zero has +14/-2, marginally higher Top1; union combined improves static but harms video/first5. No selection on independent data. Extra cohort Incineroar 1/7->3/7 dynamic, 6/7 zero aspect, so shape issue remains. Valid alternative masks union 203/240, wide 211, rowbg 198, close 213. No raw reference PNG comparison; segmentation cause not established.
Type exact compatible set metric restricted to unambiguous labels: 208/230->228/230; Ice 0/10->10/10, Rock 0/10->10/10 (5 and 4 proxy groups respectively, including correlated video frames; NOT 20 independent samples). Extra 125/134->133/134, video 53/66->65/66, original30/30. Two unknown cells overall, disputed Malamar label unchanged. No new negative/unknown tests, no acceptance calibration, no source-rights resolution, no independent admissions. 
## Reproduction and preservation
Two JSON outputs byte-identical across full rerun. Code SHA256 210c57de2250fa7590171e5d65cf0ab73a7258e890835bb9365f316de20333bf; summary 2c1db5153cf76f1e67c44cc6400f5dedc6616d2e76994e9cbd3939471031cf54; private details 9f3062622f490c0687695571b912770bccaecf40e6b352ae7a61a7749e4b4e9f. Private code and results outside public repo; aggregate only. No Codex, paid API, new downloads or main change. Next: independent label verification, shape investigation with raw references, multi-frame fusion, calibration/negative tests, then freeze and genuinely fresh holdout. Do not adopt parameter candidate automatically.
