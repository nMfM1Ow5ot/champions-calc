# MH-001-SNAPSHOT — 変更前後の識別情報

- 対象: MH-001（複数ヒット技のダメージ乱数分布の修正）
- S001 との関係: 本修正の基準点は S001（調査基準時点 2026-11-24、公開リビジョン 20261124_0418）。修正前のファイルは S001 のハッシュと一致することを確認したうえで着手した。
- 修正開始日時: 2026-11-24 10:42 JST（指示書の受領）。事前調査と修正前ファイルの保存は同日 10:43〜10:46。
- 修正終了日時: 2026-11-24 11:01 JST（最終 push）。検証と報告書の作成は同日その後に実施。

## 1. 修正前後の主要ファイルの SHA-256

| ファイル | 修正前（S001） | 修正後 | 公開状態 |
|---|---|---|---|
| core.mjs | 5d23880e356377585b94fbe0d8836636fb7cc4f1acf6b68ee012d1c38d2904da | 7be4711d33cbaba3bcbebd4b4e263c1e0f0a0bcefa58d75a47a5ae4da38c506e | rev 20261124_1051 で公開 |
| ui.html | cba2b4d3ee5f625d77dfe39939e399ead4554bd2bb93d6c1b3c815567af9500f | 89ba5030e6cbf545f2525eb53a2796144444372bfa9f3aa275160323326d2583 | rev 20261124_1051 で公開 |
| estimate_engine.mjs | 51556ca9c33aeb685d83b5f1674ce0f250822202dadc565175cb3d532a612004 | 7532733faab9a92721f67673d0137ddafa8122bb3f88ff3500e6756e1fdc4bf3 | rev 20261124_1101 で公開 |
| bundle.mjs | e0d15366a1e64fce041b5dda1bfe4e61eb8031dbf66c9721ca649a895fc23971 | 9798fa12f7fc8c34bbd9126dc3aa155cb72db8b6f5ed8e305946ec770a9b21c4 | 両 rev で再構築して公開 |
| tests/test_move_spec.mjs | c7689770faa59431ff59ffdc752ee3aac41e71c06124b6cb4477985a30297eb5 | 933f91bddd089f0fadd50372573ffb8918d1c94a8d3988c7ccce1e780487e228 | ローカル（テストは同期対象外） |
| tests/test_multihit_dist.mjs | （新規） | MH-001-DIFF.patch に全文を含む | ローカル（同上） |
| tests/bayes_sim.mjs | 0a1221f18ccc0ad0b974ff2719cc3e6b2d30e1e1d0f8e5f89b8cf80943420658（公開版） | 6e9ebf718730b2fdc7fb8b843eacd211e293802304adb76b384b0a56ad3f2d26 | ローカルのみ（未 push） |
| tests/vgc_doubles_sim.mjs | 復元可能な写しが無い（同期対象外） | 72c3f6d9bdd9639901dfa2d251b78846b45032d6f3d19bf71fd7de839ba501a3 | ローカルのみ（未 push） |

## 2. 公開リビジョンとローカル版の関係

- 修正前: rev 20261124_0418（S001 の基準）。
- 修正後: rev 20261124_1051（ダメージ計算分）→ rev 20261124_1101（型推定分、現行の公開 rev）。
- 公開マニフェスト（rev 20261124_1101）とローカルの core.mjs／ui.html／estimate_engine.mjs／bundle.mjs のハッシュ一致を、総合が取得して照合済み。
- tests/bayes_sim.mjs と tests/vgc_doubles_sim.mjs の追随変更はローカルのみにあり、未 push である（ハーネスであり、本番の動作には影響しない）。

## 3. 変更ファイル一覧

- core.mjs（畳み込みと分布 API の新設、damageRolls と rollsOf の置換）
- estimate_engine.mjs（全利用箇所の質量ベース化、ゲートの multihit 項の解除、assumedHits の記録）
- ui.html（バルーンの分布表示）
- bundle.mjs（再構築による生成物）
- tests/test_multihit_dist.mjs（新規）
- tests/test_move_spec.mjs（B2・C・F の書き換え）
- tests/bayes_sim.mjs、tests/vgc_doubles_sim.mjs（ハーネスの追随、ローカルのみ）

## 4. 依存ライブラリのバージョン

- @smogon/calc 0.12.0（変更なし。package.json の指定は ^0.12.0）
- esbuild ^0.28.2（変更なし）
- ライブラリの更新は行っていない。

## 5. バンドル再構築の確認

- 両 push ともに、bundle_entry.mjs（core.mjs + estimate_engine.mjs + @smogon/calc の Generations）から esbuild で再構築した。
- 再構築の方法：`./node_modules/.bin/esbuild bundle_entry.mjs --bundle --format=esm --outfile=bundle.mjs`
- 再構築後の bundle.mjs のハッシュは §1 のとおりで、公開マニフェストと一致する。

## 6. 他の未公開変更を維持したことの確認

- fetch_usage.mjs のローカル修正（持ち物の日英対応表の誤りの修正、S001 で記録）は、本修正の前後で不変である（公開マニフェスト側のハッシュも従来どおりで、本修正では触れていない）。
- tests/bayes_equiv_golden.json のローカル版も不変である（再記録はしていない）。
- 自動復旧機構による未公開変更の消失は発生していない（上記の未公開変更が現存することで確認）。

## 7. 復元方法

- 修正前のファイル一式は ~/workspace/mh001_prefix/ に保存してある（core.mjs、estimate_engine.mjs、ui.html、bundle.mjs、tests/test_move_spec.mjs）。これらをプロジェクトへ戻し、bundle.mjs を上書き（または §5 の方法で再構築）すれば修正前の状態に戻る。
- 公開側は、リポジトリの rev 20261124_0418 時点のファイルが修正前の内容であり、ui_manifest.json（当該 rev）のハッシュで同一性を確認できる。
- tests/bayes_sim.mjs の修正前は、リポジトリの現行公開版（ハッシュ 0a1221f1…）がそのまま修正前の内容である。
