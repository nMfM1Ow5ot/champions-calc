# 非公開・保留・除外資産一覧（理由付き）

公開リポジトリ（保全ブランチを含む）へ登録しなかった資産と、その理由・適切な保存先候補。

## G：秘密情報・非公開情報（登録禁止）

| 資産 | 理由 | 保存先候補 |
|---|---|---|
| team_key.txt | チームデータの暗号化鍵そのもの | ユーザー保有のみ |
| my_team.json | 自軍構築の平文 | ユーザー保有のみ（公開側は my_team.enc のみ） |
| my_team.enc のローカル版（分類 B） | 公開側が正であり、暗号化済みでも自軍構築情報 | 公開側の現行版が正 |
| github_log_token.txt（プロジェクト内に実在する場合は同様） | ログ取得用トークン | ユーザー保有のみ |
| logs_received/（992件、対戦ログ・デバッグ画像・動画） | 非公開の対戦ログ・スクリーンショット | ユーザー保有。暗号化ログは logs_enc/ として GitHub に既存 |
| video_probe/ の動画・フレーム（524件） | 対戦動画 | ユーザー保有 |
| ocr_eval/ の対戦画面画像（91件）、paddle_kit/samples/（29件） | 対戦画面のスクリーンショット・切り抜き | ユーザー保有 |
| 配布用 ZIP 15件（champions_calc_*.zip） | team_key.txt を同梱するため | ユーザー保有 |
| video_probe/cookies.txt | セッション認証情報（Cookie） | 登録しない（保全不要） |
| state.json、.edit_state.json | 一時状態・編集ロック状態 | 保全不要 |

## 保留：プロジェクトのセキュリティ規則による公開禁止ファイル（4件）

security_check.py の公開禁止ファイル名に指定されているため、保全ブランチにも登録しなかった。内容走査では、security_check.py 自身が検出パターン定義として Mac ユーザ名のリテラルを含む以外、秘密情報の検出はない。役割は 04_REBUILD_GUIDE.md の第5節に記録した。完全な継続性が必要な場合は、非公開リポジトリへの別途保管が適切。

| 資産 | 役割 |
|---|---|
| sync_ui.py | 同期対象一覧（MANIFEST）の正本と送受信機構 |
| push_update.py | push 手順（ゲート、マニフェスト引き継ぎ、編集ロック連携） |
| security_check.py | push 前の秘密情報検査 |
| build_zip.py | 配布用 ZIP 生成 |

## H：判断保留・除外（2件）

| 資産 | 理由 |
|---|---|
| preview_eval/glb/Salamence.glb、SalamenceShiny.glb（各約7.2MB） | Contents API のサイズ上限超過に加え、ゲーム由来 3D モデルの再配布権が未確認のため除外。ローカル保存場所は目録に記録 |

## F／E：再生成可能・外部依存（登録しない）

- Python venv 群（preview_eval/glb_venv 6,444件、ocr_eval/.venv 25,971件）：再構築可能。
- Blender 4.2 配布物（4,759件、約1.64GB）：公式配布物として再取得可能。
- 抽出フレーム・スプライト（402件）、取得キャッシュ（data/pokedb_cache 262件・202.3MB、data/vgc_cache 743件、data/meta_cache 98件）：再生成・再取得可能。
- node_modules（264件）：package-lock.json（登録済み）から再生成可能。
- ~/workspace/virtual_envs/（10,781件）：他リポジトリ（showdown-virtual-env、showdex-virtual-env）のスナップショット。各リポジトリに収録済みのため複製しない（コミットは 02_DIFF_SUMMARY.md）。
