# ポケモンチャンピオンズ 自動ダメージ計算アプリ

構成:
- `core.mjs` — 計算コア (@smogon/calc gen9 / IV31 / Lv50 / EV = SP×8 でChampions実数値を再現)
- `ui.html` — 計算UI (自分の2体×相手2体、ダブルス)。`start_ui.sh` で起動し http://localhost:8765/ui.html を開く
- `data/names_ja.json` — 日本語名辞書 (PokeAPIから生成。`fetch_names.mjs` → `build_names.mjs`)
- `reader.swift` — Mac側キャプチャプログラム: QuickTime PlayerのiPad画面を0.5秒ごとに取り込み、観測した出来事を Showdown 形式のバトルログ (`battle.log`、ターミナル表示もこれのみ) に起こし、ログ由来の状態を `state.json` に書く。プレート差分から |switch|/|-damage|/|-heal|/|faint|、ゲーム内「ログを見る」画面から |move|/|-status|/|-item|/|-ability| 等を取り込む。
  UIは2.5秒ごとに `state.json` を確認し、変化があれば自動で反映する。
- `fetch_usage.mjs` — pokedb (champs.pokedb.tokyo, rule=1) から使用率データを取得し、`data/usage_sets.json` (各種族の「最も使用されている型」) と `data/items_ja.json` を生成する。ページは `data/pokedb_cache/` にキャッシュされる。再生成は `node fetch_usage.mjs` (シーズンが変わったら再実行)。

## Macでの使い方
1. このフォルダ一式をMacにコピーする。
2. UI: `./start_ui.sh` を実行し、ブラウザで http://localhost:8765/ui.html を開く。
3. リーダー: QuickTime PlayerでiPad画面を表示した状態で `./run_reader.sh` を実行する。
   初回は「画面収録」の許可が必要です (システム設定 > プライバシーとセキュリティ > 画面収録 で、ターミナルを許可)。
4. テストだけなら `./run_reader.sh --image 対戦スクショ.png --once` で保存済み画像から読み取りを試せる。
   (Xcode Command Line Tools が必要です。無ければ `xcode-select --install` 。)

## 自チームの登録 (チーム確認画面 + UIの撮影ボタン)
1. リーダーを通常モードで起動しておく (`./run_reader.sh`)。撮影ボタン用に localhost:8899 で待受ける。
2. ゲーム側でチーム確認画面 (6体がカードで並ぶ画面) を QuickTime に映し、**能力タブ** を表示して
   UI 上部の「能力画面を撮影」ボタンを押す。続けて **ステータスタブ** に切り替えて「ステータス画面を撮影」ボタンを押す。
3. 6体分の技・特性・持ち物・能力値 (+SP) が `my_team.json` に記録され、UI に即反映される。
   能力値から SP・性格を逆算して登録する (ステータス画面の SP 表示とも照合する)。メガストーンを持っていればメガ形態も自動で用意される。
   登録は `my_team.json` に残るので次回からは不要。チームを組み替えたら同じ手順で上書きできる。
- 画像でのテスト: `./run_reader.sh --team-screen ability --image 能力画面.png` / `--team-screen status`。
- 対戦中の「様子を見る」から1体ずつ登録する方式 (`./run_reader.sh --team`) も残してある (左のパーティ一覧の選択中ハイライトで個体を特定する)。

## データの更新 (レギュレーション変更への追従)

- 現在のレギュレーション/シーズンは `data/regulation.json` で管理し、UI の注記にも反映される。
- `bash update_data.sh` (要 Node.js、`npm install` 済みのこと) で `fetch_usage.mjs` (pokedb 使用率トップ型) と `fetch_champions_dex.mjs` (Serebii の Champions 実装済みリスト: 種族368/アイテム165/技870) を再生成する。シーズンとレギュレーション名は pokedb の一覧ページから自動検出される。
- レギュレーション自体が変わったら、`data/regulation.json` の `rule` を pokedb の新しいルール番号に書き換えてから実行する。
- UI の種族/持ち物/技の候補は `data/champions_dex.json` でフィルタされる (直接入力すれば候補外でも計算データにあるものは使える)。

