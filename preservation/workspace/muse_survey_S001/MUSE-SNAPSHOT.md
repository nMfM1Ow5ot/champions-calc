# MUSE-SNAPSHOT — 調査基準時点と対象の識別情報

- Snapshot ID: **S001**（初回調査）
- 調査開始日時: 2026-11-24 10:29 JST
- 調査終了日時: 2026-11-24 10:35 JST
- 調査担当: champions_calc 総合チャット（Muse）
- 調査の性質: 調査・報告のみ。プロジェクトへの変更は一切行っていない

## 1. 対象の識別方法

本プロジェクトは、調査対象フォルダ内にローカルの Git リポジトリ（.git）を持たない。バージョンの識別は次の2系統で行った。

1. 公開リポジトリ `nMfM1Ow5ot/champions-calc`（GitHub）の ui_manifest.json が保持する、ファイル別 SHA-256 とリビジョン番号（rev）。
2. ローカルファイルの SHA-256 実測値。

調査時点の公開リビジョン: **20261124_0418**（ui_manifest.json の rev。2026-11-24 に raw.githubusercontent.com から取得して確認）。

## 2. 主要ファイルの識別（SHA-256、調査時点の実測）

| ファイル | SHA-256 | 公開版との一致 |
|---|---|---|
| reader.swift | e7b07e6747f3200bae79ec0deb1c4dc67391e8448fcfc23ca653224daa49a7f4 | 一致 |
| serve.py | 0ebc213dc21373384e7f5aa04000b0e1ef51eede1024654d2c9bc1dd88ed408b | 一致 |
| ui.html | cba2b4d3ee5f625d77dfe39939e399ead4554bd2bb93d6c1b3c815567af9500f | 一致 |
| core.mjs | 5d23880e356377585b94fbe0d8836636fb7cc4f1acf6b68ee012d1c38d2904da | 一致 |
| estimate_engine.mjs | 51556ca9c33aeb685d83b5f1674ce0f250822202dadc565175cb3d532a612004 | 一致 |
| bundle.mjs | e0d15366a1e64fce041b5dda1bfe4e61eb8031dbf66c9721ca649a895fc23971 | 一致 |
| sync_ui.py | ca6807b523debbc682eac53cae6b50a1e5b6155442779776750b21e4491177bc | 一致 |
| start_all.sh | 8761f84fdb2db8907de7fc1f0b494ee74243035c53abcd14b415d26892cc5a04 | 一致 |
| paddle_sidecar.py | 672fbbf032652bbe385d5960a96b713d4544abc6b40f93d3c14afd378dd437bf | 一致 |
| fetch_usage.mjs | c3a1bc1b6a4ff877db9866e9d15c4ae13b2b4bfdf189d2df4de1373d43bcca9e | **相違**（下記 3.） |
| tests/bayes_equiv_golden.json | f6b7f666d951dc48e35e31d030ce2b795d7d38ce51410eb73ea5df117a7981a4 | **相違**（下記 3.） |

data/ の主要ファイル（pokedb_parsed.json、usage_sets.json、regulation.json、items_ja.json、preview_features.json、vgc_pastes.json）と my_team.json も公開版と一致していた。

## 3. 未コミット変更に相当するもの（ローカルと公開版の相違）

Git 管理ではないため、「未 push のローカル変更」を未コミット変更に相当するものとして記録する。

1. **fetch_usage.mjs**: ローカル版のみに変更がある。内容は、2026-11-24 未明に判明した持ち物の日英対応表（ITEM_JA2EN）の誤り（実（ベリー）の取り違え 15 件・欠落 13 件）の修正と、生成時に items_ja.json を優先して引く変更（ダメージ計算チャットの作業記録と一致）。この相違のため、同日 00:00 の pokedb 定期再生成ジョブは push を見送った。
2. **tests/bayes_equiv_golden.json**: ローカル版が公開版と異なる。2026-11-23 の定期監査でも観察として記録されていた相違で、編集の claim は当時無かった。

## 4. 実行に関係する未追跡ファイル（同期対象外の実行時ファイル）

- state.json（reader が書く現在の対戦状態）
- flag_control.json（手動フラグの制御ファイル）
- team_key.txt（暗号化の鍵。**値は本資料群のいずれにも記載していない**）
- logs/（Mac 側の試合ログ）、logs_received/（受信済みログ）、preview_eval/、ocr_eval/、golden/ 等の作業・生成物
- .edit_state.json（編集 claim の管理、ローカル専用）
- node_modules/、__pycache__/

## 5. 使用言語・ランタイム・ライブラリのバージョン

| 対象 | バージョン・識別 |
|---|---|
| @smogon/calc | ^0.12.0（package.json） |
| esbuild | ^0.28.2（package.json、開発依存） |
| Node（調査環境の実測） | v24.22.1 |
| Python（調査環境の実測） | 3.12.3 |
| Swift（reader 型チェック用ツールチェーン） | 6.0.3（tests/run_all.sh の既定パス） |
| PaddleOCR／PaddlePaddle（Mac ローカル、文書記録） | 3.7.0／3.3.1 |

## 6. 主要設定・データの識別情報

| 対象 | 識別情報 |
|---|---|
| レギュレーション | M-C（data/regulation.json） |
| シーズン | M-8（regulation.json／usage_sets.json ともに一致） |
| 実装範囲 | 種族 370／持ち物 165／技 870、specialElements: ["mega"] |
| 母集団データ | champions_dex.json: 種族 1,323／持ち物 583／技 942 |
| 使用率データ | usage_sets.json: 262 セット |
| 収集セット | vgc_pastes.json: 744 チーム |
| ログ保管（リポジトリ側） | logs_enc: 983 ファイル／約385MB、index.json 189,156 バイト（2026-11-24 監査実測） |

## 7. 調査対象と対象外の範囲

- 対象: `~/workspace/champions_calc/` のソース、設定、データ、テスト、プロジェクト内文書。公開リポジトリのマニフェスト。
- 対象外（存在と役割の確認にとどめたもの）: Mac ローカルにのみ存在する実行物（PaddleOCR の venv・モデル、Mac 側の logs/ 現物、実機の reader 実行挙動）、ユーザーの端末内の他データ、本資料群に含めない認証情報・鍵・個人情報。
- 本調査では新規のベンチマーク実験は行っていない（指示書の定めによる）。

## 8. 調査中の変更検出

調査終了時（2026-11-24 10:35 JST）に、主要ファイル8件（reader.swift、serve.py、ui.html、core.mjs、estimate_engine.mjs、bundle.mjs、fetch_usage.mjs、tests/bayes_equiv_golden.json）の SHA-256 を再実測し、調査開始時の値とすべて一致することを確認した。調査期間中に、対象ファイルの変更は検出されなかった。本資料群の内容は、すべて同一時点（S001）の情報で構成されている。
