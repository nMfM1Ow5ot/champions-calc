# 外部依存関係一覧

| 依存 | バージョン等 | 取得元・配置 | 再構築可能性 |
|---|---|---|---|
| Node.js | v24.22.1（本 VM 実測） | OS パッケージ等。プロジェクトは ~/workspace/champions_calc | インストールのみで再現可 |
| @smogon/calc | ^0.12.0（package.json） | npm。node_modules は再生成（package-lock.json を保全ブランチに登録済み、`npm ci` で復元） | 可 |
| esbuild | ^0.28.2（devDependencies） | npm。bundle.mjs の再構築に使用 | 可 |
| Python | 3.12.3（本 VM 実測） | OS 標準。serve.py、各種ツール、テスト群が使用 | 可 |
| Swift（Mac 本番） | macOS 標準の Swift（reader.swift の実行環境はユーザーの MacBook Air） | macOS 同梱。Vision フレームワーク（OCR）に依存するため Mac が必須 | Mac 環境が必要 |
| Swift Linux 検証環境 | Swift 6.0.3 Linux ツールチェイン＋Apple API スタブ（check/ 配下、リポジトリ収録済み） | ~/swift-toolchain（約3.3GB、本 VM ローカル）。`bash check_reader.sh` が型チェックに使用 | ツールチェインの再取得＋ check/ のスタブで再現可 |
| PaddleOCR（補助 OCR） | PP-OCRv6 small。Mac ローカルの Python sidecar（paddle_sidecar.py はリポジトリ収録済み） | モデル・venv・スプールは Mac の ~/champions_paddle/ にのみ存在（本 VM から未調査）。導入キットは paddle_kit/（保全ブランチに登録済み、README_MAC.md 参照） | キットと手順書で再構築可。モデル実体は再取得が必要 |
| Blender | 4.2（preview_eval/blender、tar 含む約1.64GB） | 選出画面の参照レンダリング実験用。現在は GLB 参照レンダリング保留中で未使用 | 公式配布物として再取得可 |
| ポケモン 3D モデル（GLB） | preview_eval/glb/ の2件 | ゲーム由来資産。再配布の権利が確認できないため保全ブランチへは登録していない | 権利面の確認が別途必要 |
| pokedb／VGCPastes 等の外部データ源 | fetch_usage.mjs、fetch_vgcpastes.mjs 等（リポジトリ収録済み） | 取得キャッシュは data/pokedb_cache（202.3MB）、data/vgc_cache に残るが、再取得で再生成可能 | 可 |
| Muse の定期実行基盤 | cron ジョブ定義一式 | 定義のバックアップは ~/workspace/cron_backups/（保全ブランチに登録済み）。実行基盤そのものは Muse サービス側 | 定義は復元可。基盤は Muse 固有 |
| GitHub 接続 | custom.github コネクタ（fine-grained PAT） | 認証情報そのものは保全対象外（秘密情報）。push_update.py 等の機構は 05_EXCLUDED.md の保留4件を参照 | 認証は再発行が必要 |
| Muse（実行エージェント基盤） | 本保全作業自体を含む運用全般 | チャット構成・管轄・手順は IMPLEMENTATION_MANUAL.md／PLANNING_MANUAL.md／MEMORY_DETAIL.md（いずれも保全ブランチに登録済み）に記録 | 文書として引き継ぎ可 |

## 環境変数・配置の要点

- プロジェクト正本：~/workspace/champions_calc/。オンライン側（GitHub）が同期の正。
- team_key.txt：プロジェクトフォルダと配布 ZIP 内にのみ存在（リポジトリ・保全ブランチには含めない）。
- PaddleOCR のスプール・venv・モデルは Mac ローカル（~/champions_paddle/）にのみ置き、同期・ZIP の対象外。
