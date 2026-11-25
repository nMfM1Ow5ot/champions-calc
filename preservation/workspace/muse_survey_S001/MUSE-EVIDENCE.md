# MUSE-EVIDENCE — 報告事項と根拠

- Snapshot ID: S001
- 調査基準時点: 2026-11-24（JST）
- 行番号は調査時点で実測したローカルファイルのもの。公開リビジョン 20261124_0418 のマニフェストと主要ファイルのハッシュが一致することを確認済みのため、公開側でも同一内容である。

## E-01 ダメージ計算は既存ライブラリ @smogon/calc を使用している（A06）
- package.json: `"dependencies": { "@smogon/calc": "^0.12.0" }`（devDependencies は esbuild ^0.28.2 のみ）
- core.mjs:2-3:
  - 注記「Championsの実数値は @smogon/calc (gen9) で IV31 / Lv50 / EV = SP x 8 と置くと完全一致する (検証済み)」
  - `import { Generations, Pokemon, Move, Field, calculate, calcStat } from '@smogon/calc';`
- bundle_entry.mjs: `export * from "./core.mjs"; export * from "./estimate_engine.mjs"; export { Generations } from "@smogon/calc";`
- テスト: tests/calc_audit.mjs が UI 配線と素の @smogon/calc の突き合わせを行う。2026-11-21 に calc.pokemonshowdown.com との監査で計算コアに欠陥なし（プロジェクト記録）。

## E-02 乱数16本のダメージ配列が取得できる（A06）
- core.mjs:1223 `export function damageRolls(atkSpec, defSpec, moveName, opts = {})`
- core.mjs:1237-1251: `calculate(gen, atk, def, moveObj, field)` の `r.damage` を返し、複数ヒット技ではヒットごとの配列を要素ごとに合計して16本化する。変化技は `{ rolls: [], status: true }`、無効は `{ rolls: [0], immune: true }`、例外時は `{ rolls: [], error }`。

## E-03 複数候補の一括計算は推定エンジンで実装されている（A03）
- estimate_engine.mjs:14 `export function createEstimator(deps)`、同 :8 で core.mjs から `gen, statTable, damageRolls, withCurHP, moveData` を import。
- estimate_engine.mjs:1152: ダメージ証拠ごとに `ent.cands.map(c => damageRolls(...))` で候補全件の16本を計算し尤度評価する経路。
- 事前の混合: estimate_engine.mjs:937 `for (const c of corpus) c.post *= 0.75;`、同 :940-941 で合成側に 0.25 を配分。
- キャッシュ: estimate_engine.mjs:492 `moveStatsCache`（種族ごとの技統計）、同 :20 teamFormesCache。
- 表示用の一括計算: core.mjs:743 `export function calcMatchup(state, names)` が両方向・全技を1回で計算する。

## E-04 Python バックエンドから計算は呼ばれていない（A02）
- serve.py の subprocess 使用箇所は、sync_ui.py の実行（serve.py:33, 35 付近の run_sync）と、ログ暗号化の openssl 実行（serve.py:526 付近の _encrypt_log）のみ。core.mjs／bundle.mjs への計算呼び出しは存在しない。
- Python 側で core.mjs／bundle.mjs の名前が現れるのは、sync_ui.py の同期対象ファイル一覧と、tests/run_checks.py のゲート対象の定義のみ。
- serve.py:2226 `server = QuietHTTPServer(("127.0.0.1", 8765), handler)` — サーバは 127.0.0.1:8765 で待受ける。

## E-05 手動フラグの契約（A02／A14）
- ui.html:667 `async function pressBattleFlag()` が `{"action": "toggle"}` のみを送る。ui.html:4224 の 200ms ポーリングで state.json を取得し、battlePhase を権威としてボタンの有効化と表示を決める。
- serve.py:1711 の POST /battle_flag ルートが _apply_battle_flag へ接続される。
- reader.swift:1783 `flagPhase()` が `(logStarted && !winLogged) ? "inBattle" : "idle"` を返し、同 :1790 `applyFlagControl` が flag_control.json を消費する。

## E-06 現在無効化されている仕組みとスイッチの所在（A10）
- serve.py:875 `_AUTO_UPLOAD_ENABLED = False`（同 :1357 `_upload_logs_once_locked` の先頭で参照し、無効時は送信系をすべて止める）
- serve.py:868 `_NOTE_GATE_ENABLED = False`
- serve.py:301 `_LIMIT_TERMINAL_OUTPUT = True`
- reader.swift:28 `limitTerminalOutput = true`
- reader.swift:261 `blankStandbyEnabled = false`
- reader.swift:3447 `interruptedSaveEnabled = false`（同 :3451 の安全網の控え保存の条件に使用）

## E-07 ログ順序の修復機構（A04／A05）
- reader.swift:2574 `pullBackSwitchBlock` が遅れて確定した交代ブロックを現在の区間から引き戻し、正しいターン境界へ差し込む。
- reader.swift:2672 `emitLog` の表示経路が、ターミナルへの1回きりの印刷と、配列側の蓄積を分担する（印刷は撤回不可、蓄積は修復可能という非対称の根拠）。

## E-08 データの規模と現行シーズン（A07）
- data/regulation.json 実測: レギュレーション M-C、シーズン M-8、種族 370／持ち物 165／技 870、`specialElements: ["mega"]`。
- data/champions_dex.json 実測: 種族 1,323／持ち物 583／技 942。
- data/usage_sets.json 実測: シーズン M-8、262 セット。data/vgc_pastes.json 実測: 744 チーム。
- data/items_ja.json: 588 件。

