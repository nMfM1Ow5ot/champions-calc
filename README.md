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

## state.json の形式 (Mac側プログラム → UI)
```json
{
  "mine": [
    {"species": "Garchomp", "mega": true, "curHPPercent": 78, "boosts": {"spa": 1}},
    {"species": "Incineroar", "curHPPercent": 100}
  ],
  "oppTeam": ["Garchomp", "Incineroar", "Rillaboom", "Volcarona", "Greninja", "Kingambit"],
  "opps": [
    {"species": "Garchomp", "curHPPercent": 62, "status": "tox", "revealed": {"moves": ["じだんだ"], "item": "こだわりスカーフ", "ability": "すながくれ"}},
    {"species": "Rillaboom", "curHPPercent": 100}
  ],
  "field": {"weather": "Rain", "terrain": "Grassy", "tailwindMine": false, "tailwindOpp": true}
}
```
- species は英語名 (Showdown表記) が基本。日本語名でもよい (UI側で解決する)。
- `oppTeam` は相手の6体。相手パネルのアイコン列に表示され、クリックで計算相手を切り替える。reader.swift は対戦中にプレートで読み取れた相手種族を登場順に自動で蓄積して書き込む (見せ合い画面には名前テキストが無いため、対戦開始直後は場の2体から埋まっていく)。
- 相手の型はデフォルトで pokedb の使用率トップ型 (`usage`)。`setKind` で attacker / bulky / none / custom も指定可。
- `revealed` は対戦画面で判明した情報 (技・持ち物・特性、日本語名可)。想定型の該当項目だけが実測値に差し替わり、パネルに「判明情報で訂正済み」と表示される。手動で直した項目も state.json の更新で保持される。
- 自分側は登録済み構築 (TEAM_PRESETS) に一致する種族のみ自動反映される。

## 検証
- `node test_core.mjs` — 実数値の再現チェック (全ケース一致が正)
- `node test_matchup.mjs` — サンプル対面の計算
