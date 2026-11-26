# OBS virtual camera stop/restart pilot — acceptance v1.0
2026-11-26 JST. LIMITED PASS, explicitly confirmed by user with corrected operation order. Aggregate-only; no private frames, image hashes, candidate IDs, lineup, trainer names or local paths.

## Evidence and method
User-submitted Mac terminal output of the camera-only diagnostic launcher at commit e14897f9c76b585b27c71f2c50d9797701564b80, blob da56615934ee1846b28053aa04a3eacd36e6490f. Reported script and component integrity, plist, Swift build and signature verification passed. One baseline/stop/restart cycle, same diagnostic process, original capture methods retained; read-only diagnostic extension. Scene evaluation is the full-layout/visibility candidate gate, not species ranking or authenticated scene detection. GPT reviewed the submitted aggregate, not raw frames or an independent Mac rerun.

## Results
| Phase | Baseline | Stopped | Restarted |
|---|---:|---:|---:|
| Successful PNG captures / attempts | 3/3 | 14/14 | 20/20 |
| Layout+visibility candidates | 3/3 | 0/14 | 13/20 |
| Distinct decoded pixel hashes | 3 | 1 | 6 |
| Callback sequence advance | 75 | 685 | 1017 |
| Session generation start/end | 0/1 | 1/1 | 1/1 |
| Capture errors | 0 | 0 | 0 |

All 37 captures reported advancing consumed sequence and valid decode; fresh-consumption contract true, shutdown true, specified local state paths absent, completed true, process exit 0. Restarted visible candidate pixels differed from baseline. Stop phase produced repeated identical decoded pixels but new callbacks; content was not independently visually identified. Candidate gate rejected all 14 stopped-phase images. The session generation remained 1 during stop/restart: no session reconfiguration demonstrated. Result NON_GAME_OUTPUT_AND_LAYOUT_RECOVERY_CANDIDATE; accepted=false, scene_authenticated=false. Continuity Camera deprecation warning did not prevent observed capture.

## Timing correction (user clarification)
User explicitly clarified that Enter was pressed BEFORE restarting OBS Virtual Camera, and the camera was enabled late by mistake. The recorded restarted-phase first capture 60.543 ms and first visible candidate 6154.248 ms are relative to Enter/phase start, not to the actual OBS restart. The latter includes operator delay; the former may predate restart. Actual restart-to-first-frame and restart-to-first-valid-content latency are NOT MEASURED. Do not attribute 6.154 s to OBS, AVFoundation or recognition performance; do not subtract an estimated operator delay. Baseline first capture 329.748 ms includes initial phase start/initialization and is not a live end-to-end metric. No retest required for this limited recovery-possibility decision.

## Scope and disposition
Limited PASS for the observed single user-controlled stop/restart with layout-candidate recovery in the same process and stopped-image rejection. Transport callback liveness, content variation and scene validity are distinct. The existing >4 s callback staleness reconfiguration condition was not exercised; no claim of recovery from physical disconnect, complete callback loss, OBS process crash, repeated cycles, stale game pixels, or live production noninterference. Raw images and detailed per-frame evidence remain local. No Codex, new production change or production reader startup in this pilot. Next candidate: isolated live shadow evaluation, including load, delay, drops, shutdown and noninterference; separate authorization. Production adoption requires separate approval. No automatic threshold change or new experiment authorized by this acceptance.