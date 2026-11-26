# PV16-F selective coverage optimization research v1.0
2026-11-26 JST. LIMITED_DEVELOPMENT_RESULT; independent acceptance BLOCKED. IMRaD; GPT basic principles v1.10.

## Introduction
Increase the coverage of selective recognition while avoiding wrong proposed confirmations. Background: Geifman & El-Yaniv, Selective Classification for Deep Neural Networks (2017), https://proceedings.neurips.cc/paper/2017/hash/4a8423d5e91fda00bb7e46540e2b0cf1-Abstract.html ; Sun et al., Out-of-Distribution Detection with Deep Nearest Neighbors (2022), https://proceedings.mlr.press/v162/sun22d.html . Adapt the ideas of rejection and distance-based confidence, not their trained models or statistical guarantees.

## Methods
Verified previous private ZIP SHA256 23764fa626b4232779026435be5a9ff6948e4403e1dd090830e757bd3ffe4fb2, CRC, rank member SHA256 5a47eb5d3431e17f57da925169abd82af8c0e2344f8fa43b44a30899fe70360c and prior summary SHA256 90a04b76cc47bf40dcb7052490bdb904c3990e57586ae497e6c44c6d17006c0a. No image replay in this experiment; reuse stored 293-ID distances, 239 evaluable slots, 29 proxy roster groups, 96 exact labels and 143 provisional base labels. Verify correct flags and previous threshold counts. Recreate 239 simulated absent-catalog negatives by deleting all true-base IDs (or exact truth ID for exact labels); not genuine unseen images.
Six lower-is-safer features: d1, d1-d2, d1/d2, d1/d5, d1/d10, d1/median. Unique first place required. For each fixed feature subset, reject any x dominated by a known error b (b_i<=x_i for all i). The complement of the upward closure of B is the maximum downward-closed region avoiding B: any downward-closed region containing x>=b also contains b. The implemented rule additionally rejects empty boundary and ties. Keep only minimal bad points. Evaluate 12 feature subsets with two negative-set definitions (known errors only vs known errors plus proxy negatives), 29 leave-one-proxy-group-out refits with paired negatives held out. After observing proxy errors, compare 20 post-hoc cushion configurations (four subsets times five absolute cushions .005/.01/.02/.03/.05), shifting every bad coordinate downward. No calibrated probabilities. All 44 configurations are exploratory; comparison is not independent.

## Results
Same 239 known slots and 239 proxy negatives. Full-fit known/unknown and group-held-out counts:
| Rule | Known accepts | Known wrong | Proxy wrong | Group held-out known accepts | Group known wrong | Group proxy wrong |
|---|---:|---:|---:|---:|---:|---:|
| Forced first (counterfactual) |239|14|239|239|14|239|
| Prior distance .5 |114|0|3|114|0|3|
| Prior joint .5/.025 |113|0|2|113|0|2|
| Exact distance boundary, known only |159|0|11|160|1|12|
| 3-feature known-only |190|0|45|193|3|47|
| 2-feature distance/ratio5, known+proxy |123|0|0|123|0|1|
| 3-feature d1/negative margin/ratio5, known+proxy |129|0|0|129|0|2|
| Distance, known+proxy cushion .005 |87|0|0|87|0|0|
| 3-feature known+proxy cushion .03 |85|0|0|88|0|0|

Prior fixed rule columns use the same fixed thresholds on all groups (not a refit); previous grid selection on known-only yielded identical known counts. 129/239=53.97% vs 113/239=47.28%, +16 slots/+6.69 percentage points; known-only 190/239=79.50% is NOT a safe improvement (3 held-out errors and 47 proxy errors). Three-feature candidate full-fit first5 13/30, extra24 79/143, video37/66; exact labels50/96. Stronger constraint zero across both cohorts and all held-out predictions: highest full-fit coverage among tested rules 87/239=36.40% (distance .005 cushion), highest held-out coverage 88/239=36.82% (3-feature .03 cushion, full fit85). No configuration simultaneously exceeds previous joint coverage and achieves zero held-out proxy errors. Baseline and counts reproduced; summary and stdout byte-identical across two runs. Synthetic checks of boundaries, ties, invalid scores, missing context and catalog, duplicates and deterministic boundary ordering passed; accepted always false.

## Discussion
No global optimum over arbitrary classifiers claimed. The maximum property holds for a fixed monotone feature subset and observed negatives; adding dimensions can overfit. Unknown proxy negatives are derived from the same images and not a realistic scene/unknown test. Proxy groups do not establish statistical independence and all research decisions reuse the development cohort. 129-slot candidate for further exploration, not a deployed acceptance rule; 87-slot conservative reference. Formal independent sample n=0. Need actual negatives, improved recognition/feature quality, fixed catalog/identity, exact labels, predeclared frozen rule and independent risk/coverage test. No threshold or risk target approved. No Codex, new downloads, paid API, main or production changes.

## Preservation
Private reproducibility package contains source ZIP/member hash requirements, module, evaluator, summary and two stdout logs. Module SHA256 713e26b621f870e5b0d765fd6b8a6edcdeb6dcf7bd4f4e5ab61bf7c3ece799d5; evaluator SHA256 48da86b9e30142af9ba0ad336ba8502caf6f1dc953db0f6db96935cce40b4358; summary SHA256 8ba5a1964513e907c8ac09405a8e97a148e5368febcefa661787fe2704c24866. No private labels or learned boundary values in this public aggregate report. Research code staging is a separate proposed action.
