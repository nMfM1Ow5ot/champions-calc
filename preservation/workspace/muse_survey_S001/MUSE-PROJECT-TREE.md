# MUSE-PROJECT-TREE — ディレクトリ構成と主要ファイルの役割

- Snapshot ID: S001
- 調査基準時点: 2026-11-24（JST）。公開リビジョン 20261124_0418 との照合済み（詳細は MUSE-SNAPSHOT.md）
- 対象: `~/workspace/champions_calc/`（公開リポジトリ `nMfM1Ow5ot/champions-calc` の同期対象を含むプロジェクトフォルダ）

## 1. ディレクトリツリー（主要部分のみ、生成物・キャッシュは注記）

```
champions_calc/
├─ reader.swift            画面取得・認識・ログ構築・state.json 書き出し（Mac 上で実行）
├─ serve.py                ローカルサーバ (127.0.0.1:8765)・同期・ログアップロード
├─ ui.html                 ダメージ計算 UI（ブラウザで実行）
├─ core.mjs                計算コア（@smogon/calc のラッパ＋Champions 適合）
├─ estimate_engine.mjs     型推定エンジン（ブラウザ上で UI から利用）
├─ bundle.mjs              esbuild 生成物（core.mjs＋estimate_engine.mjs＋@smogon/calc の束）
├─ bundle_entry.mjs        バンドルの入口定義
├─ sync_ui.py              リポジトリから同期対象ファイルを取得してローカルへ反映
├─ push_update.py          公開リポジトリへの push（セキュリティ確認＋機能ゲート付き）
├─ security_check.py       push 前の秘密情報・個人情報スキャン
├─ edit_lock.py            複数チャット間の同時編集を防ぐ claim/release 管理（ローカル専用）
├─ build_zip.py            配布用 ZIP の作成
├─ start_all.sh            Mac 側の統合起動（同期→サーバ→reader）
├─ start_ui.sh             UI サーバのみの起動
├─ run_reader.sh           reader の起動
├─ preview_test.sh         見せ合いテストの撮影・送信セッション用
├─ update_data.sh          データ再生成の補助
├─ paddle_sidecar.py       PaddleOCR 補助チャンネル（Mac ローカルの Python サイドカー）
├─ check_reader.sh         reader.swift の型チェック（Linux Swift＋Apple API スタブ）
├─ check/                  型チェック用の Apple API スタブ
├─ data/                   ゲームデータ一式（下記 3.）
├─ tests/                  テスト・ハーネス一式（下記 4.）
├─ golden/                 reader 改善計画の黄金試合・採点素材
├─ calibration/            認識キャリブレーション素材
├─ logs/                   Mac 側の試合ログ置き場（試合ごとのフォルダ。実行時生成物）
├─ logs_received/          Muse 側で受信・復号した試合ログ（実行時生成物、約545MB）
├─ preview_eval/           見せ合い評価の作業領域（約2.0GB、実行時生成物）
├─ ocr_eval/               OCR 評価用 venv 等（実行時生成物）
├─ node_modules/           npm 依存（@smogon/calc、esbuild）
├─ package.json            依存定義（@smogon/calc ^0.12.0、esbuild ^0.28.2）
├─ my_team.json            登録自チーム（正本はオンライン側。平文はローカルのみ）
├─ my_team.enc             暗号化された登録チーム（リポジトリに置かれる形）
├─ team_key.txt            ログ・チーム暗号化の鍵（ローカル／ZIP のみ。値は本資料に記載しない）
├─ state.json              reader が書く現在の対戦状態（実行時生成物）
├─ flag_control.json       手動フラグの制御ファイル（実行時生成物、同期対象外）
├─ presets.json            プリセットストアの共有先（リポジトリ直下に置かれる）
├─ 各種 *_DESIGN.md / *_PLAN.md / *_MANUAL.md   設計・計画・手順の文書（下記 5.）
└─ champions_calc_*.zip    過去の配布 ZIP（複数）
```

## 2. 主要ファイルの役割と規模（行数は調査時点の実測）

| ファイル | 行数 | 役割 |
|---|---|---|
| reader.swift | 12,558 | iPad 画面（QuickTime ミラーリング）の取得、Vision OCR、プレート／メッセージ解析、Showdown 形式ログ（プロトコル＋人間可読）の構築、state.json の書き出し、PaddleOCR サイドカーの監督、手動フラグの取り込み |
| serve.py | 2,237 | HTTP サーバ（UI 配信、state.json 配信、POST /battle_flag・/calclog・/presets 等）、GitHub 同期、試合ログの暗号化アップロード（現在は無効化中）、プリセット共有 |
| ui.html | 4,428 | ダメージ計算 UI 本体。state.json を 200ms 周期でポーリングして盤面へ反映。プリセット、推定結果の表示、試合開始／終了ボタン |
| core.mjs | 1,292 | 計算コア。@smogon/calc (gen9) への適合（IV31／Lv50／EV=SP×8）、calcMatchup（表示用一括計算）、damageRolls（乱数16本の取得）、KO% の表示ロジック、spec_patches の適用 |
| estimate_engine.mjs | 1,812 | 型推定エンジン。ベイズ推定＋制約交差（inf）の二層構造。UI から createEstimator で生成して使用 |
| bundle.mjs | 29,383 | 上記2モジュール＋@smogon/calc のバンドル生成物。UI はこれを読み込む（core.mjs を直接は読まない） |
| sync_ui.py | 344 | リポジトリの公開ファイルを取得し、ハッシュ照合のうえローカルへ反映する |
| push_update.py | 283 | push の唯一の経路。security_check と tests/run_checks.py のゲートを通過した場合のみアップロードする |
| paddle_sidecar.py | 253 | PP-OCRv6 small による第2チャンネルの OCR。生の証拠を battle_<key>_paddle.jsonl に記録するのみで、状態判定には使わない |
| start_all.sh | 100 | Mac 側の統合起動スクリプト |

