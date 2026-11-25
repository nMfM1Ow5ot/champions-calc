# 可読ログの遅延印刷（案2）計画 — ステップ0

委任元: 質問・調査チャット（ユーザーの明示指示）。対象は reader.swift のみ（serve.py・UI・state.json は対象外、battle_protocol.log は不変）。着手条件だった 090354 修正ラウンドは push・検証まで完了済み（rev 20261123_1000）のため、本ラウンドを開始する。

## 現状
- 可読ログの terminal 印刷は emitLog の描画部の2箇所（差し込み時の Swift.print と追記ループの Swift.print）だけで、発生順に即時印刷している。displayInsertAt による差し込みや pullback の時点で、terminal の並びは battle.log（= displayLog の書き出し）と既にずれ得る（描画部のコメントにも「ターミナルへのライブ出力は発生順のまま」と明記）。
- battle.log ファイル自体は emitLog のたびに displayLog 全文で書き直されるため、正本としての displayLog は常に最新。

## 確定境界の決め方（確定事項2への回答）
印刷済み行数を displayPrintedCount とし、非最終時の確定上限を
「displayLog 内の最後の『Turn 』見出しの位置（インデックス）」とする。見出しが無ければ 0（ヘッダーも印刷しない）。最終アーカイブ時は全行。

根拠（実在機構の到達範囲をコードで確認）:
- displayInsertAt の差し込み: 走査は『Turn 』見出しで止まり、遡行は最大60行。現在の区間（最後の見出し以降）しか触らない。
- pullBackSwitchBlock の表示側: 収集は最後の『Turn 』見出しより後ろからのみ。挿入先は（最後の見出し＋1）か末尾。プロセスプレート側の確定時引き戻し（5177行）も同じ到達範囲。
- ターン行ガード: 新しいターン行を出す直前に、その時点で最後の区間（＝閉じようとしている区間）を書き換える。見出しが displayLog に載った後は、その区間へ到達する機構は無い（次のガードは新しい最後の区間だけを対象にする）。
- pendingTurnDisplay: 『Turn 』見出しは、そのターンの最初の出来事の描画と一緒に載る。境界が進むのは見出しが載った時点であり、それは前区間が閉じた時点と一致する。
- ヘッダー（Turn 1 より前の行）: 『Turn 1』見出しが載るまで印刷されない（確定事項3で許容済み）。

## 実装形
- 印刷管理を新設する: displayPrintedCount、confirmedDisplayCount(isFinal:)、takeDisplayPrintLines(isFinal:)（印刷すべき行を返しカウンタを進める）、flushDisplayPrint(isFinal:)（Swift.print で出す）。
- 呼び出し: (1) emitLog 描画部の末尾で、従来の2箇所の即時印刷を flushDisplayPrint() に置き換える（displayLog への挿入・追記の後）。(2) archiveCurrentBattle(final: true) で flushDisplayPrint(isFinal: true) を呼び、未印刷分を全て出す。(3) resetLogState で displayPrintedCount を 0 に戻す。
- limitTerminalOutput の現行の振る舞い（可読ログ以外を通さない）は維持する。印刷管理の内部では従来どおり Swift.print を直接使う。

## 保証の限界（確定事項の扱いに従い、追加策は広げない）
- 2ターン以上遅れた交代の引き戻し等、境界を超えた遅延登録が起きれば印刷済み範囲と battle.log がずれる可能性がある（ユーザーは承知のうえで案2を選択）。
- 追加で1件、同じ限界として報告する: 特性判明によるフォルム訂正（correctForme 相当、6095行付近）は displayLog の全行を対象に種族名を書き換える。到達範囲が全行のため境界に組み込めず、これが印刷済みの行へ及べば名前だけがずれる（並びは崩れない）。発生条件は、相手の同名フォルムを取り違えて記録し、後から特性判明で訂正される場合。対策は加えず、発生したら報告して判断を仰ぐ。

## 検証の物差し
- ハーネス T162 を新設する: 任意の時点で、印刷済み出力がその時点の displayLog の接頭辞であること／最終フラッシュで全文が一致すること／差し込み（急所表示の割り込み相当）の再現で順序が崩れないこと／pullback の再現で接頭辞が保たれること／印刷カウンタが後退しないこと。
- ゲート: check_reader、ハーネス全通過、run_all 全通過。push は対戦中でないタイミングで行い、push 後はリポジトリの実 rev で blob 一致を検証する。push 完了をもって出荷完了とし、実戦での一致確認は次の実戦ログ到着時に行う。

## 完了記録（2026-11-23、reader build 20261123_1007、rev 20261123_1011、blob 検証済み）
- 実装は計画どおり: confirmedDisplayCount(isFinal:) / takeDisplayPrintLines(isFinal:) / flushDisplayPrint(isFinal:) と displayPrintedCount を新設し、emitLog 描画部の即時印刷2箇所を flushDisplayPrint() に置換、archiveCurrentBattle(final: true) で全量フラッシュ、resetLogState でカウンタを 0 に戻す。
- 検証: ハーネス T162a–e（境界・差し込み・pullback・最終一致・カウンタ後退なし）含め全件合格、check_reader 合格、run_all 全合格。
- 実戦での一致確認は次の実戦ログ到着時に行う（出荷は push 完了をもって完了）。
