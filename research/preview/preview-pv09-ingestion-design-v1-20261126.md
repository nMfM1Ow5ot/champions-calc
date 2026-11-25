# PV-09 — Reference dictionary ingestion and quality management v1.0
Date: 2026-11-26. Research only, no production changes.
## Disposition
Descriptor audit completed, metadata gate synthetic test 11/11. Raw ingestion, rights and independently approved roster remain blocked. Metadata gate checks declarations, not their truth or image bytes. Standalone Node wrappers not independently executed.
## Sources
Frozen data commit f43460ad3d93ac4591a8e1e8bb924b6050c7f5a4. PV-08 commit 51e7d60f142ab7875dd691507e4be9a85bd3c97e. Audit report 31f7ce47ed7fea35337cbc362e90a8bedfe096d7. Metadata gate 837ca325ed9ed99146edc0339412987787800e88.
Prior research: https://pmc.ncbi.nlm.nih.gov/articles/PMC8321059/ (CIFAR near-duplicate leakage); https://proceedings.neurips.cc/paper_files/paper/2024/file/a7ce9b6a4db012cdaac28dd48989a17d-Paper-Datasets_and_Benchmarks_Track.pdf (SELF-CLEAN: candidate duplicate and label-error discovery). Transfer only review principles, not published performance or thresholds.
## Proposed pipeline
1. Inventory permitted existing local game frames and reference assets. Do not upload raw frames, names, or third-party images. Keep original read-only, compute real SHA-256 and locally opaque source/battle IDs. Rights unknown -> quarantine.
2. Establish approved preview roster separate from battle forms and an explicit visual-equivalence mapping. Do not infer eligibility from suffix. Keep unresolved forms as UNKNOWN or candidate set.
3. Extract each crop with pinned extractor/version, geometry and source digest; verify bounds, raw and crop digest against bytes, image decode, quality, and independent label evidence (observed battle identity or independently checked annotation; never classifier self-label). Conflicting evidence -> quarantine. The present gate implements only metadata shape and grouping checks.
4. Freeze split at source/battle/duplicate-component level BEFORE selecting thresholds. Identical crop bytes under different labels -> review, not auto-delete. Near descriptors -> review; do not assume duplicates or collapse legitimate forms. Transitive connected components across actual duplicate/origin links must not span partitions; near-duplicate candidates adjudicated before split.
5. Select references by distinct sources and appearance diversity. Proposed pilot target >=3 independently verified distinct battles per candidate (not sufficient acceptance evidence). Allocate priority using observed frequency if available, reference deficit, and PV08 confusions. No fabricated usage prior. Prefer rare unrepresented labels for coverage floors, then hard negatives; retain domain and form variation. No new paid APIs.
6. Rebuild immutable versioned research bank from accepted reference partition only; keep dev and held-out assets outside. Record manifest, extractor digest, roster version, input digests, gate result and rollback pointer. Never auto-publish to production. Use candidate sets where descriptors non-identifiable.
7. Evaluate on independent held-out battles, including unknowns, auto type/no type, top-k, macro recall, selective risk/coverage and 6-slot accuracy. Predeclare acceptance criteria separately. Production approval and user authorization required before replacement.
## Metadata gate fixture results
{
  "valid": true,
  "unverified_label": true,
  "unresolved_rights": true,
  "missing_battle": true,
  "bad_crop": true,
  "unknown_label": true,
  "same_battle_leak": true,
  "same_crop_conflict": true,
  "duplicate_id": true,
  "malformed_digest": true,
  "null_record": true
}
## Unresolved
Existing generator build_frame_templates.py referenced by reader.swift but exact repository root path returned 404 at frozen commit; actual location/local code unavailable. No raw file acquisition, no new templates, no legality proof, no full byte-verifying ingestion or split assignment implementation. Gate detects direct split collisions in provided source/battle/digests; it cannot discover unknown duplicate or battle links. Legacy records lack required provenance and must remain legacy/unverified, not be destructively discarded. No automatic label fixes. All changes confined to research/preview.
