# PV16-E residual recognition study v1.0
2026-11-26 JST. Limited development study; no independent acceptance, no production adoption.

## Existing type samples
Fixed source data/type_icons.json at 59edac6d38caf3c9aa209aa5f43c350fd2c77294, blob c4ca6c06022f70e6bbf9edc168e7f86b0d6b06a0. 322 distinct RGB/glyph feature pairs, 18 classes, all lengths/ranges valid. Original images, source battles, labeling and independence not established. Same-sample exclusion removes identical feature pairs, not whole battles. RGB/glyph correlation score .7*(1-r)/2+.3*RGB distance/441.7. Maximum distance .42, guarded margin .025.
| arm | all correct | wrong | unknown | Ice correct/wrong/unknown (8) | Rock correct/wrong/unknown (6) |
|---|---:|---:|---:|---|---|
| fixed prototypes |302|20|0|7/1/0|6/0/0|
| leave-one-feature-out |316|6|0|7/1/0|6/0/0|
| leave-one-feature-out + guard |309|2|11|7/0/1|6/0/0|
All 322 sample grayscale-grid std >30; Ice min 35.56485, Rock min 49.53591. Ice mean prototype std 26.74750. Sample-level experiment is a feature-space diagnostic, not full image pipeline nor independent real-image validation.

## Blank gate
Five already used screens, identical working image hashes. Actual 6 blanks std 3.28694–6.47660, 54 occupied cells std 40.98008–78.01268. Old gate std<=30 confounds low contrast and absence. Proposed blank only on left cell, std<=10 AND nearest blank patch distance<=.18; right cell cannot be a legitimate empty cell on an admitted selection row. If patch rejects or suggests NONE without evidence, classify with guarded glyph fallback without variance blank rule. None of this establishes scene detection. Actual known development 60/60 cells, 6/6 blanks, 54/54 occupied, 30/30 pairs. No actual Ice/Rock screen. Prototype synthetic identity 17/18 old vs 18/18 new (glyph branch without blank evidence); half and quarter contrast 18/18 new, old 5/18 and 0/18, zero contrast 16 correct/2 unknown, not evidence of real image accuracy or unknown rejection. Uniform gray unknown example and four logical gate checks pass. Gate threshold informed by known screens, not calibrated.

## Same-type appearance
Reused all 293 candidate scores on 30 slots, new type predictions, existing .4 soft penalty, no new features. Baseline 29/30; halve existing hue weight .7->.35 yields 30/30, five complete teams, MRR 1, no regression on 29 known correct slots. Same-type diagnostic conditioned on true type set: 29->30; eternal Floette goes rank 5->1. Hash only 24/30, no hue 25/30, hue double 28/30, mean unique templates 29/30, low-foreground hue half also 30/30. Leave-one-screen-out selection between baseline and alternative weights (ties prefer baseline) returns 29/30, not 30: on held-out screen with prior error training screens favor baseline by tie. Consequently fixed half weight is candidate research setting, not validated generalization. No new descriptors, no new raw images, no complete legality constraint or independent holdout. Two JSON outputs byte-identical on rerun. No Codex, paid API, main change or production adoption.
Remaining: original Ice/Rock screen evidence; provenance of historical bank; negative and scene tests; independent calibration and frozen evaluation; provisional master/form mapping and rights. Private per-slot evidence kept outside public repo.
