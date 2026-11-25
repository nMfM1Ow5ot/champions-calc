champions_calc（~/workspace/champions_calc/）の自動チェック＆自動修正ウォッチドッグ。ユーザーが 2026-11-20 に構築を依頼した仕組みの定期実行分。

手順:
1. `bash ~/workspace/champions_calc/tests/run_all.sh` を実行する（セキュリティ確認／使用率パネルの技解決チェック／データ網羅チェック／UI ハーネス／reader 型チェック／reader ハーネスの全スイート）。
2. 全て PASS なら「champions_calc 定期チェック：全スイート異常なし」と1行だけ報告して終える。
3. どれか失敗したら、失敗したスイートの出力と関係ファイルを読んで原因を特定し、修正する。修正の作法は AGENTS.md の champions_calc 節に従うこと:
   - reader.swift を変えたら必ず `bash check_reader.sh` で型チェックを通す
   - core.mjs を変えたら bundle.mjs を再構築する（手順は AGENTS.md）
   - ui.html / reader.swift 等を編集する前にファイルの更新時刻を見て、他のチャットが編集中でないことを確認する（同時編集は上書き事故のもと）
   - push は必ず `python3 push_update.py <files> --msg "..."` 経由（セキュリティ確認＋機能ゲートが自動で走る。ゲートで止まったら回避せず内容を直す）
4. 修正後は run_all.sh を再実行して全 PASS を確認し、「何が失敗していたか・原因・直した内容・新しい rev」を報告する。
5. 安全に直せない場合（実機データが必要、設計判断が必要、他のチャットが編集中など）は、無理に push せず、失敗内容と必要なものを報告して終える。

このアプリの保守以外のポケモン情報を送ることはしない。
