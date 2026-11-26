# PV16-E: critical review and exploratory development evaluation v1.0
2026-11-26 JST. User approved E01-E09, no Codex. Disposition: LIMITED_DEVELOPMENT_PASS; TYPE_INTEGRATION_PRIORITY; NEW_FEATURES_AND_INDEPENDENT_ACCEPTANCE_PENDING.

## Critical review (same assistant, not an external auditor)
Plan v0.1 is conditionally sound for development only. Five known screens are insufficient for population inference; selection and evaluation on the same data cause optimism; compare fixed settings and leave-one-screen-out (LOSO) selection as sensitivity analysis, not independent performance. Separate true-type oracle from image-derived type evidence. Do not hard-exclude on uncertain type. Separate individual rankings from team assignment and allow abstention. Asset-level image count can bias minimum-distance scoring; compare unique-blob mean as a sensitivity arm, not an unbiased correction. Exact image formats and scope remain provisional. New HOG/HSV/spatial/direct matching require raw cache on Mac, not provided here; defer full extra-feature extraction unless marginal need demonstrated. References: Cawley & Talbot 2010 https://www.jmlr.org/beta/papers/v11/cawley10a.html ; OpenCV mask template matching https://docs.opencv.org/4.x/de/da9/tutorial_template_matching.html . No claim of efficacy transfer from literature.

## Inputs and reproduction
PV16-D review 24b450e303feb59dabeb5e08c3688da2ede9700b; submitted ZIP SHA-256 69d16d949b3052ce8a841e90c61a21b0936cb27283a305f4aa2e9f567039c897. Five exact previously used working images; no additional screenshot accessed, no holdout. Baseline program re-executed, all 30 ID rankings reproduced by new decomposition. 293 IDs, 712 paths, fixed distance formula. Python 3.13.5, OpenCV 4.13.0, NumPy 2.3.5, SciPy 1.17.0. Repeated experiment: all aggregate results excluding elapsed time and detailed score file exactly reproduced. Runtime about 0.3 s for exploratory script on container (not Mac/device latency; excludes baseline run and I/O outside script).
Type lookup: fixed champions_calc species_types.json, blob bfeba203f6cd0d891d56ae60a5ec4f761209cb6b; 268 direct ID entries + 25 inherited aliases (Aegislash shield, Alcremie cosmetic, Vivillon cosmetic). Type sets cover 293/293, not direct game/master certification.
Species clause: pinned Showdown 7f7b03182d1df61c88ad360cf1d1639451b97b42 config/formats.ts M-C uses Flat Rules, data/rulesets.ts Flat Rules includes Species Clause; checks species.num. Assignment used PokeAPI species_id proxy and explicit same-species cosmetic mappings from fixed manifest; 231 groups, not full TeamValidator or item constraints.

## Results (development data only)
| Arm | Top1 /30 | Top3 /30 | Top5 /30 | Top10 /30 | complete /5 | MRR |
|---|---:|---:|---:|---:|---:|---:|
| baseline |17|19|21|21|1|0.624332|
| widened global bg threshold 60 |17|19|20|21|0|0.620446|
| widened global bg threshold 90 |19|21|22|24|1|0.695017|
| widened row bg threshold 45 |9|13|15|15|0|0.388833|
| widened row bg threshold 60 |16|16|18|18|0|0.562043|
| LOSO preprocessing selection (other 4 screens) |14|18|19|21|0|0.558548|
| hash only |11|13|14|17|0|0.433528|
| hue only |1|7|9|15|0|0.184342|
| geometry only |2|5|5|10|0|0.152001|
| no hash |5|13|16|19|0|0.335614|
| no hue |13|16|17|22|0|0.517115|
| no geometry |16|18|19|21|1|0.578825|
| hue half weight |16|20|21|25|0|0.630304|
| hue double weight |10|19|19|20|0|0.488699|
| mean unique templates |14|19|21|23|0|0.580984|
| true-type oracle + baseline |29|29|30|30|4|0.973333|
| true-type oracle + LOSO preprocessing |27|29|29|30|2|0.933333|
| observed type + baseline |28|29|30|30|3|0.956667|
| observed type + LOSO preprocessing |27|28|28|29|2|0.917568|

Diagnostics: among 13 baseline errors, weighted hue component contributes the largest positive difference between the best true and best predicted asset in 11, hash in 2. Foreground occupies <5% crop in 4/13 errors and 0/17 correct cases (post-hoc descriptive cutoff; not proof of cause). Wider global90 recovers 2 net slots but LOSO choice loses 3 vs baseline, so no general preprocessing gain demonstrated. Unique-blob mean loses 3 Top1; does not isolate causal template-count effect. New feature representations not tested; old PV13 vs PokéAPI vs union controlled comparison also not run.

Image-derived type experiment: two fixed 15x15 icon patches per slot, downsampled to 8x8 RGB; nearest template trained only on other four screens, ordered type labels and NONE for absent left icon; fixed distance threshold .18 rejects UNKNOWN. 16/18 types observed in whole development sample, 27/30 exact type pairs, 3 slots partially/fully unknown (each missing type absent in its training fold). Soft mismatch cost .4*(count known types missing from candidate + indicator full recognized set differs); no hard exclusion. Actual observed-type baseline 28/30, 17 prior correct retained, 11/13 errors recovered; remaining two are one missing type exemplar and one same-type appearance ambiguity. Oracle 29/30 is conditional reference, not universal upper bound. Icon training templates and parameters developed on known sample, possible correlated screens, no independent claim. Type oracle rank only among type-compatible IDs (excluded scores infinite).
Species-group assignment: min score over IDs within species group then minimum-cost six-slot matching. Forced matching unchanged Top1 (17/30 baseline, 28/30 observed-type); optional 0.9 abstention cost yields 27 correct, 1 abstention, 2 wrong for observed type. No calibration, no production threshold. Joint Top-k/MRR not evaluated; individual ranks remain distinct. Synthetic 2x2 assignment test passed and uniqueness checked on all forced teams. Same-image ambiguity groups retained, not resolved by type or grouping.

## E01-E09
E01 baseline reproduction complete; E02 descriptive component/mask diagnostics complete but causes not fully proven; E03 four preprocessing comparisons + LOSO sensitivity complete; E04 legacy feature ablations complete, HOG/HSV/spatial/ORB/direct new descriptors deferred (raw cache absent); E05 limited weight and template aggregation sensitivity complete; E06 oracle and real image type comparisons complete (limited 16 types, three rejects); E07 provisional species-clause assignment and abstention experiment complete, full legality not tested; E08 development aggregate and repeatability complete; E09 public aggregate report and private evidence preservation, ledger synchronization separately. No production adoption, no new recording, no paid API, no Codex, no main change. Do not use holdout for tuning. Next: all-18-type reference/icon recognition with independent calibration, retain baseline appearance metric; investigate same-type cases and resolve mapping/rights; only then pre-register PV16-F held-out validation. Raw PNGs not present, no blanket full-feature comparison claim.
