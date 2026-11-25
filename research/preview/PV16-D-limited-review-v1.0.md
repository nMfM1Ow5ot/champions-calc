# PV16-D: full-registration reference bank — limited review v1.0
2026-11-26 JST. User approved plan v0.1, D01–D09, no Codex. Disposition: STATIC_MANIFEST_AND_PILOT_PASS; FULL_BUILD_AND_INDEPENDENT_ACCEPTANCE_BLOCKED.

## Source and scope
- V11-D fixed diff and old regulation list at champions_calc c2fc17e62f9442a1cdc297596d89d6b1b9c5f585, Showdown 7f7b03182d1df61c88ad360cf1d1639451b97b42, expected v3 master SHA-256 994ce200dbeb2f7fbf1fe8e0bc54b75b3330f318daedf6e7109d87bfac95b43c. Full master ZIP exists in library but raw-byte materialization denied. Reconstructed 293 distinct IDs: 268 common + 25 Showdown-only. No direct master re-extraction or game equivalence claim.
- PokéAPI metadata commit de6760be38b60a3024f1d9054330ff265f0dc619; sprites commit c0542f7c51215d9672439012838c99f520596cbd; licence blob f08318829a5c65e870b79ddd7e03b7f51416f3d9. 452 normal + 452 shiny paths. Image copyright The Pokémon Company; repository CC0 wording does not prove third-party image reuse permission. Limited research only, no public redistribution or production adoption.
- Manifest commit 11a4d4e2d8c6cea4af67e311b7f027574f17f047, blob 57f3db7022dffcc5511e298945d2af1b3eb5c3ed. 293/293 provisional IDs with both normal/shiny paths; 356+356=712 paths, 9,656,827 bytes (directory metadata). 604 distinct Git blobs, 8,453,345 distinct bytes, 108 redundant paths. No duplicate path ownership. 96 normal and corresponding 96 shiny paths not assigned. No claim that all unassigned paths are illegal. Seven Salted-Cream normal and seven shiny paths are unassigned due to missing ID in reconstructed registration set; must reconcile raw master and game scope before final acceptance.
- Numeric pokemon_id and pokemon_forms.id are separate namespaces. Rotom-Fan 10011 vs form ID 10061 (latter is Floette-Eternal icon). Maushold default Three=10257, Four=925; checked pinned Showdown baseForme. Vivillon pattern filename and Alcremie cream/sweet filename mappings, female Pyroar and Florges/Furfrou visual variants included. Source naming/metadata mapping still requires independent semantic review. All available variants in catalog are not proof of all in-game variants.

## Static readback audit (8/8)
Registration set equality with separately rebuilt difference set; manifest blob; pinned directory path/size/blob identity for 712/712; unique paths; exactly-one owner per path; normal/shiny paired owner; byte total; both colors per candidate. Same assistant performed independent second computation; not an external auditor. No raw image checks beyond pilot.
Five identical-blob groups cross 11 registration IDs: shiny Alcremie (7 cream IDs, 49 paths in one blob); Polteageist/Antique normal and shiny (two groups); Sinistcha/Masterpiece normal and shiny (two groups). Retain all IDs; equal source bytes cannot discriminate these ID pairs via that asset alone.

## Actual connector pilot
Ten public PNG responses retrieved at pinned commit, Git blob SHA-1 recomputed on bytes and matched pinned metadata, zlib data decompressed with Adler-32 and raster filters, largest 8-connected alpha>=128 component extracted, 256-bit dHash, raw 24-bin hue counts, aspect and density computed. Seven 128x128; three initially rejected by fixed-size guard; corrected to variable dimensions and all three passed. No raw images persisted or published. No SHA-256 measured for these JS-only bytes; builder measures it when locally fetched.
| path | bytes | width x height | foreground pixels |
|---|---:|---|---:|
|687.png|15049|128x128|4649|
|shiny/687.png|14986|128x128|4649|
|10061.png|9367|128x128|1936|
|10011.png|11022|128x128|2796|
|10257.png|7640|128x128|3435|
|925.png|7636|128x128|3420|
|10248.png|17364|128x128|6944|
|666-archipelago.png|16267|128x120|7165|
|869-caramel-swirl-star-sweet.png|11021|120x120|3575|
|668-female.png|12094|95x112|4614|
This is icon ingestion feasibility, not recognition accuracy. JS decoder was an exploratory execution, Python builder has not been replayed against these actual bytes.

## Builder and execution limits
Builder v1 commit 7cf08540ebb6e622c9222eb9da119728c425e556; v1.1 commit c4b0b42eda532a9b1bfbb22415620c6bfecea0fe, blob f7503706ce99ec9444b25ad8fea5c98c630e6d83, local SHA-256 f8d29d0b59a0e76cb5080b071dbe8b2e3ccee933047404a59fcbef58a1f5d30b, readback matches local bytes. Python stdlib, local-only, pinned manifest and image blob/length checks, PNG CRC and variable dimensions, SHA-256, content-addressed cache, group acquisition by blob, 4 workers max, no publication of raw images, fail closed on missing or unsupported image. Self-test passes; independent Pillow-generated synthetic raster 5/5 exact, deterministic descriptor and cache-only SHA-256 checks pass. Pillow used only for development fixtures, no runtime dependency. All-source PNG format, JS/Python equivalence, full reproducibility and full manifest runtime not yet demonstrated. Reference extraction is versioned and not assumed identical to legacy screenshot feature extraction.
Direct container HTTPS failed DNS; web raw fetch disabled, download path denied; connector individual requests limited and no supported batch raw asset acquisition. No 604-request workaround. Full image cache/feature bank not generated, five-screen full-universe rerun not executed. Local execution is an available alternative (not yet executed), with no Codex or paid API. No GitHub Actions changes, no production, no independent holdout access.

## D01–D09 gate
D01 reconstructed provisional set only; D02 pinned source/licence review done (rights not cleared); D03 static manifest 293/293, semantic/scope reconciliation pending; D04 limited actual JS pilot 10/10 after fix; D05 full acquisition blocked; D06 builder v1.1 prepared and synthetic tests passed, full feature bank blocked; D07 static 8/8, full/independent review pending; D08 full-candidate rerun not executed; D09 code, manifest, report preserved. Main unchanged. D05-D08 resume only when raw acquisition accessible; resolve Salted-Cream and full master before formal acceptance. User corrections from PV16-C not altered; no new recording or independent acceptance data used.
