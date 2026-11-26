# PV16-F-R4 preflight review v1.0
2026-11-26 JST. User approved F-R1–F-R3 limited outcomes and GPT-side contract tests, asset verification and Mac preparation. Status: LINUX_CONTRACT_PASS; HISTORICAL_STILL_REPLAY_COMPLETE; MAC_REPLAY_READY; INDEPENDENT_ACCEPTANCE_BLOCKED. No Codex, paid API, new imagery acquisition, main or production changes.

## Contract verification
Recovered the five exact files from GitHub connector and reconstructed local copies because container DNS could not resolve raw.githubusercontent.com. All five Git blob hashes matched commit 02828ae53fae327e88ec88655be7a7e4d85729fd:
- joint v2 573be1ef1e422c285c680906ed56413dc649cee5
- coverage v2 be0ff17d08ca8b52dace5fb004da210e9fd41ee2
- temporal v1 aa40601d4c0ac6475bebbe3383beabf18a50cf40
- integrated v1 6870548ff34a62ebdd37627fab9269d9b7f09997
- test suite 8bdbb427d81076d270258ab90ee0c60068140684
Python 3.13.5, OpenCV 4.13.0, NumPy 2.3.5, x86_64. Executed original 18 unittest methods: 18/18 PASS, 0.213 s. No Mac runtime test yet.

## Asset verification
Recovered existing private evidence via Library, not publicized. Reference features SHA256 2a47f9fbe141a752ca4b3292f530e48b3be3563c25685c6ef4404b17c76b9b3a; full evidence ZIP 69d16d949b3052ce8a841e90c61a21b0936cb27283a305f4aa2e9f567039c897; source screenshot ZIP 570237e0ff335477eed827205a6938507295772d548a4e33ffaeec380c46c8f7; type mapping 32928471a9b80a03e4ec1beadcab3394813660d22e9210a9aa4d34ac94718ffc; legacy type prototype JSON efeae3ba2cd69461fe90d18492bd8962219dae1817861890c7358b816c79981b; historical joint details 9f3062622f490c0687695571b912770bccaecf40e6b352ae7a61a7749e4b4e9f. All matched earlier pinned evidence. Verified 29 source entry hashes and first five exact working JPEG hashes. CRC checks for relevant evidence. Type map covers exact 293 IDs; prototypes shape 18x147; 712 reference paths. No videos recovered or requested. Historical review bundle indicates 604 raw icons verified by user-side pilot, not independently reverified here. No verified species-clause group mapping; no reuse of provisional base mapping as legality constraint.

## Development replay
29 previously examined stills, 174 attempts, 173 historically labeled slots (30 exact registration IDs, 143 provisional base species), 27 proxy groups. First five exact working JPEGs, additional 24 resized INTER_AREA to 823x540. Historical labels incl weak type order; no independent annotations. Rebuild group-excluded banks from stills only: 328 type patches, 130 valid gallery descriptors across 44 IDs, all 27 folds cover all 18 types. Same group excluded from both banks; historical glyph provenance not independent. Current integrated v1 uses different HOG scale, normalization margin and occupancy interpolation than private original research; not an exact replay of prior 232/239. No threshold fitting, no team constraint, no video fusion performance test. One duplicate-frame invariance assertion using actual ranked frame; no actual temporal improvement claim. All accepted=false and no-boundary proposals held.
| Arm | Top1 | Top3 | Top5 | Full rosters | No rank | Median/p95 ms per six slots |
|---|---:|---:|---:|---:|---:|---:|
| joint25 dynamic v2 |160/173|167/173|167/173|18/28|5|23.38/29.20|
| integrated v1 |166/173|167/173|167/173|22/28|5|27.58/39.41|
6 recovered, 0 regressed. first5 30/30 both; extra24 130/143 vs 136/143. Type compatible exact set 163/164; not independent type accuracy. Timing x86_64, OpenCV reported one thread; one warmed pass, excludes capture/decode/scene/bank prep/UI. Old final fallback guard-only counterfactual: 174/174 nonempty, corrected 169/174, all five rejected due to excessive width, all five historically labeled. Do not equate nonempty features with accuracy. Keep guard; improve segmentation separately.

## Mac handoff
Created private portable ZIP, 17 members, 550874 bytes, SHA256 36cf09da11f2b335d6c1181799c751dc06039b8f038392c11d4fd49377a664ef. Existing verified screenshot ZIP is external; only five small historical working JPEGs included. Private ZIP stored in Library, not public GitHub. All members checked against manifest and ZIP CRC. Runner SHA256 1aff8a39270a71a9d8ffbc4e4cdddab2854fcd28e5236c275a31b84ce8081685; executed on Linux. Mac uses existing Python 3.9.6 venv, no installations, one new temp directory; verify whole ZIP before extraction, source ZIP before reading, run synthetic suite then development replay. Share aggregate stdout only. F-R4 Mac runtime not done. F-R5 independent eligible n=0; no production approval. F-R6 central ledger/dashboard sync deferred.