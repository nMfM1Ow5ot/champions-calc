# 手動フラグ化 計画（ローカルのみ・未同期）

委任: 総合チャット（61dc1fd3）から 2026-11-23、ユーザーの明示指示。
分担: バックエンド（本チャット）＝フラグ機構と受け渡し経路の主担当、
ダメージ計算（f7110139）＝UIボタン、監査（706c9700）＝期間限定の監視
（watch cron champions-calc-manual-flag-watch 稼働中）。

## 目的
自動的な試合開始フラグのオンと自動的な試合終了フラグのオンを一時的に
無効化し、ダメ計 UI 上部のボタンでのみフラグをオンにできるようにする。

## 調査で確定した現行経路（reader.swift、build 20261123_0707 時点）
開始側:
- startBattleLog の自動発火 6 か所: (1) 見せ合い同定の確定時、
  (2) processPlates の開始復旧（late_start）、(3) parseLogScreen、
  (4) 相手の繰り出し文、(5) 自分のゆけっ文、(6) emitLog の
  winLogged ガード（次試合の開始）。
- inBattle の自動オン 2 か所: プレート検出時、ログ画面の解釈時。
  自動オフ: プレート消失 30 フレーム超、見せ合い分岐の入口。
終了側:
- winLogged の自動オンは translateBattleMessage の 4 分岐
  （勝敗文、投了文「あきらめた」、無操作終了文×2 形）。
  いずれも |win| 行の出力 → winLogged = true →
  archiveCurrentBattle(final: true) の順。

## 自己議論の結論
1. inBattle の扱い: 「オンの抑止」のみ対象とし、自動オフは残す。
   賛成: 委任文が inBattle の自動オンを対象に挙げている。inBattle は
   見せ合いの再同定やメッセージ監視の前提であり、オンを手動化する
   ことで「試合とみなす」開始も権威ある操作に揃う。オフは終了の
   意味論ではなく認識側の片付けであり、自動のままで害がない。
   反対: 開始押下前はプレート不在フレームのメッセージ監視が止まり、
   冒頭文の取りこぼしが増える。ただしプレートのあるフレームの処理は
   inBattle に依存せず、ユーザーは試合開始時点で押す運用のため実害は
   小さい。結論: オン抑止のみ。
2. 受け渡しの輸送: flag_control.json のファイル監視を採用。
   賛成: serve.py の POST は既存の同型（/calclog、/presets）が
   ファイル保存であり、reader は scriptDir のファイルを既に読む。
   Paddle の spool と同じ実証済みの形。reader 再起動に強く、要求が
   消失しない。
   反対（reader の 8899 HTTP へ転送する案）: reader が落ちていると
   届かず、消失した要求と未達の区別が付かない。却下。
3. モードの既定: flag_control.json が無い場合は manual。
   出荷状態＝手動モード有効という要件に一致し、ファイル消失時も
   安全側（手動）に倒れる。
4. 勝敗文の扱い: |win| 行は従来どおり記録し、winLogged と確定
   アーカイブだけを終了押下まで遅らせる。
   賛成: 行は証拠であり、位置も正しい。終了を押し忘れても安全網の
   下書きに勝敗行が残る。
   反対（行ごと抑止し終了押下時に合成する案）: 合成時点では勝敗の
   帰属情報を再構成できず、証拠性も落ちる。却下。
5. 終了押下時に勝敗文が無い場合: |win| 行なしで final アーカイブ
   する。ユーザーの明示操作が権威であり、備考で補える。

## 受け渡し契約（Step 0 でダメージ計算と確定する案）
- serve.py: POST /flag {"action": "start"|"end"} /
  {"action": "mode", "mode": "auto"|"manual"}、GET /flag。
  応答は {"ok": true, "mode", "startSeq", "endSeq", "started",
  "ended"}（started / ended は state.json の flag から重ねる）。
- flag_control.json（プロジェクトフォルダ、同期対象外）:
  {"mode": "manual", "startSeq": N, "endSeq": M} を serve.py が
  原子的に書く。reader は mtime 監視で取り込む。reader 起動時は
  現在値を取り込み済みとして採用する（古い要求を再生しない）。
- state.json: 全書き出し（対戦形・選出形・リセット形）に
  "flag": {"mode", "started", "ended"} を追加する。
- reader の手動モード意味論:
  - startSeq の増加を取り込んだら、(!logStarted || winLogged) の
    とき startBattleLog() を実行し inBattle = true にする。
  - endSeq の増加を取り込んだら、(logStarted && !winLogged) の
    とき winLogged = true とし archiveCurrentBattle(final: true)
    を実行し inBattle = false にする。
  - 自動発火 6 か所と inBattle の自動オン 2 か所、winLogged の
    自動オン 4 分岐の「オン」部分を manual 時だけ抑止する。
    自動経路のコードは削除せず、manualFlagMode の分岐で囲む。
  - mode = auto では制御ファイルを mode 以外無視し、従来どおり。

## 手順と完了条件
- Step 0: ダメージ計算と契約を確定し、総合へ報告する。
  完了条件: 相手の同意と総合への報告済み。
