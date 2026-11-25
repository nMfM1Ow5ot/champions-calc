# 環境再構築資料

Muse が存在しない場合に、第三者が開発を継続するための手順の要点。

## 1. 取得

1. https://github.com/nMfM1Ow5ot/champions-calc を clone する（main が稼働中システム）。
2. 保全ブランチ `preservation` を checkout し、`preservation/` 配下に元の相対パスで置かれた資産（ツール、テスト、設計文書、ハーネス、ジョブ定義バックアップ）を参照する。

## 2. 計算 UI の再現

- `npm ci`（package-lock.json は保全ブランチ内）で依存を復元する。
- core.mjs を変更した場合は bundle_entry.mjs から esbuild で bundle.mjs を再構築する（手順は AGENTS 相当の記録として MEMORY_DETAIL.md と本書群を参照）。
- テストは保全ブランチの tests/run_all.sh（全スイート）と tests/run_checks.py（push ゲートの選択実行）を使う。

## 3. Mac 側の運用（対戦読み取り）

- 構成：iPad（USB）→ Mac QuickTime ミラーリング → reader.swift（Vision OCR）が state.json を書く → serve.py（127.0.0.1:8765）が ui.html を配信し、GitHub 同期とログ保存を行う。
- reader.swift の変更前には `bash check_reader.sh`（Linux Swift ツールチェイン＋ check/ のスタブ）で型チェックを通す。
- PaddleOCR 補助チャネルは paddle_kit/README_MAC.md（保全ブランチ）に従って Mac に導入する。モデル等は ~/champions_paddle/ に置き、同期対象に含めない。

## 4. データの再生成

- 使用率データ：`node fetch_usage.mjs`（data/pokedb_cache を消してから実行すると全件再取得）。
- VGCPastes：`node fetch_vgcpastes.mjs`（キャッシュ data/vgc_cache は消さない）。
- 名称データ：fetch_names.mjs／build_names.mjs（保全ブランチ）。

## 5. 同期・配布の機構（原本は非公開のため役割のみ）

以下の4件はプロジェクト自身のセキュリティ規則により公開リポジトリへ登録していない（05_EXCLUDED.md）。継続運用には、ユーザーから原本の提供を受けるか、本書の役割記述から再実装する必要がある。

- sync_ui.py：同期対象ファイルの一覧（MANIFEST）の正本と、GitHub Contents API 経由の送受信。
- push_update.py：同期対象の push 手順（セキュリティ検査→機能ゲート→本体→マニフェスト→rev の順に登録）。マニフェストは引き継ぎ方式（対象外ファイルは公開中マニフェストのハッシュを引き継ぐ）。
- security_check.py：push 前の秘密情報検査（鍵の値、トークン形式、個人情報、認証情報らしい代入、公開禁止ファイル名）。
- build_zip.py：配布用 ZIP の生成（内部トップフォルダは champions_calc_YYYYMMDD_HHMM/）。

## 6. 定期実行

- ジョブ定義のバックアップ（保全ブランチの workspace/cron_backups/）に、監視ドッグ、データ再取得、日次監査、ガーディアン等の定義が含まれる。Muse 以外の基盤で再現する場合は、各定義の指示文を cron 等へ移植する。
