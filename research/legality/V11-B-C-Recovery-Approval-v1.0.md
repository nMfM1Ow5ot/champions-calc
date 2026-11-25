# V11-B/C limited approval and recovery preservation v1.0
2026-11-26 JST. The user explicitly approved the limited V11-B/C results and requested GitHub preservation of recovered code and dashboard synchronization.

Scope: preserved research code and reported evidence, not actual game registration legality, full master acceptance, or approval to start V11-D/E. Source Showdown commit 7f7b03182d1df61c88ad360cf1d1639451b97b42. Original publication base 6cfc7dccfee1e03d19fb22b052b91f8c06c8f8d3. Previous delivery ZIP SHA-256 8bd15a07f9bdb003386f016d22f9b6480167fe4d27bb6f7f588f723c7efe12f4; recovered ZIP SHA-256 cd423deaac620648d84d9c17308464a1722ad98767e983ce9b5994a5512a47a2. Both CRC and digest checked, recovered contents compared to the original inventory. Five code files checked for common credential patterns and preserved without modification, verified by Git blob SHA and content readback.

| File | SHA-256 | New preservation commit |
|---|---|---|
| v11_additional_validator_tests_v3.mjs | 911c7762e34fe3beeab4d09dd0c80c68e52f0fb171ead710248a6aa9f06af0d3 | 2b63a7af53cbe2e23b6558a094b35b0e159fa078 |
| v11_dex_validator_runner_v3.mjs | ec590f40d4a75077e25b916bc693091241bc7b419eb63e4bc1aca71631215c44 | b902e65859c5009cdcf765dec24299293638db97 |
| v11_master_crosscheck_v3.mjs | 4776347e91f30f7b3c664caa7def17b30ca23d6bcb9f61781b1f77c94ee7d5ed | 4d1da501a928a3b88037cf339abd58a03f69ee89 |
| v11_master_regressions_v3.mjs | e4c23c0b354be509f9a60090da5bf8046533a4f633fc5c00723b70ebec95c6e8 | 9a596956a0df7d1149393930507dec54e76936b5 |
| v11_runtime_trace_v1.cjs | be1b3198f997eaf38f7af8336d08d4088c3ba0b0f1f13686498c7a2c3666e415 | 39ed1a4caaeb34734498ece1d176ad132a4ed496 |

Original v2 runner, mock tests and static audit were already tracked at the pinned base. Prior independent review: 44/44 recorded real validator outcomes matched expectations; 18/18 mock and 3/3 regression tests reported independently rerun by GPT in preceding review. No fresh Showdown execution in this preservation turn. Code-only scope: original evidence files remain in submitted archives; do not publish raw logs or full master. Original seven commits and full masters are unrecovered according to Codex; the new branch does not reconstruct their identities. No forced updates, main modification, deployment, or Codex consumption. Full master recovery/regeneration and V11-D/E remain subject to separate decision. Fractional/missing SP acceptance and form/ability normalization remain simulator observations, not game proof.
