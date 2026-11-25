#!/bin/bash
# champions_calc 全チェック一括実行。
# 使い方: bash tests/run_all.sh
# どれか1つでも失敗したら exit 1。push ゲートと定期ウォッチドッグから使う。
set -u
cd "$(dirname "$0")/.."
ROOT=$(pwd)
SWIFT=${SWIFT:-$HOME/swift-toolchain/swift-6.0.3-RELEASE-ubuntu24.04/usr/bin/swift}
FAILED=()

run() {
  local name="$1"; shift
  echo "=== $name ==="
  if "$@"; then echo "--- $name: OK"; else echo "--- $name: FAILED"; FAILED+=("$name"); fi
  echo
}

run "security_check" python3 security_check.py
run "check_moves (usage panels)" node tests/check_moves.mjs
run "check_coverage (data/UI/reader name coverage)" node tests/check_coverage.mjs
run "check_spec_patches (spec diff data validity)" node tests/check_spec_patches.mjs
run "check_item_map (item JA-EN mapping)" node tests/check_item_map.mjs
run "ui_harness (state.json scenarios)" node tests/ui_harness.mjs
run "calc_audit (UI wiring vs raw @smogon/calc)" node tests/calc_audit.mjs
run "test_multihit_dist (MH-001 multi-hit distribution)" node tests/test_multihit_dist.mjs
run "test_multihit_gate (MH-001-R1 multi-hit estimation gate)" node tests/test_multihit_gate.mjs
run "test_dist_unavailable (MH-001-R1 dist availability)" node tests/test_dist_unavailable.mjs
run "test_fault_injection (MH-001-R1 fault injection)" node tests/test_fault_injection.mjs
run "test_r1d_replay (MH-001-R1 replay; old engine in /tmp/r1d_old)" node tests/test_r1d_replay.mjs
run "test_candranges_display (candidate ranges display)" node tests/test_candranges_display.mjs
run "test_hh_consumption (MH-001-R1-F1 Helping Hand consumption)" node tests/test_hh_consumption.mjs
run "test_r1f_verification (MH-001-R1-F verification)" node tests/test_r1f_verification.mjs
run "test_r1g1_fixes (MH-001-R1-G1 fixes)" node tests/test_r1g1_fixes.mjs
run "test_hh_residual_risks (MH-001-R1 Helping Hand residual risks)" node tests/test_hh_residual_risks.mjs
run "reader typecheck" bash check_reader.sh
if [ -x "$SWIFT" ]; then
  ( cd ~/workspace/logfix_test && python3 make_harness.py >/dev/null && "$SWIFT" harness.swift 2>&1 | grep -q "^ALL PASS$" )
  if [ $? -eq 0 ]; then echo "--- reader harness: OK"; else echo "--- reader harness: FAILED"; FAILED+=("reader harness"); fi
else
  echo "--- reader harness: SKIPPED (swift not found)"
fi

echo "===================="
if [ ${#FAILED[@]} -eq 0 ]; then
  echo "ALL CHECKS PASS"
  exit 0
else
  echo "FAILED: ${FAILED[*]}"
  exit 1
fi
