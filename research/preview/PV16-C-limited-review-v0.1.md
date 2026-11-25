# PV16-C limited review v0.1 — 2026-11-26 JST
Status: PARTIAL / DEVELOPMENT_ONLY / INDEPENDENT_ACCEPTANCE_BLOCKED.
User approved limited PV16-C; no production changes, no Codex, no paid APIs, no new recording downloads or independent holdout use.

## Rechecked evidence
- Prior qualitative report: PV16-PokeAPI-icon-pilot-v0.1.md, blob a487006927a7569e7216ff503c9658cfd02d3a85. Three species, two layouts of one recording, six development queries. Same-recording observations, some labels provisional, rights unknown, quarantine maintained.
- Public icon files retrieved via GitHub connector (62,946 B total). All four PNG signatures, IHDR 128x128, 8-bit RGBA; returned Git blob identifiers match earlier report:
  - icons/812.png 99abd84beb658aa72e2582648263aeb4d2de8d08 17550 B
  - icons/727.png 81a5991d0cc745e40b830d3c573ca318babd55ac 14504 B
  - icons/637.png 05051bb4903170e7e6f2475e1b10214596130a29 15280 B
  - icons/shiny/637.png 214fab40998711f85d108def9942558ed5e4967c 15612 B
  Source: https://github.com/PokeAPI/sprites/tree/master/sprites/pokemon/versions/generation-ix/champions/icons
  PNG headers inspected, full raster decoding and independent SHA recomputation not performed.
- Licence blob f08318829a5c65e870b79ddd7e03b7f51416f3d9: https://github.com/PokeAPI/sprites/blob/master/LICENCE.txt. Third-party image copyright expressly reserved; CC0 does not establish permission to redistribute images. Japan Copyright Act art. 30-4 non-enjoyment technical testing is a provisional basis only subject to statutory conditions. https://www.bunka.go.jp/seisaku/chosakuken/hokaisei/h30_hokaisei/ . No image files or private assets committed; no tournament use approval.

## Recovered prior conversation result (not independently reproduced)
Earlier PV16-C conversation reports 6/6 species matches in its compared conditions and a variant diagnostic: existing dictionary 6/6, ordinary-only PokéAPI 0/2 on the two shiny-target queries, normal+shiny 2/2 on those queries. Exact raw ranks, candidate universe, counts per class, metric, and source descriptors are not recovered. These aggregates cannot establish A/B/C improvement, equal-denominator variant comparison, independent accuracy, or actual shiny truth. Do not treat as current-run measurements.

## Comparison infrastructure
pv16c_compare_v1.mjs commit b2ab8896fc0d5a59b3ee0706583084f147946136 blob 170b0fab28428744a54be0ab0ce113f5863debd0. Readback exact equality. Frozen PV13 Hellinger + dHash/aspect/density score, common candidate set, equal template counts per label in A/B, C union (double count explicitly reported), worst tie rank, verified subset and recording grouping. All ten synthetic self-tests passed on identical function definitions in JavaScript execution environment; standalone Node CLI not executed. No private data read or written by the test. Type-assisted ranking, variant truth, full-team accuracy, runtime/memory on Mac and image preprocessing not evaluated. C's larger template count is a confound to analyze separately.

## Blockers and disposition
The prior PV12 image cache and PV13 private descriptor JSON are not mounted in this run. Direct raw.githubusercontent.com DNS failed. Project code file materialization was denied; existing GitHub code read instead. Seven potential independent screens remain quarantined (0 formally admitted). No new real-image A/B/C comparison or independent performance acceptance; no production adoption. Keep development pilot pending actual paired input with label evidence, rights and grouping checked; use the local CLI after compatible extraction and explicit matching candidate universe (including hard negatives); evaluate normal/shiny separately. Existing holdout isolation and all other project priorities remain unchanged.
