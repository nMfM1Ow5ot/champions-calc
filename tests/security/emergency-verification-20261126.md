# Emergency v0.2 verification — 2026-11-26

Status: PARTIAL PASS; deployment not approved by this test.

Target serve.py blob: 4ed10cf3a628a5fb64a5ec8f351a9d6abae18b30
Target commit: 3aee97608777a5f1020289ea58d296ac21b7f7e9
Harness commit: b7f939763b9fc9c672c655b00523fcb138f46aba

Method: GitHub connector retrieved handler source. Direct raw GitHub download in isolated Linux runtime failed DNS resolution. Handler methods were transcribed from retrieved source into a temporary fixture; AST extraction and actual loopback HTTP requests used dummy files and ephemeral port. No full repository checkout or full application startup. No live credentials or external API calls.

Actual output: unittest Ran 1 test in 0.541s; OK. 23 HTTP subcases:
- 200: ui.html, state.json, my_team.json, presets.json, data/a.json, normal/index.html, normal/ (body equality checked)
- 404: github_log_token.txt, team_key.txt, .git/config, .env, .env.local, a.pem, a.key, a.p12, a.pfx, alias, hardalias, outside, badindex/, %74eam_key.txt, data/../team_key.txt
- 403: empty/

Reproduce from isolated checkout: python3 tests/security/test_emergency_http_20261126.py serve.py
This invocation against the full file is not yet executed. Earlier reported 26-case results lack independently available execution evidence and are not relied upon here.

Not tested: full application, POST routes, GitHub synchronization, encryption/decryption, macOS behavior, concurrent file replacement, HEAD, full research regression. No changes to main or live Mac. Source inspection confirms automatic synchronization and self-restart behavior, so do not merge while experiments run. Denylist is incomplete by design. S-01 remains open.