## state.json の仕様 (Mac側プログラム → UI)

### 原則
- state.json に入れるのは「対戦画面から知りうる情報」だけ。相手の正確なHP実数など、画面で知りえないものは入れない (HPはプレート表示のパーセントのみ)。
- 推定値 (相手の想定型など) は UI 側でのみ扱い、state.json には混ぜない。state.json の値はすべて画面からの観測と、観測した出来事からルールで導ける事実 (残りターン数など) のみ。
- 出しうるキーの正本は reader.swift 内のスキーマ定義 (`stateTopKeys` 等)。実際に生成した state.json のキーがスキーマの範囲内であることを検証ハーネスで機械チェックしている。

### スキーマ概要
```json
{
  "mine":  [ {モンスター}, ... ],   // 自分の場の2体 (無ければ空)
  "opps":  [ {モンスター}, ... ],   // 相手の場の2体
  "oppTeam": ["Sneasler", ...],      // 相手の選出 (判明した順)
  "oppRevealed": { "Sneasler": {"moves": [...], "item": "...", "ability": "..."} },
  "oppTrainer": "相手の名前",
  "events": [ {"k": "mv", "turn": 3, "label": "p2a: Sneasler", "move": "Fake Out"}, ... ],
  "field": {"terrain": "Psychic", "weather": "Rain", "terrainTurnsLeft": 3, "weatherTurnsLeft": 4, "trickRoomTurnsLeft": 2},
  "sideConditions": { "p1": {"Tailwind": 2}, "p2": {"Reflect": 4} }
}
```
- モンスター: `species` (英語名・Showdown表記), `curHPPercent`, `status` (任意), `boosts`, `mega`/`megaSpecies` (任意), `unburden`/`itemLost` (任意), 相手のみ `revealed` {moves/item/ability} (任意)。
- `boosts` は常時7能力すべてをそろえて出す: `{"atk":0,"def":0,"spa":0,"spd":0,"spe":0,"acc":0,"eva":0}` (0も省略しない)。
- `field` の `terrain`/`weather` は常時送る (空文字 = なし)。`terrainTurnsLeft`/`weatherTurnsLeft`/`trickRoomTurnsLeft` は継続中のみ付く追加キーで、残りターン数 (現在のターンを含めてあと何ターン持続するか) を表す。基本継続は天気・フィールド・トリックルームとも5ターンで数え、道具による延長 (岩・ねんど等) は画面から知りえないため数えない。
- `sideConditions` は継続中のサイド状態だけをサイドごとに {状態名(英語): 残りターン} で送る。対象は Reflect / Light Screen / Aurora Veil (5ターン), Tailwind (4ターン), Mist / Safeguard (5ターン)。何も無ければキー自体を出さない。
- `oppTeam` は相手の6体。相手パネルのアイコン列に表示され、クリックで計算相手を切り替える。reader.swift は見せ合い画面の画像識別で書き込み、対戦中にプレートで読み取れた相手種族も登場順に蓄積する。
- 相手の型はデフォルトで pokedb の使用率トップ型 (`usage`)。`setKind` で attacker / bulky / none / custom も指定可 (これは UI 側の想定であり state.json には含まれない)。
- `revealed` / `oppRevealed` は対戦画面で判明した情報 (技・持ち物・特性、日本語名可)。想定型の該当項目だけが実測値に差し替わり、パネルに「判明情報で訂正済み」と表示される。手動で直した項目も state.json の更新で保持される。
- 自分側は登録済み構築 (TEAM_PRESETS) に一致する種族のみ自動反映される。

## 検証
- `node test_core.mjs` — 実数値の再現チェック (全ケース一致が正)
- `node test_matchup.mjs` — サンプル対面の計算
