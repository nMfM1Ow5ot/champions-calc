# GitHub との全差分一覧

基準：GitHub main @ 19ea2d65256c180f0708ae4d977dd6ca8a157201 のツリー（1,046 blob）と、ローカル目録（SHA-256／git blob SHA-1）の照合結果。

## 分類別件数（プロジェクト本体 13,652ファイル）

| 分類 | 件数 | 内容 |
|---|---|---|
| A. GitHub に存在しない | 13,594 | 処分表参照 |
| B. GitHub 版と内容が異なる | 4 | 下表 |
| C. GitHub 版と同一 | 54 | 同期対象ファイル群 |
| D. 他リポジトリに存在 | （プロジェクト外）10,781 | ~/workspace/virtual_envs/ のスナップショット2リポジトリ分 |
| E. ローカル環境固有・外部依存 | A の内数 4,759＋集約分 | Blender 配布物、Swift ツールチェイン等（03_DEPENDENCIES.md） |
| F. 再生成可能な派生資産 | A の内数 6,944＋集約分 | venv、抽出フレーム、取得キャッシュ、node_modules 等 |
| G. 秘密情報・非公開情報 | A の内数 1,655 | 対戦ログ・画像・動画、鍵、平文チーム等（05_EXCLUDED.md） |
| H. 判断保留・除外 | 7（保全リスト内の保留）＋GLB 2件 | 05_EXCLUDED.md |

## A の処分表

| 処分 | 件数 | サイズ |
|---|---|---|
| F 再生成可能（Python venv） | 6,444 | 218.7 MB |
| E 外部依存（Blender 配布物＋tar） | 4,759 | 1,643.0 MB |
| G 非公開（対戦ログ・画像・動画、logs_received） | 992 | 568.9 MB |
| G 非公開（対戦動画・フレーム、video_probe） | 524 | 451.7 MB |
| F 再生成可能（抽出フレーム・スプライト） | 402 | 71.5 MB |
| 保全対象（コード・文書・テスト） | 236 | 62.6 MB |
| F 再生成可能（取得キャッシュ data/*_cache） | 98 | 7.6 MB |
| G 非公開（対戦画面画像、ocr_eval） | 91 | 44.0 MB |
| G 非公開（対戦画面サンプル、paddle_kit/samples） | 29 | 14.4 MB |
| G 非公開（配布 ZIP、鍵を含む） | 15 | 6.8 MB |
| G 秘密・一時状態（team_key.txt、my_team.json、state.json、.edit_state.json） | 4 | — |

集約記録（ファイル単位で数えないもの）：node_modules（264ファイル、40.7MB。package-lock.json を保全済みのため再生成可能）、ocr_eval/.venv（25,971ファイル、1,367.8MB）、data/pokedb_cache（262ファイル、202.3MB、再取得可能）、data/vgc_cache（743ファイル、0.8MB）。

## B の詳細（GitHub 版と内容が異なる4件）

| ファイル | ローカル SHA-256 | 扱い |
|---|---|---|
| tests/bayes_sim.mjs | 6e9ebf718730… | ローカル版を保全ブランチへ登録（上書きなし） |
| tests/bayes_moves_eval.mjs | ed76b12cf640… | 同上 |
| tests/bayes_equiv_golden.json | f6b7f666d951… | 同上（既存ドリフト。再記録しない判断が確定済みのもの） |
| my_team.enc | 06e3567f0f49… | 登録しない。公開側が正（プロジェクト運用ルール）であり、暗号化済みとはいえ自軍構築情報のため。05_EXCLUDED.md 参照 |

## D の詳細（他リポジトリ収録済み）

- showdown-virtual-env（champions/main @ 7f7b03182d1df61c88ad360cf1d1639451b97b42）
- showdex-virtual-env（champions/main @ 98ca40dbfc7de5f15aedcaa8e7ce9c1010ca064c）
いずれも GitHub 上の各リポジトリに収録済みのため複製しない。ローカルには API アーカイブ取得のスナップショットと作業コピーが ~/workspace/virtual_envs/ にある。

## 既知の不整合（差分ではないもの）

- fetch_usage.mjs：公開マニフェスト（ui_manifest.json）の記載ハッシュが旧値 2bfd811b… のままだが、実ファイルはローカル・公開とも c3a1bc1b… で一致している。マニフェスト側の記載だけが古い（監査でも継続観察）。
