champions_calc の pokedb 使用率データを再取得して最新化する定期ジョブ（ユーザー指示 2026-11-20、当初は一日置き。2026-11-21 にユーザーが24時間ごとへ変更）。2026-11-22 から、VGCPastes Repository の型収集・統計の更新もこのジョブに相乗りする（ユーザー指示、質問・調査チャット経由）。

作業ディレクトリ: ~/workspace/champions_calc

手順:
1. 現在の data/items_ja.json を /tmp に退避し、data/pokedb_parsed.json と data/usage_sets.json の SHA-256 を記録する。
2. data/pokedb_cache を削除してから `node fetch_usage.mjs` を実行する（キャッシュはシーズン単位で再利用されるため、消さないと最新化できない。全件再取得で約8分かかる）。これにより data/pokedb_parsed.json / data/usage_sets.json / data/regulation.json が再生成される。
3. 検証: 両 JSON がパースできること、usage_sets の sets が約262件、pokedb_parsed のキーが約262件あること、regulation.json の season と usage_sets の season が一致すること。失敗したら push せず、このチャットに失敗内容を報告して終わる。
4. items_ja.json の項目数が退避分より減っていたら、退避分を書き戻す（fetch_usage.mjs には既存項目優先マージの修正が入っているので通常は減らない。減っていたら異常として報告にも一言添える）。
5. pokedb_parsed.json と usage_sets.json のハッシュが手順1と同じ（データに変化なし）なら、push せず静かに終わる（報告不要）。
6. push 前の競合チェック: リポジトリの ui_manifest.json とローカルの全同期対象ファイルを照合し、今回の再取得ファイル（data/pokedb_parsed.json / data/usage_sets.json / data/regulation.json / data/items_ja.json）以外のファイルに差分があったら、他のチャットが編集中の可能性があるため push せず、このチャットにその旨を報告して終わる。
7. push は必ず `python3 push_update.py data/pokedb_parsed.json data/usage_sets.json data/regulation.json --msg "pokedb data refresh"` で行う（セキュリティチェックと機能ゲートは自動で走る。失敗したら迂回せず、このチャットに報告して終わる）。
8. 成功したら、このチャットに新しい rev・シーズン名・種族数を1〜2行で報告する。
9. VGCPastes 更新: data/vgc_pastes.json / data/vgc_pastes_stats.json / data/vgcpastes_sets.json の SHA-256 を記録してから `node fetch_vgcpastes.mjs` を実行する（シート再取得→Team ID / PokéPaste URL の差分判定→新規・変更分だけ間隔を空けて直列取得→統計再計算。キャッシュ data/vgc_cache/ は消さないこと）。出力最終行の VGCPASTES|... サマリ（teams / sets / fetched / rejects / changed）を確認する。実行に失敗したら push せず、このチャットに失敗内容を報告して終わる。
10. 3ファイルのハッシュが手順9の記録と同じ（changed=0）なら、VGCPastes 側は push せず静かに終わる。
11. 変更がある場合は、手順6と同様に他の同期対象ファイルへ差分が無いか確認し（あったら push せず、このチャットにその旨を報告して終わる）、`python3 push_update.py data/vgc_pastes.json data/vgc_pastes_stats.json data/vgcpastes_sets.json --msg "vgcpastes data refresh"` で push する。失敗したら迂回せず報告して終わる。
12. VGCPastes 側で push した場合は、その rev とチーム総数を、このチャットへの報告に1行加える（pokedb 側に変更が無くても、VGCPastes 側の変更だけで報告する）。
