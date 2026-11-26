# OBS native Swift / Python comparison v1.0
2026-11-26 JST — LIMITED PASS, explicitly approved by user. No production adoption. Aggregate-only record; no screenshots, lineups, individual species or candidate IDs, trainer identifiers, private paths or input hashes.

## Method and evidence
User-submitted Mac terminal logs from two complete runs of isolated comparison v1.1, plus a user-submitted review montage visually checked by GPT. Two distinct existing 1920×1080 PNGs: one positive preview with six opponent slots and one negative team-list image. Both engines received the same copied bytes in each run; the script reported source Git blob checks and archive SHA256 checks PASS. Old Swift source 038267041215f0f47e76156acf32ea7d0977a9fd (main snapshot 8fe118aefba0867979cbf49a14d068fc8bf37205); only the isolated entrypoint replaced, native identifyPreview preserved. OCR keyword criterion reproduced without logging/trainer extraction. Compiled Swift 5 language mode with -O. New Python worker 71506eb4f9dde3697d782579ed8c075467d4174c, fixed reference 5da26d5d49cd338e25b1085645f12ec771f96645, OpenCV single thread, all historical development bank. Five warmed rank invocations per image/run; Swift OCR one measurement per image/run. No retraining, tuning, new capture or Codex. GPT did not execute Mac binaries or independently hash the raw Mac files; montage-to-input linkage is user-provided, not cryptographically authenticated.

## Results (species level, visual labels)
| Metric | Legacy Swift | Python v2 |
|---|---:|---:|
| Top1 | 5/6 | 5/6 |
| Top3 | 5/6 | 6/6 |
| Type-set accuracy | 5/6 | 6/6 |
| All six Top1 correct | no | no |
| Scene classification | 2/2 | 2/2 |
| Within-run output stability | 5/5 each image/run | 5/5 each image/run |

Normalize blank type marker and form names to species level; exact-form accuracy is not established. Raw string Top1 agreement 3/6, species-level agreement 4/6. One legacy miss involved type misclassification; one new miss had correct type and correct second-ranked candidate; causal explanation of appearance error untested. Outputs reproduced across both runs. Two runs are repeated measures, not additional independent images.

| Timing (ms) | Run 1 | Run 2 |
|---|---:|---:|
| Swift positive OCR (single) | 379.052 | 299.869 |
| Swift positive rank (median) | 23.719 | 22.466 |
| Swift sum (derived) | 402.771 | 322.335 |
| Python positive gate+rank (median) | 15.408 | 15.309 |
| Swift negative OCR (single) | 323.045 | 298.311 |
| Swift forced negative rank (diagnostic median) | 5.700 | 5.169 |
| Python negative gate/hold (median) | 5.257 | 5.010 |

Positive derived ratio 26.14x / 21.06x; not a direct end-to-end or live speed measurement. Negative forced Swift rank not part of normal rejected-frame flow. Excludes acquisition, decoding, initialization, IPC, state integration, and live interference. Python initialization 1.116/1.138 s. Both runs reported specified local state paths absent; not proof of OS-wide isolation. No main or production code changes in the comparison.

## Disposition
Direct native comparison and small-sample label review complete; limited PASS only. Top1 equal, Top3/type better on this image, substantially lower measured gate+rank time. No population-level superiority, calibrated confirmation, independent encounter sampling or production performance certified. Input raw bytes differ from previous GPT/Linux upload; do not combine results as identical-image evidence. Next candidates: bounded OBS disconnect/reconnect and exclusive live shadow/noninterference tests, separately authorized; do not tune on this single image. Production switch remains separately approved.