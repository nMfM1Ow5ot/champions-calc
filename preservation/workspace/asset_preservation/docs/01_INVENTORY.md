# champions_calc ローカル資産 包括的目録

- 作成：2026-11-26（総合チャット 61dc1fd3、GPT-6.2 発の保全指示に基づく）
- 基準コミット：19ea2d65256c180f0708ae4d977dd6ca8a157201（調査開始時点で GitHub main の最新コミットと一致）
- 対象リポジトリ：https://github.com/nMfM1Ow5ot/champions-calc （公開、main）
- 保全先：同リポジトリの専用ブランチ `preservation`、パス接頭辞 `preservation/` + 元のホーム相対パス
- 調査方法：対象11か所を走査し（25,523エントリ）、プロジェクト本体の全ファイルについて SHA-256 と git blob SHA-1 を算出し、GitHub のツリー（1,046 blob）と照合した。機械可読の全件データは本書と同梱の inventory_classified.json（分類済み）と inventory_local.jsonl（生目録）を参照。

## 調査範囲と件数

| 保存場所 | 件数 | 備考 |
|---|---|---|
| ~/workspace/champions_calc/ | 13,652ファイル＋集約ディレクトリ | プロジェクト本体。下記の差分分類の対象 |
| ~/workspace/logfix_test/ | 101 | reader パース検証ハーネスと修正パッチ履歴 |
| ~/workspace/mh001_deliverables/ ほか MH-001 系5か所 | 21 | MH-001／R1 の成果物・修正前控え・検証資料 |
| ~/workspace/muse_survey_S001/ | 5 | 2026-11-24 の実態調査 S001 成果物 |
| ~/workspace/cron_backups/ | 14 | 定期実行ジョブ定義のバックアップ |
| ~/workspace/virtual_envs/ | 10,781 | 他リポジトリのスナップショット（分類 D、複製しない） |
| ~/workspace/your_files/ | 142（うち champions 関連は成果物 ZIP・資料類） | 配布済み成果物。ZIP は分類 F／G として記録のみ |
| ~/swift-toolchain/ | 集約1件（約3.3GB） | Swift Linux 検証環境（分類 E、文書で記録） |

## プロジェクト本体の内訳（分類の要約）

- GitHub 版と同一（C）：54件 — 同期対象ファイル群（ui.html、core.mjs、bundle.mjs、estimate_engine.mjs、reader.swift、serve.py、paddle_sidecar.py、データファイル群、R1 テスト9件ほか）
- GitHub 版と相違（B）：4件 — 詳細は 02_DIFF_SUMMARY.md
- GitHub 未収録（A）：13,594件 — 内訳は 02_DIFF_SUMMARY.md の処分表を参照。うち保全対象（コード・文書・テスト）236件と、プロジェクト外の保全対象（logfix_test 等）を合わせ、重複を除く 374件を保全リスト化し、367件を preservation ブランチへ登録した（残り7件は保留・除外、05_EXCLUDED.md）。

## GitHub にのみ存在するもの

- logs_enc/（983件、約385MB）：暗号化済み対戦ログ。serve.py が Contents API 経由で直接リポジトリへ保存する運用のため、ローカルに対応物はない。既に GitHub 上に保全されている。
- ipad.html、sp.html、presets.json：リポジトリに存在するが本 VM のプロジェクトには対応ファイルがない（Mac 側運用で生成・使用されるものと推定。未調査領域として記録）。
- ui_manifest.json、ui_rev.txt：push 機構が生成・管理するファイル。
