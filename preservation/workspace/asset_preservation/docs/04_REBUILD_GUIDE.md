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

## 7. 保留4件の詳細（バックエンド管轄からの報告、2026-11-26）

### sync_ui.py（344行、SHA-256 先頭16桁 ca6807b523debbc6）
- 役割：Mac 側の同期クライアント。公開リポジトリの ui_manifest.json と ui_rev.txt を取得し、MANIFEST の同期対象ファイルをハッシュ照合しながらダウンロードしてローカルへ反映する。あわせて my_team.enc を team_key.txt の鍵で復号して my_team.json を生成する（openssl サブプロセス経由、OpenSSL Salted__ 形式）。start_all.sh が起動時に --force で実行する。
- 依存関係：MANIFEST（同期対象一覧と期待ハッシュ）の単一の正本であり、push_update.py、build_zip.py、security_check.py の既定対象が参照する。実行には team_key.txt（ローカルのみ）と公開側 ui_manifest.json が必要。
- 再構築：MANIFEST のファイル一覧は公開済み ui_manifest.json から復元可能。復号は OpenSSL 互換 AES-256-CBC（鍵は team_key.txt）。端末出力抑制（_LIMIT_TERMINAL_OUTPUT、2026-11-23 の案B）を含む版が現行版。

### push_update.py（283行、SHA-256 先頭16桁 7fd1d32d72d4b2b0）
- 役割：同期対象ファイルの唯一の正規 push 手段。security_check.py の走査、tests/run_checks.py のゲート、edit_lock の競合確認を順に行い、全て通過した場合のみ gh.py 経由で Contents API へ登録する。公開側 ui_manifest.json から未対象ファイルのハッシュを引き継ぐ方式で、取得失敗や競合時はマニフェストを更新せず中止する。
- 依存関係：sync_ui.py（MANIFEST の import）、security_check.py、tests/run_checks.py、edit_lock.py と .edit_state.json、gh.py（custom.github コネクタ）。
- 再構築：動作仕様はプロジェクトの規則記録（ゲート迂回禁止、カリーオーバーの中止条件、--as 記録、push 後の blob 照合）に残っており、tests/test_push_update.py（保全済み）の期待動作が仕様の裏付けになる。

### build_zip.py（30行、SHA-256 先頭16桁 64b4c8197a2703d3）
- 役割：配布用 ZIP の生成器。MANIFEST のファイル一式に sync_ui.py、team_key.txt、state.json を加えて梱包する。ZIP 内トップフォルダは champions_calc_YYYYMMDD_HHMM/（ファイル名の日時と一致）。
- 依存関係：sync_ui.py の MANIFEST を import。team_key.txt を含むため生成 ZIP は配布先限定。
- 再構築：梱包対象とトップフォルダ名の規則から再作成可能（小規模）。

### security_check.py（119行、SHA-256 先頭16桁 b73bc1b63a501cdc）
- 役割：push 前の秘密情報走査器。公開禁止ファイル名と禁止パターン、トークン形式（GitHub、AWS、秘密鍵ブロック、Slack、sk- 形式）、個人情報（Mac ユーザ名、/Users/ パス、メールアドレス）、認証情報らしい代入のパターンで全同期対象を走査し、team_key.txt の値そのものの混入も照合する。検出時はファイル名・行・ルール名のみを表示し、値は伏せる。
- 依存関係：標準ライブラリのみ。照合のためローカルに team_key.txt が必要。push_update.py から scan_files() が呼ばれる。
- 備考：このファイル自身が検出パターン定義（47〜48行目）に Mac ユーザ名の文字列をリテラルで含むため、公開するとユーザ名そのものが公開される。これも公開禁止の実質的理由の一つ。