## 3. data/ の主要ファイル

| ファイル | 内容 |
|---|---|
| champions_dex.json | 全 gen9 母集団（種族 1,323／持ち物 583／技 942） |
| regulation.json | Champions 実装範囲のフィルタ（レギュレーション M-C、シーズン M-8。種族 370／持ち物 165／技 870、specialElements: ["mega"]） |
| usage_sets.json | pokedb 使用率の「最も使われている型」（262 セット、シーズン M-8） |
| pokedb_parsed.json | pokedb の解析済み使用率データ（262 キー） |
| vgc_pastes.json / vgcpastes_sets.json / vgc_pastes_stats.json | VGCPastes コーパス（744 チーム／4,462 セット）と統計 |
| meta_sets.json | メタ側コーパス（推定の候補生成に使用） |
| names_ja.json / names_index.json | 日本語名の対応（種族・技・特性。PokéAPI 由来） |
| items_ja.json | 持ち物の日本語名対応（588 件） |
| species_types.json / species_abilities.json / species_moves.json | 種族ごとのタイプ・特性・技の参照データ（認識と計算の双方が参照） |
| preview_features.json | 見せ合い同定のスプライト特徴量＋実フレームテンプレート（調査時点で 200 件超のテンプレートを含む） |
| type_icons.json | タイプアイコンの参照グリフ・参照色＋実サンプル |
| spec_patches.json | シーズン仕様変更への差分レイヤー（UI の「仕様」セレクタと連動） |
| pokedb_cache/ / vgc_cache/ / meta_cache/ | 取得元ページ等のキャッシュ（再生成時に使用） |

## 4. tests/ の主要ファイル

| ファイル | 役割 |
|---|---|
| run_all.sh | 全スイートの一括実行（push ゲートと定期ウォッチドッグが使用） |
| run_checks.py | push 対象ファイルに応じて必要なスイートを選ぶゲート |
| check_moves.mjs / check_coverage.mjs / check_spec_patches.mjs / check_item_map.mjs | データと UI の整合（技の解決、網羅、仕様差分、持ち物対応）の検査 |
| ui_harness.mjs | 実 ui.html をヘッドレスで読み、state.json の系列を再生して盤面構築を検証（300件超のチェック） |
| calc_audit.mjs | UI の配線と素の @smogon/calc の結果の突き合わせ |
| audit_calc.mjs | 計算監査の補助 |
| bayes_sim.mjs / bayes_eval.mjs / bayes_moves_eval.mjs / bayes_equiv.mjs / vgc_doubles_sim.mjs | 推定エンジンのシミュレーション・評価・等価性確認 |
| bayes_equiv_golden.json | 推定の等価性ゴールデン（調査時点でローカル版が公開版と相違。MUSE-SNAPSHOT.md 参照） |
| test_*.py（約25件） | serve.py の各機能（フラグ、備考ゲート、アップロード再開、フォルダ化、プリセット等）の単体テスト |
| preview_eval.py / icon_eval.py | 見せ合い・アイコン認識の評価 |

reader 側のハーネスは別置き（`~/workspace/logfix_test/`。reader の実解析チェーンを抽出して検証する）。

## 5. 文書類（プロジェクト内）

| ファイル | 内容 |
|---|---|
| README.md | 構成と Mac での使い方 |
| IMPLEMENTATION_MANUAL.md | 実装指示・実実装の手順（計画と自己議論、管轄、ゲート等） |
| PLANNING_MANUAL.md | 大きな変更の議論から指示発出までの流れ |
| CAPTURE_DECOUPLING_DESIGN.md | 撮影と認識の分離の設計 |
| PADDLE_DESIGN.md | PaddleOCR 補助チャンネルの設計 |
| PHASE3_DESIGN.md / PHASE4_DESIGN.md | 交代読み取り等の reader 改善フェーズの設計 |
| SPEC_PATCHES.md | 仕様差分レイヤーの運用手順 |
| INDEX_BLOAT_PLAN.md | logs_enc／index 肥大化対策の改訂版計画（2026-11-24 作成、未実施） |
| ESTIMATION_IMPROVEMENT_PLAN_DRAFT.md | 型推定の改善計画ドラフト（未実施） |
| FLAG_MANUAL_PLAN.md / PRINT_DELAY_PLAN.md / FIX_*.md | 個別案件の計画・修正計画 |
| MEMORY_DETAIL.md | プロジェクトの詳細経緯のアーカイブ |
| BACKLOG.md | 保留中の作業項目 |

## 6. プロジェクト外の関連物（対象範囲の注記）

- Mac ローカルの PaddleOCR 実行環境（venv・モデル）は Mac 上の専用フォルダにのみ存在し、同期・ZIP の対象外。
- Muse 側の到着検知フック（champions-log-watch）と取得スクリプトは、このフォルダではなく Muse の実行環境側に置かれる（リポジトリ同期対象外）。
- reader ハーネス一式は `~/workspace/logfix_test/` に置かれる。