- Step 1: reader.swift 実装（フラグ抑止＋制御取り込み＋state.json
  の flag）。完了条件: check_reader.sh 通過、ハーネス全通過
  （手動モードの開始・終了・自動復帰のケースを追加）。
- Step 2: serve.py 実装（/flag の GET/POST と制御ファイル書き込み、
  テスト追加）。完了条件: serve.py の関連テスト全通過、run_all 通過。
- Step 3: ZIP を作成しユーザーへ渡す（push はしない）。
  完了条件: ユーザーが実機でボタン開始・終了の実戦ログ到達を確認。
- Step 4: push し、リポジトリの実 rev で検証、連絡・進捗管理へ
  一文で通知、総合へ完了報告。対戦中とみられる時間帯は避ける。

## Step 0 確定（2026-11-23、ダメージ計算と合意・総合へ報告済み）
- state.json: "battlePhase": "idle"|"inBattle" と "flagMode":
  "manual"|"auto" を全書き出しに載せる（UI 側の提案を採用）。
- serve.py: POST /battle_flag {"action": "start"|"end"|"mode"}。
  応答 {"ok", "phase", "mode", "startSeq", "endSeq"}。phase は
  見込み値で、権威は state.json の battlePhase。
- flag_control.json（プロジェクトフォルダ、同期対象外）に serve.py
  が連番つきで記録し、reader が mtime 監視で取り込む。ファイルが
  無い場合は manual。reader 起動時は現在連番を取り込み済みとする。
- 要求は冪等（開始済みの start、未開始の end は reader が無視）。

## Step 1・2 完了記録（2026-11-23）
- reader.swift（build 20261123_0721）: flagManualMode ほか全域変数、
  applyFlagControl / pollFlagControl、自動オンの抑止（開始6か所・
  inBattle 2か所・終了4分岐のフラグと確定アーカイブ）、state.json
  の全書き出しへの battlePhase / flagMode 追加。
  check_reader 通過、ハーネス ALL PASS（T159a–h を追加）。
- serve.py: FLAG_CONTROL_PATH と読み書き・応答のヘルパー、
  POST /battle_flag。tests/test_battle_flag.py（14 件）全通過、
  関連 serve.py テスト群と run_all も全通過（test_upload_resume の
  既知の既存失敗 2 件は従来どおりで本変更と無関係）。
- ZIP: champions_calc_20261123_0727.zip（reader / serve.py は新版、
  ui.html は現行公開版＝ボタンはダメージ計算の実装待ち）。

## 契約の確定（2026-11-23、総合経由でユーザーが判断）
- 報告間の食い違い（当方の最初の案 POST /flag・"flag" オブジェクト
  と、実装済みの統合版 POST /battle_flag・battlePhase / flagMode）
  について、ユーザーが「文字列のまま進める」と判断し、統合版で
  確定した。付け替えは不要。
- UI はダメージ計算が統合版で実装し、rev 20261123_0727 で push
  済み。実機確認は実ボタンでのフルチェーンで行う（ZIP から
  reader.swift と serve.py の両方を差し替える手順に更新）。

## 完了記録（2026-11-23）
- 実機確認の前提は、ユーザーが総合で「実機のテストなしで push
  してよい」と判断したため免除された（監査の固定点も同日修正）。
- 順序: 先行する別件（黒画面待機の無効化、質問・調査からの委任）
  を公開版ベースで push（rev 20261123_0800、build 20261123_0757）
  し、手動フラグをその上に乗せ直した（reader build 20261123_0802）。
- push: reader.swift + serve.py を rev 20261123_0805 で push。
  両 blob のリポジトリ一致を検証済み。ゲートは check_reader、
  ハーネス（T159a–h 含む）、test_battle_flag.py 14 件、run_all
  の全通過。連絡・進捗管理への一文通知済み。edit_lock 解除済み。
- 事後の確認事項: 実戦でボタン開始・終了のログが届くこと
  （ログ分析側で到達時に確認）。

## 実機確認の経路（検討結果）
- 制約: 稼働中の serve.py は公開マニフェストと異なる同期対象
  ファイルを補正する（最大で 10 分に 1 回）。ただし補正はファイル
  を戻すだけで、起動中の reader プロセスには影響しない。serve.py
  自身は補正対象外。ui.html はブラウザが読み込み済みなら補正後も
  開いているページは動き続ける。
- 推奨（reader のみの先行確認）: 通常フォルダの reader.swift だけを
  ZIP の新版に差し替え、reader を再起動する。flag_control.json へ
  直接書き込むことでボタンを模擬する（公開版 serve.py はこの
  ファイルを参照しないため、差し替え前後で本番の挙動は変わらない）。
  試合開始時に startSeq を、勝敗文の表示後に endSeq を書き込み、
  final ログが通常経路で届くことを確認する。
- 代替（テストフォルダで並行起動）: Paddle サイドカーの spool を
  本番 reader と共有するため CHAMPIONS_PADDLE_OFF=1 が必要で、
  8899 番ポートも本番と競合する。推奨しない。
- フルチェーン（実ボタン）確認は、ダメージ計算の ui.html が
  揃ってから、同じ差し替え方式で serve.py と ui.html を加えて行う。
