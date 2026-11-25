# OCR replay v6 — validation record (2026-11-26)

## Operating principles
Respect user resources; maximize time efficiency; prioritize static work and investigation; minimize user effort and download frequency; avoid excessive plan subdivision; adapt plans to progress; prioritize pilots; make proportionate compromises; minimize external dependencies; version meaningful changes; avoid duplicate filenames.

## Scope and provenance
Isolated research code, not production reader changes. Script commit ce2f9e8ee2be453ef67474d574c582ef67535374; Git blob cfbbc955bb4ff537b5a475c36251809f2c07e901. Local source SHA-256 576d75e5b1802d4004ff1ad895446ade42fe4da0b0da8c1660e9ee887a151865. Replayed user-provided v5 diagnostic report (3 verified source images, 4 saved OCR results). No private recordings, raw OCR transcripts or player identifiers published. Existing reader.swift reviewed at blob 038267041215f0f47e76156acf32ea7d0977a9fd. Name dictionaries reviewed at repository commit f43460ad3d93ac4591a8e1e8bb924b6050c7f5a4.

## Results
- Python syntax check passed. 17/17 synthetic checks passed.
- Three image SHA-256 checks passed against the supplied report.
- Four saved OCR outputs replayed; zero new OCR calls, installations, video downloads, user-side runs.
- Geometric row grouping restored the intended word order in both full-frame and direct-crop results of the same two-line message. Separate ruby box removed in both.
- Command menu identified on the one observed command frame; other full-frame examples remain UNKNOWN. No state or event emission.
- Slash substitution generated a single format-valid HP candidate matching the visually inspected HP display. This is a candidate, not validated game state.
- Existing species/move dictionaries offer plausible near matches for observed errors; one trainer-accessory term had no suitable item dictionary match. No automatic dictionary correction implemented.

## Decision
Retain Apple Vision as provisional OCR baseline; use saved evidence for static parser development; preserve original text and uncertainty. Do not repeat the video scan or install additional engines now. Before any production use, investigate distinct held-out battle samples, menu and HP geometry, mixed/embedded ruby, and contextual ambiguity. If additional OCR evidence is needed, batch the smallest useful independent sample in one run rather than sequential micro-pilots.

## Limits
Purposively selected samples from one recording; no independent accuracy, recall, or throughput measurement. Coordinate thresholds fitted to prior examples, not general iPad calibration. Ruby heuristic cannot remove readings embedded in a single box. HP candidates can be spurious outside a confirmed HP region. Dictionary distances do not prove correctness. Existing production code untouched.
