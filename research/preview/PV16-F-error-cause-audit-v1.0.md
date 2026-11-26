# PV16-F additional 24-screen error cause audit v1.0
2026-11-26 JST. Post-hoc diagnostic only; fixed ranker unchanged, no independent validation or production adoption.

## Reproduction and scope
Prior report d1388bb15b04539aeaec54ac5e39c193512b7d2d. Prior private evidence ZIP SHA256 6d69865cede11d4dadc2d26dbaf75bf249fe2611b9b5f7ec1738d2e2466f1c2e, CRC pass, four source members byte-equal to working copies. Original preview ZIP SHA256 570237e0ff335477eed827205a6938507295772d548a4e33ffaeec380c46c8f7, all 24 source JPEG hashes matched, frozen dependency hashes passed. 144 slots, 143 provisional base-species labels and 1 unlabeled; 293 registered IDs/712 paths ranked, collapse to base species, all 143 ranked IDs, scores (absolute difference <1e-12), prior base ranks reproduced. Baseline 123/143, 20 apparent errors: 15 rank 2, one each rank 3,4,5,12,22. Source provenance/group independence not verified, prior same-assistant nonblind visual labels not authoritative. Reinspection of one alleged error strongly suggests incorrect prior annotation (appearance and type consistent with prediction); keep historical labels unchanged, sensitivity if independently confirmed 124/143, excluding it 123/142. Unlabeled slot stays excluded.

## Causes (conditional on provisional labels)
13 errors with exact compatible type and same-type winner; 6 with wrong type (four Rock->Fairy, two Ice->Flying) and one disputed label. Exact type set compatible with at least one form for 132/143 slots, not exact-form type accuracy. 4/4 Ice and 4/4 Rock slots whose species label implies a unique relevant type are misclassified by the local 8x8 branch (two Ice cases still rank species correctly); additional form-ambiguous slot suggests Ice but excluded from those counts. Root mechanism: local patch bank omits Ice/Rock; nearest other class accepted with distance <=.18 and no competition from 18-type glyph branch. Actual Rock distances .153-.158; all four guarded glyph outputs Rock when separately evaluated. Actual Ice distances .120-.132; glyph top Ice in 3/4, Flying in 1/4, all four rejected by margin .025. This is not exclusively video-domain mismatch. Need joint full-18 comparison and uncertainty, not unconditional override. Correct-type oracle only for 134 unambiguous-type base labels: fixed 114/134, oracle 121/134; seven apparent errors recovered including disputed annotation, no regressions; oracle not deployable. 
13 appearance errors: largest positive weighted appearance contribution aspect 9, hash 2, hue 2. Six recurring same-species confusion cases contribute 6/20 apparent errors: query bbox width/height .65217-.77273 versus correct best reference 1.347826 and wrong best reference .660714. Largest-component extraction and asset visual-domain mismatch are hypotheses; source raw PNGs unavailable; relative distance contribution and ablation, not proof of segmentation cause. Foreground <5% in 4/20 error vs 2/123 correct, descriptive post-hoc cutoff. No true candidate absent at base level; exact form and raw template coverage unresolved.

## Controlled single-component sensitivity (old provisional 143 labels, same data)
| arm | correct | recovered | regressed |
|---|---:|---:|---:|
| fixed |123|0|0|
| appearance only |87|5|41|
| aspect zero |129|8|2|
| aspect half |124|2|1|
| density zero |123|1|1|
| hue double (.7) |126|4|1|
| hue half (.175) |120|1|4|
| hue zero |107|0|16|
| hash only plus type |109|4|18|
| type penalty half (.2) |126|3|0|
| type penalty double (.8) |123|0|0|
Aspect zero improves recurrent confusion from 1/7 to 6/7, but harms two previously correct cases. Do not select new fixed weights from this post-hoc data alone. No new features tested; original PNGs absent. 
## Preservation and next
Three JSON outputs byte-identical on rerun. Private code and detailed metrics preserved outside public repository; no raw screenshots, labels or per-slot outputs committed. No Codex, paid API, new downloads, production change or holdout access. Prior cohort remains development/exploratory. Prioritize label review; all-18 type routing with uncertainty and representative Ice/Rock patches; foreground/reference shape alignment and feature ablation; multi-frame fusion and calibration separately; fresh held-out data after freeze. Independent eligible n=0 remains unchanged. Aggregate report only; ledger/dashboard updated separately.
