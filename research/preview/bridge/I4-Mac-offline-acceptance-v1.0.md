# PV16-F I4 Mac offline integration acceptance v1.0
2026-11-26 JST. Status: MAC_OFFLINE_LIMITED_PASS; LIVE_SHADOW_RECOMMENDED_PENDING_AUTHORIZATION; PRODUCTION_SWITCH_NOT_APPROVED.

## Evidence
User-submitted Terminal transcript of the pinned mac_probe.sh at commit 699a5357889e03dfc35d58af00ec126e2b221935 (script blob dd4fbc86559eecbb09c25f661fdf0ecce1b5e44f). Script uses source pin 5da26d5d49cd338e25b1085645f12ec771f96645; reader blob fa8152abd137d8ccaeb32f12fac8cb65b319ff43. Transcript reports successful private archive verification and proceeds past all source hash checks. Raw private paths, username and per-slot results omitted. Evidence is user-reported execution of fixed script, not remote direct observation of Mac or independent certification.

## Acceptance
- 21/21 Python contract tests PASS, 0.207 s.
- Development regression: screens 29, slots 174, same_rank_vectors 174, top1 171, n 173, complete 26, complete_n 28, through_gate 29, gate_top1 171, gate_n 173. Equality is between direct and bridge rank kernels within Mac evaluation, not full Linux/Mac bitwise score equivalence.
- Persistent worker rank/hold/rank PASS.
- Full reader.swift compilation succeeds. One warning at 7830: nil coalescing with nonoptional megaSpecies. Base main reader 8fe118aefba0867979cbf49a14d068fc8bf37205 line 7830 retrieved and exact expression confirmed; pre-existing warning, unrelated code left unchanged.
- Offline Swift->Python probe: MAC_OFFLINE_BRIDGE_PASS: six slots, matching top-five candidates and scores, no state files. Script checks status, route, candidate-only flags, types, recovery, IDs, scores (isclose tolerance 1e-8), and absence of four named state/log/team files in isolated directory.
- COMPLETE: NO LIVE LOOP OR PRODUCTION CHANGE.
- All predeclared offline criteria met; no measured live end-to-end latency, capture or scheduler behavior, no independent holdout; no confirmed outputs or production adoption.

## Next gate
Recommend separate authorized live shadow evaluation in isolated worktree/sandbox, not default launch or main update. Before live run check capture ring, network listener, synchronization/auto-restart and global filesystem paths; avoid concurrent capture/state writers, disable or isolate shared paths/ports, preserve existing production process and assets. Measure actual new/old same-frame paired candidates, dropped frames, latency, CPU/memory, process cleanup and unchanged legacy output. Use anonymized aggregate report; retain private data locally. No new test executed or production change in this acceptance turn.