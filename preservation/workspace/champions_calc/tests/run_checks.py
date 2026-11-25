#!/usr/bin/env python3
# push ゲート: push 対象ファイルに応じて必要な機能チェックだけを実行する。
# 使い方: python3 tests/run_checks.py [push対象ファイル ...]
# 失敗があれば exit 1 (push_update.py はその時点で push を中止する)。
import os
import subprocess
import sys

BASE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SWIFT = os.path.expanduser(
    "~/swift-toolchain/swift-6.0.3-RELEASE-ubuntu24.04/usr/bin/swift")
HARNESS_DIR = os.path.expanduser("~/workspace/logfix_test")

READER_FILES = {"reader.swift"}
UI_FILES = {"ui.html", "core.mjs", "bundle.mjs", "my_team.json"}
# 推定系テスト (MH-001-R1) を要するファイル: 推定エンジン本体、それを
# 読み込む計算・UI 側 (bundle は estimate_engine を含む)、テスト自体
ESTIMATE_FILES = {"estimate_engine.mjs", "core.mjs", "bundle.mjs",
                  "ui.html", "tests/test_multihit_gate.mjs",
                  "tests/test_dist_unavailable.mjs",
                  "tests/test_fault_injection.mjs",
                  "tests/test_r1d_replay.mjs",
                  "tests/test_candranges_display.mjs",
                  "tests/test_hh_consumption.mjs",
                  "tests/test_r1f_verification.mjs",
                  "tests/test_r1g1_fixes.mjs",
                  "tests/test_hh_residual_risks.mjs"}
# 推定・計算が読み込むデータファイル (estimate_engine.mjs / core.mjs /
# ui.html が参照するもの)。これらの変更でも推定系テストを実行する。
# 同期対象 (sync_ui.MANIFEST) に含まれるものだけを挙げる。認識側の
# preview_features / type_icons や、生成側だけが使う base_stats 等は
# 推定に影響しないため含めない
ESTIMATE_DATA_FILES = {
    "data/champions_dex.json", "data/items_ja.json",
    "data/meta_sets.json", "data/names_index.json",
    "data/names_ja.json", "data/pokedb_parsed.json",
    "data/regulation.json", "data/spec_patches.json",
    "data/species_abilities.json", "data/species_moves.json",
    "data/usage_sets.json", "data/vgc_pastes.json",
    "data/vgcpastes_sets.json",
}
ESTIMATE_TESTS = [
    ("test_multihit_gate", "tests/test_multihit_gate.mjs"),
    ("test_dist_unavailable", "tests/test_dist_unavailable.mjs"),
    ("test_fault_injection", "tests/test_fault_injection.mjs"),
    ("test_r1d_replay", "tests/test_r1d_replay.mjs"),
    ("test_candranges_display", "tests/test_candranges_display.mjs"),
    ("test_hh_consumption", "tests/test_hh_consumption.mjs"),
    ("test_r1f_verification", "tests/test_r1f_verification.mjs"),
    ("test_r1g1_fixes", "tests/test_r1g1_fixes.mjs"),
    ("test_hh_residual_risks", "tests/test_hh_residual_risks.mjs"),
]


def run(name, cmd, cwd=BASE):
    print(f"=== gate: {name} ===", flush=True)
    r = subprocess.run(cmd, cwd=cwd)
    print(f"--- gate: {name}: {'OK' if r.returncode == 0 else 'FAILED'}", flush=True)
    return r.returncode == 0


def main():
    files = sys.argv[1:]
    need_reader = False
    need_ui = False
    need_estimate = False
    for f in files:
        if f in ESTIMATE_FILES or f in ESTIMATE_DATA_FILES:
            need_estimate = True
        if f in READER_FILES or f.startswith("check/"):
            need_reader = True
        elif f in UI_FILES or f.startswith("data/") or f.startswith("fetch_"):
            need_ui = True
        elif f.endswith((".sh", ".py", ".md", ".txt", ".json")) and "/" not in f:
            pass  # スクリプト/文書のみの変更はセキュリティ確認だけでよい
        else:
            need_reader = need_ui = True  # 想定外のファイルは全チェック
    ok = True
    if "data/spec_patches.json" in files or "data/regulation.json" in files:
        ok = run("check_spec_patches", ["node", "tests/check_spec_patches.mjs"]) and ok
    if need_ui:
        ok = run("check_moves", ["node", "tests/check_moves.mjs"]) and ok
        ok = run("check_coverage", ["node", "tests/check_coverage.mjs"]) and ok
        ok = run("check_item_map", ["node", "tests/check_item_map.mjs"]) and ok
        ok = run("test_move_spec", ["node", "tests/test_move_spec.mjs"]) and ok
        ok = run("test_multihit_dist", ["node", "tests/test_multihit_dist.mjs"]) and ok
        ok = run("ui_harness", ["node", "tests/ui_harness.mjs"]) and ok
    if need_estimate:
        for name, path in ESTIMATE_TESTS:
            ok = run(name, ["node", path]) and ok
    if need_reader:
        ok = run("reader typecheck", ["bash", "check_reader.sh"]) and ok
        if os.path.exists(SWIFT) and os.path.isdir(HARNESS_DIR):
            gen = subprocess.run(["python3", "make_harness.py"],
                                 cwd=HARNESS_DIR, capture_output=True)
            if gen.returncode != 0:
                print("--- gate: reader harness: FAILED (generation)")
                ok = False
            else:
                r = subprocess.run([SWIFT, "harness.swift"], cwd=HARNESS_DIR,
                                   capture_output=True, text=True)
                lines = (r.stderr or "").splitlines()
                passed = any(line == "ALL PASS" for line in lines)
                print(f"--- gate: reader harness: {'OK' if passed else 'FAILED'}")
                if not passed:
                    ok = False
                    for line in (r.stderr or "").splitlines():
                        if line.startswith("FAIL"):
                            print("   " + line)
        else:
            print("--- gate: reader harness: SKIPPED (no swift toolchain)")
    if not need_reader and not need_ui:
        print("gate: 対象ファイルに機能チェックは不要です")
    print("gate:", "ALL PASS" if ok else "FAILED")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
