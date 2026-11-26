# PV16-F residual seven-slot research v1.0
2026-11-26 JST. User approved F-R4 limited acceptance and requested static diagnosis, segmentation and appearance improvements, comparative experiments and preservation. Status: CONDITIONAL_RECOVERY_DEVELOPMENT_PASS; INDEPENDENT_ACCEPTANCE_BLOCKED. No Codex, paid API, new image acquisition, Mac operation, main/production changes.

## Inputs and baseline
Verified parent bundle SHA256 36cf09da11f2b335d6c1181799c751dc06039b8f038392c11d4fd49377a664ef and screenshot ZIP 570237e0ff335477eed827205a6938507295772d548a4e33ffaeec380c46c8f7. Runner verified member hashes, 293 IDs, 712 paths, 29 screens, 27 proxy groups, 328 type patches, 130 gallery examples across 44 IDs. Linux x86_64 Python 3.13.5 OpenCV 4.13.0 NumPy 2.3.5, one configured thread. Original 166/173 Top1, 167/173 Top3/5, 22/28 complete, five missing ranks, two ranking errors reproduced. Private crops inspected: thin decorative lines/background pixels merge with sprite components in width-guard failures. Not proof of general cause distribution.

## Comparison
23 configurations including baseline on the same development cohort; no independent model selection. Recovery-only arms keep all original nonempty rankings unchanged. Morphological opening 3x3 then largest component, one-pixel limited restoration intersecting original mask; existing width/area guards retained, minimum area 20, centroid and minimum bounding dimensions added. Type penalty and gallery retained; recovery-only aspect weight .05. No whole-component flood restoration. Compared 5x5 opening, row-median background/opening, opening without restoration, existing union/rowbg/close, recovery score weight changes, global mask substitution, global score reweighting and a four-rank ensemble.
| arm | Top1/173 | no rank | recovered | regressed |
|---|---:|---:|---:|---:|
| baseline |166|5|0|0|
| conditional 3x3 opening |171|0|5|0|
| conditional 5x5 |170|1|4|0|
| conditional rowopen or opening only |171|0|5|0|
| conditional rowbg |168|3|2|0|
| conditional union or close |166|5|0|0|
| global 3x3 opening |157|0|5|14|
| global union |166|5|1|1|
| global rowopen |156|0|6|16|
| global type removal |141|5|0|25|
| ensemble incl conditional fallback |171|0|6|1|
Global type half/gallery weight 1.5 retain 166; aspect zero 165, hue .7 164, high aspect .35 160. No tested global alternative improves on conditional recovery. One residual same-type error true rank 3 becomes first under union/row-background and ensemble but global variants cause regressions. Other residual has provisional label conflict with observed type pair and visible shape; the current predicted identity is plausible, ground truth needs independent verification. Keep historical label unchanged; no automatic relabeling. All details private.

## Implementation and verification
Research candidate integrated v2 uses conditional recovery only on originally empty rank. New score kind joint25-dynamic-gallery-recovery-v2 prevents old boundary reuse under existing contract matching; recovered per-slot flag included. Original nonempty rank logic unchanged. Temporal aggregation and calibration of recovery scores not validated, never confirmed. Source:
- pv16f_residual_v1.py commit da80c37d605fae8f5133725b4ce2a2d4209f1985 blob eeddf54c86ecd9938e4b2f713e69e17639241468 SHA256 b1393ead51823b392126a8b17b63ac296d81a4a073e6b2cabf00eb4c385e9192
- pv16f_integrated_v2.py commit 90720eb4dec0282c4ad2d8702f68a77dc727cd8f blob cb63e9347b82163c4aefa56c25230abe902ff407 SHA256 33d68afafb3eab9a0047c5ca06b1493be0f1607d0c1702502143d5355728d6c2
- test_pv16f_integrated_v2.py commit aa2c1ffadd6ca83338f5e5a321277435ce57b770 blob adf93c73405cffd80740e7fda724e4316597acb7 SHA256 3524b1ee339c526ed5301b3bc2b459bf119ffbbb2297773e49923167f001861d
All three GitHub readback blobs match local execution files. 21/21 contract tests PASS (old 18 + blank/thin streak, connected streak recovery, old score domain rejection), .209s. Replayed full v2: 171/173 Top1, 172/173 Top3/5, 26/28 complete; 5 recovered vs integrated v1 and 0 regressed; 11 recovered vs base v2 and 0 regressed. Type 163/164 unchanged. Two runs: private per-slot rank-index details byte identical, summary fields identical except timings. Not full score vector equality. Warmed one pass median/p95 25.15/28.87ms per screen, no controlled overhead estimate; capture/decode/scene/bank prep/UI excluded. No new Mac test.
Private evidence ZIP PV16-F-residual-research-private-evidence-v1.0.zip 25838 bytes SHA256 5b47f1d2214dd6823fb8189155a40b3656bd1f39089e0432efe176134c0ee7ef. Includes 13 files and manifest, CRC and SHA256 verified; archived in personal Library; requires parent bundle and verified screenshot ZIP. Runner SHA256 79a3288946df7405eafb11b23a12c7b07f537cf19aa4bd754ccd5d270292c996; comparison runner d16e6ba0f4ac0ad0a7a6064c66d667134646727e8e017304030506a4d29d842a; summary aedeffdacc986fd6781ffda2e8e17d11345799af1ae17e3f51435a46b05ce556; per-slot details d48a28c53727a7117d7585da8b968ba54af585bb48a8fdd82e9d58407059a34e; comparison 7d4691115f15bdf629160e8d8b469e640c7e8ca80686138ff03754af48a900ca.

## Disposition
Recommend conditional recovery v2 as next development candidate, not production. Stop post-hoc tuning same data; verify disputed label, scene/geometry, true negative/unknown cases and branch-specific rejection calibration, independent sample eligible n=0. No team constraint, no video replay, no independent generalization, no confirmed observations. Synthetic line rejection does not establish rejection of arbitrary decorations. Mac v2 replay can be batched with subsequent meaningful gate. Private screenshots/labels/rankings not posted publicly. Central ledger/dashboard synchronization remains F-R6.