## E-09 テストスイートの構成と直近の合否（A09）
- tests/run_all.sh の実行対象: security_check、check_moves、check_coverage、check_spec_patches、check_item_map、ui_harness、calc_audit、reader typecheck（check_reader.sh）、reader harness（~/workspace/logfix_test/）。
- tests/run_checks.py:40-46 が push ゲートで node の各スイートを呼ぶ。
- 直近の全件合否の記録: 定期ウォッチドッグ 2026-11-23 12:30 の実行で ALL PASS（プロジェクト記録）。
- 既知の失敗: tests/test_upload_resume.py の2件は従前から失敗したまま（プロジェクト記録。ゲート対象の run_all には含まれない）。

## E-10 リポジトリと index の規模（A10）
- 2026-11-24 00:00 の定期監査の実測: logs_enc/index.json = 189,156 バイト、logs_enc = 983 ファイル／385,341,796 バイト、リポジトリ全体 約400MB。増加ペースは自動送信が有効だった期間の実測で約38KB/日。
- ローカル容量の観察（同監査）: プロジェクト全体 約4.6GB、preview_eval 約2.0GB、logs_received 545MB／992 ファイル、ディスク使用率 4%。

## E-11 PaddleOCR 補助チャンネルの実測（A05／A13）
- 検証試合 battle_20261123_042534 の記録: リクエスト 187／応答 187／欠落 0／未処理 0、フレーム間隔の中央値 0.763 秒、両チャンネルで名前が読めた 16 件すべてで種族名が一致。
- 設計の根拠文書: PADDLE_DESIGN.md（状態判定に使わないことが設計として明記）。

## E-12 タイプアイコン照合の精度改善（A05）
- テンプレート照合化（reader build 20261124_0241、rev 20261124_0326）の記録: アイコン単体の精度 0.914 → 0.976、悪化したタイプなし。種族ミラー 170/186、悪化したフレームなし。

## E-13 主要ファイルの SHA-256（調査時点の実測、S001 の識別子）
| ファイル | SHA-256 |
|---|---|
| reader.swift | e7b07e6747f3200bae79ec0deb1c4dc67391e8448fcfc23ca653224daa49a7f4 |
| serve.py | 0ebc213dc21373384e7f5aa04000b0e1ef51eede1024654d2c9bc1dd88ed408b |
| ui.html | cba2b4d3ee5f625d77dfe39939e399ead4554bd2bb93d6c1b3c815567af9500f |
| core.mjs | 5d23880e356377585b94fbe0d8836636fb7cc4f1acf6b68ee012d1c38d2904da |
| estimate_engine.mjs | 51556ca9c33aeb685d83b5f1674ce0f250822202dadc565175cb3d532a612004 |
| bundle.mjs | e0d15366a1e64fce041b5dda1bfe4e61eb8031dbf66c9721ca649a895fc23971 |
| sync_ui.py | ca6807b523debbc682eac53cae6b50a1e5b6155442779776750b21e4491177bc |
| start_all.sh | 8761f84fdb2db8907de7fc1f0b494ee74243035c53abcd14b415d26892cc5a04 |
| paddle_sidecar.py | 672fbbf032652bbe385d5960a96b713d4544abc6b40f93d3c14afd378dd437bf |
| fetch_usage.mjs | c3a1bc1b6a4ff877db9866e9d15c4ae13b2b4bfdf189d2df4de1373d43bcca9e（公開版と相違。E-14） |
| tests/bayes_equiv_golden.json | f6b7f666d951dc48e35e31d030ce2b795d7d38ce51410eb73ea5df117a7981a4（公開版と相違。E-14） |

## E-14 公開マニフェストとの照合結果（A01）
- 公開 ui_manifest.json（rev 20261124_0418、調査時点で raw.githubusercontent.com から取得）との照合: 上表の fetch_usage.mjs と tests/bayes_equiv_golden.json を除く主要ファイルはすべて一致。
- fetch_usage.mjs の相違は、2026-11-24 未明に判明した持ち物日英対応表の誤り（実の取り違え 15 件・欠落 13 件）の修正がローカルにあり未 push の状態と一致する（ダメージ計算チャットの報告記録）。
- data/ の主要ファイル（pokedb_parsed.json、usage_sets.json、regulation.json、items_ja.json、preview_features.json、vgc_pastes.json）と my_team.json も公開版と一致していた。

## E-15 実行環境のバージョン（A08）
- 調査環境（Muse 側 VM）で実測: Node v24.22.1、Python 3.12.3。
- reader の型チェック用ツールチェーン: Swift 6.0.3（tests/run_all.sh の SWIFT 既定パスに明記）。
- PaddleOCR 3.7.0／PaddlePaddle 3.3.1 は PADDLE_DESIGN.md の記録による（Mac ローカル環境のため本調査では直接測定していない）。

## E-16 未確認事項の一覧
- reader.swift の実機（Mac）での実行挙動全般（Vision OCR を含む）は、この調査環境では実行できないため、記録とハーネスの結果に基づく。
- serve.py の自己修復ガードの現行実装状況（D-15）。
- 推定の証拠ごとの処理時間、メモリ使用量の体系的な測定値（A13）。
- Mac ローカルにのみ存在する物（PaddleOCR の venv・モデル、Mac 側 logs/ の現物）は、存在と役割を文書で確認したにとどまる。
