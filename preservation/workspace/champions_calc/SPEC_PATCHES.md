# 仕様差分 (バランス調整) の登録手順

Champions のバランス調整 (種族値・技性能・タイプ相性など、データで表せる
変更) に対応するための仕組みのうち、データ側の手順書です。計算側は
core.mjs の差分レイヤー (setSpecPatchData / applySpecPatch、ダメージ計算
チャットの管轄) が担い、推定エンジンは core 経由で同じ差分が効きます。

## ファイル構成

- `data/spec_patches.json` (同期対象): 差分の登録ファイル。
  - `versions`: バージョンの配列 (下記「形式」)。
  - `seasons`: シーズン → そのシーズンの仕様に対応するバージョン id。
    現行仕様のまま (差分なし) のシーズンは `null`。
- `data/regulation.json` の `specPatch` フィールド: 現行シーズンに
  対応するバージョン id (`seasons[season]` と同じ値)。正本は
  `seasons` 側で、fetch_champions_dex.mjs の再生成時に seasons から
  刻まれる (手で編集した場合も、検証で不整合を検出する)。
- 検証: `node tests/check_spec_patches.mjs` (push ゲートにも組み込み
  済み: spec_patches.json / regulation.json の push 時に自動実行)。

## 形式

各バージョンは **素のデータ (現行仕様) に対する差分の完全な集合** です。
前バージョンへの追加差分ではありません (差分レイヤーは適用時に全て
復元してから、選択したバージョンだけを適用します)。新しい調整を
登録するときは、前バージョンの内容を複製してから変更点を足し引き
してください (解除された調整はエントリごと消す。検証が「前バージョン
にあって今回ないエントリ」を警告します)。

```json
{
  "id": "m9-20261202",
  "label": "2026/12/2 調整",
  "season": "M-9",
  "species": {
    "Garchomp": { "baseStats": { "atk": 120 }, "types": ["Ground", "Dragon"] }
  },
  "moves": {
    "Earthquake": { "basePower": 90, "accuracy": 100, "category": "Physical" }
  },
  "types": {
    "Fire": { "Grass": 2 }
  }
}
```

- `id`: `<yyyymmdd>` (適用開始日。`m9-20261202` のようにシーズンの接頭辞を付けてもよい)。
- 名前はすべて @smogon/calc の英語名 (種族・技・タイプ)。解決できない
  名前は差分レイヤーが黙って読み飛ばすため、検証でエラーにしています。
- `species` の差分: `baseStats` (hp/atk/def/spa/spd/spe の部分指定可)、
  `types` (1-2 個)、`abilities` ({0/1/H: 特性名}) など、calc の種族
  オブジェクトのプロパティをそのまま書けます。
- `moves` の差分: `basePower`、`accuracy` (1-100、必中は true)、
  `type`、`category` (Physical/Special/Status)、`priority`、`target`、
  `pp` など。
- `types` の差分: 攻撃タイプ → 防御タイプ → 倍率。
- **対象外**: 特性や道具の「効果そのもの」の変更は calc 内部のコード
  依存のため、このデータ層では扱えません (該当する調整が来たら
  ダメージ計算チャット側のコード対応が必要です)。素早さまわりの
  効果 (スカーフ・天候加速など) は推定エンジン側にも独自実装がある
  ため、効果変更時は型推定エンジンチャットへも連絡してください。

## 新しい調整が来たときの登録手順

1. `data/spec_patches.json` の `versions` に新しいバージョンを追加
   する (前バージョンを複製し、発表内容との差分だけを変更)。
2. `seasons` に新シーズン → 新バージョン id を登録する。シーズン
   自体が変わる場合は regulation.json の `season` も切り替わる
   (レギュレーション変更は fetch_champions_dex.mjs の再生成手順に
   従う。その際 `specPatch` は seasons から自動で刻まれる)。
3. 検証する: `node tests/check_spec_patches.mjs`
   - ERROR が 0 であること (存在しない名前・範囲外の値は不可)。
   - WARN は内容を確認する (前バージョンからのエントリ欠落 =
     調整の解除として意図どおりか、正規名との表記差など)。
4. push する: `python3 push_update.py data/spec_patches.json data/regulation.json --as <chat-id> --msg "..."`
   (ゲートで検証とセキュリティ確認が自動で走ります)。
5. Mac 側は serve.py の同期で自動取得します (追加の手当ては不要)。
   UI の「仕様」セレクタに新しいバージョンが現れます。利用者の
   選択は端末側に保存されるため、既定で新仕様にしたい場合は
   セレクタで選び直してもらう運用です。

## 初回導入時の注意 (済)

- `data/spec_patches.json` は sync_ui.py の MANIFEST に登録済み
  (2026-11-22)。MANIFEST 自体 (sync_ui.py) は同期対象外のため、
  Mac 側へは ZIP 更新で届きます。
- 導入時点の登録内容: versions は空、seasons は {"M-8": null}
  (現行仕様 = 差分なし)、regulation.json の specPatch は null。
