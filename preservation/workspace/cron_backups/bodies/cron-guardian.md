定期タスクの見張り役（ユーザー指示 2026-11-21: タスクが勝手に消えないようにする仕組み）。30分ごとに実行される。

手順:
1. ~/workspace/cron_backups/manifest.json を読む。読めない場合は、その旨をこの実行の報告としてメインチャットへ送って終了する。
2. cron.list で現在の登録を確認し、manifest の jobs の id と照合する。
3. manifest にあるのに登録が無いタスクは、manifest の定義で復元する（kind=agent は cron.add、kind=space_action は cron.add_artifact_action。id・スケジュール・配信先・本文は manifest と bodies/ のファイルのとおり）。復元したら、この実行の報告としてメインチャットへ「どのタスクを復元したか」を送る。
4. 登録はあるが無効（enabled=false）になっているタスクは、ユーザーが意図的に止めた可能性があるため、勝手に有効化せず、報告だけ送る。
5. 登録のあるタスクについて、スケジュールまたは配信先が manifest と食い違っていたら、正規の変更とみなして manifest を現在の定義に合わせて更新し、その旨を報告する。本文（body）の食い違いは manifest 側のファイル（bodies/<id>.md）を現在の本文で上書きする（報告不要）。
6. 欠けも食い違いも無ければ、何も送らずに終了する。

注意:
- このジョブ自身（cron-guardian）と cron-guardian-daily も manifest に含まれている。cron-guardian-daily が消えていたら手順3で復元する。
- タスクの内容そのものには干渉しない。復元と manifest の追随だけを行う。
