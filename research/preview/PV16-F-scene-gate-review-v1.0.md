# PV16-F scene and coordinate gate research v1.0
2026-11-26 JST. Resumed after user Mac restart. LIMITED_LAYOUT_DEVELOPMENT; SCENE_AUTHENTICATION_BLOCKED. No Codex, paid API, new images, Mac execution, main or production change.
## Inheritance
Verified existing parent bundle SHA256 36cf09da11f2b335d6c1181799c751dc06039b8f038392c11d4fd49377a664ef, residual evidence 5b47f1d2214dd6823fb8189155a40b3656bd1f39089e0432efe176134c0ee7ef, original screenshot archive 570237e0ff335477eed827205a6938507295772d548a4e33ffaeec380c46c8f7, integrated v2 source 33d68afafb3eab9a0047c5ca06b1493be0f1607d0c1702502143d5355728d6c2. No new ranker accuracy test; prior 171/173 remains a historical development result.
## Method
29 known layout positives plus two previously excluded actual images, one nested in another UI and one battle move-selection screen. Confirmed visually. No untouched holdout access. First five exact historical working JPEGs and other 26 canonical resize; also tested all 31 original raw images via adapter. Candidate gate: aspect tolerance .005, uint8 BGR, minimum 823x540; fixed geometry normalized via INTER_AREA; left/right chromatic occupancy, strong horizontal boundaries at six expected rows and vertical edges at left panel sides and opponent panel start. Thresholds selected on inspected development examples, not predeclared test. Compare aspect-only, color-only and full. This is coordinate compatibility, NOT automatic viewport localization or semantic scene authentication. No 16:9 video support; no arbitrary offset correction. All results accepted=false. Do not feed layout_candidate directly as authenticated geometry_verified.
## Results
Linux OpenCV 4.13.0 NumPy 2.3.5, requested one thread. Full original 29/29 positive and 2/2 rejected, both canonical and raw-image replay. Color-only matches original counts; aspect-only admits both negatives.
| synthetic challenge | n | full admits | color-only admits |
|---|---:|---:|---:|
| translation >=5 pixels (8 prescribed offsets per positive) |232|0|171|
| mirrored |29|0|0|
| right row occlusion |29|0|0|
| left panel occlusion |29|0|0|
| wrong aspect |29|0|0|
| blank/white/random noise |3|0|0|
| right sprite black rectangle, anchors preserved |29|29|29|
| center black rectangle, anchors preserved |29|29|29|
| 1px translations (tolerance probe) |116|84|116|
| 2x upscale then normalize |29|28|29|
Full gate rejects 351/409 synthetic challenge instances designated invalid, but 58 of 409 pass; all 58 deliberately preserve structural anchors. Not a population false positive estimate. One upscale and 32 of 116 one-pixel translations conservatively held. No automatic realignment. Canonical gate median .632365ms, p95 .8976584ms (29 observations; no capture or raw decode; not Mac). Positive and negative labels refer to compatibility, not all possible game scenes. No real negative sample beyond two images; no independent acceptance (n=0). 
## Preservation
pv16f_scene_gate_v1.py commit 40873ff7a470ebc534311cc5fd0db43a8dd8f998 blob 66788a1dcf08eab0346adb6ffb6303850e95d15a SHA256 b316491b9ac9c60ca7aeb3c474ed149eb2fc2f7cd81a757c1d441f01b7ad4e05; exact local hash and connector readback match. Private evidence archive PV16-F-scene-gate-private-evidence-v1.0.zip 4608 bytes SHA256 510f21c4154f0497cc4aa89831b68c45b26bea8bea099c4e7f7ae2c574d536f7, 6 members, CRC and internal manifest verified, personal Library. No raw images, labels, private lineups posted. Evaluator uses existing private plan and source archive; workspace paths require adaptation on another host.
## Next
Compare existing PV01 video viewport detection with this fixed-layout gate; add semantic scene and per-slot visibility checks with actual negative examples before integration. Prioritize candidate-layout vs authenticated observation separation, then freeze negative/positive protocol and independent labels. Do not infer real detection rates or tune arbitrary synthetic rectangles alone. No extra Mac trial now. F-R6 ledger/dashboard sync remains pending.
