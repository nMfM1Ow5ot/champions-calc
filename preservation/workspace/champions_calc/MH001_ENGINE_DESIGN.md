# MH-001 型推定エンジン側 置き換え設計（estimate_engine.mjs）

作成: 2026-11-24（型推定エンジンチャット）。状態: 設計確定・実装は総合からの「ダメージ計算チャットの push 完了」連絡待ち。
前提: core.mjs の固定契約（convolveHitRolls / damageDistribution / damageRolls の新形）はダメージ計算チャットが実装する。本書は利用側（推定）の置き換え設計のみ。

## §3 調査結果の検証（異議なし）

現行コードで全件を確認した。対象行: inf 235/259、ベイズ相手側 1152/1174、自分側 1207/1233、candRanges 1745。
補足2件（異議ではない）:
- candRanges は moveSpec 無しの場合、入れ子配列で meanPct が NaN になり exp も壊れる（§3 の「exp は偶然正しい」は moveSpec 有りの場合）。
- inf の自分側（259）も到達可能性が同じ仕組みで誤る（§3 の記載どおり）。

## 重大な補足: inf 側の multihit ゲート（範囲の確認事項）

- processDamageInf の冒頭（176行）には `md.multihit` を対象外とするゲートがあり、ヒット数が複数ある技はすべてここで落ちる。落ちたイベントは pendingOpts が null のままとなり、processDamageBayes も冒頭で無言で戻る（UI は optsOverride を渡していないことを ui.html 3572/3580 で確認）。
- 実測: 主要な複数ヒット技18種すべてで moveData().multihit が設定されていた（@smogon/calc のデータ）。つまり現行の本番経路では、複数ヒット技のダメージ証拠は両エンジンに一切届いていない。
- したがって §3 のベイズ／inf の誤判定は現時点では「潜在的」（ゲートが外れるか、sim のように bayesApply を直接叩く経路でのみ顕在化）であり、candRanges の誤りだけが実働している。
- 委任の assumedHits 要件（推論ログの trig への記録）は、複数ヒット技の証拠が処理される前提でなければ意味を持たない。よって本実装の範囲には「ゲートの md.multihit 項の解除」を含むと読むのが自然であり、総合へ確認を求めた（2026-11-24）。解除する場合は Status / fixedDamage / INF_BLACKLIST のゲートは残し、multihit 項だけを外す。質量計算が入ることで、ゲートが存在した理由（分布を表現できない）は消える。
- この確認が済むまでは実装に着手しない（前提の解釈が2通りに分かれる箇所は着手前に確定させる、という実装マニュアルの規律による）。

## T05・単発不変の事前検証（実施済み）

- Part A: convolveHitRolls([[10,11,12,13],[10,11,12,13]]) → values [20..26]、counts [1,2,3,4,3,2,1]、total 16、mass(23) = 0.25 を実測で確認（PASS）。
- Part B: 固定場面（Garchomp の Rock Slide 実数観測 + Venusaur の Earth Power 割合観測）の事後分布と trig のハッシュを prefix（修正前）で記録: 688c01d9a1bfc2d9a58b564c046756b02a96e7c2e3ebd6b2638f998232e8c4f0。現行プロジェクト（新 core + 現行 engine）でも同一ハッシュが再現され、core 側の単発等価性は事前に確認できた。スクリプトは /tmp/check_mh001.mjs（SRC_DIR 切替式）。

## 設計の確定事項

### 論点1: 統一ヘルパー dmgDist
- 内部ヘルパー `dmgDist(atkSpec, defSpec, moveName, opts)` を1つ置き、core の `damageDistribution` を呼んで統一形に正規化する。
  - 攻撃技 → { values, counts, total, min, max, hits, multi }
  - { error } / { status } → null（分布なし。従来どおり証拠を保留する）
  - { immune } → 退化分布 { values:[0], counts:[1], total:1, min:0, max:0, hits:1, multi:false } に変換する
- 賛成（immune の退化分布化）: 現行の rolls:[0] の挙動を全経路でバイト等価に再現できる（尤度0、max=0 の over 判定、inf の到達不可、candRanges の 0% 幅）。
- 反対: 無効のダメージイベントは実戦では発生しない（HP が減らないため reader がイベント化しない）はずで、保留でも実害はない。
- 結論: 退化分布化を採る。「単発は従来と完全一致」という検収条件を端部まで守るため。

### 論点2: bayesApply への渡し方（質量 ×16）
- 各候補の尤度は確率質量 p（0〜1）で計算し、`bayesApply(ent, counts)` には counts = p × 16 を渡す。
- 賛成: bayesApply 本体・critPatch の保存形式（counts と係数の割り戻し）・公開 API applyCounts の契約がすべて不変。単発では p = 件数/16 が二進浮動小数で厳密（16 は2の冪）であり、(p×16)/16 = p の算術は従来の 件数/16 とビット同一になる。
- 反対: 「counts」という名前と中身（非整数があり得る）の意味がずれる。
- 結論: 採用する。ヘルパーと受け渡し箇所に「尤度×16（単発では従来の件数と一致）」と明記して意味のずれを文書化する。§7 の「他の尤度モデルを変更しない」「無関係なリファクタリング禁止」にも適合する最小差分である。

### 論点3: over / under 判定
- over（相手側）: 全候補に分布があり、かつ obsMin > 各候補の dist.max のときに限り成立。分布が無い候補が1件でもあれば不成立（現行の rolls.length 偽 → over=false と等価）。
- under（自分側）: 全候補について、分布の全値 v に対する floor(v / hp × 100) の最小値より ev.pct が小さいときに成立。分布が無い候補があれば不成立（現行と等価）。KO ガード（とどめでは方向判定をしない）は現行どおり維持する。

### 論点4: pctCounts（自分側ベイズ）の質量版
- 現行の「round / floor の両対応で pct に一致するロールの件数」を、「一致する値の質量の合計 ×16」に置き換える。両対応の規約はそのまま維持する。

### 論点5: inf 経路の到達可能性
- `rolls.some(pred)` を「counts[j] > 0 かつ pred(values[j]) を満たす j の存在」に置き換える（分布の全値は counts ≥ 1 で構成されるため、実質 values に対する述語）。
- 自分側 inf の `if (!rolls.length) continue` は「分布なし → continue」に置き換える。述語内の r > 0 条件はそのまま値に適用する。

### 論点6: candRanges
- damageRolls から damageDistribution（dmgDist）へ置き換える。分布なし（status / error）は現行どおりスキップ。
- lo = min / defHp × 100、hi = max / defHp × 100（現行の rolls の min/max と同一）。
- exp = Σ(values × counts) / total を質量加重平均として計算（単発では16本の平均と整数演算で一致）。
- koPct = 現在 HP 以上の値の質量合計 × 100（単発では該当ロール件数/16 と一致）。

### 論点7: assumedHits の記録
- 条件: 分布が multi（または hits > 1）で、かつ moveData の spec が kind:'hits'（可変ヒット）で、かつ opts.moveSpec が無い場合に、ベイズ側 damage の trig に `assumedHits: dist.hits` を記録する。
- 固定ヒット数の複数ヒット技（spec が無いもの）は「想定」ではないため記録しない。crit 再評価でも同じ trig が使われるため、capture 経路でも一貫する。
- inf 側の記録形式には trig が無いため、記録はベイズ側の対になる記録に寄せる。

### 論点8: ハーネスの追随（最小限）
- bayes_sim.mjs: 現行でも null ガードの短絡で落ちはしないが、複数ヒット技がプールから無言で消える。利用可否チェック（126行）と観測生成（220/238行）は、rolls が null のとき dist の値と質量で代替する（観測 amt は質量で重み付け抽選、候補の件数は質量×16）。エンジン本体と同じ数え方を sim 側でも保ち、物差しの意味を変えない。
- vgc_doubles_sim.mjs: 181-182行は rolls が null のとき dist の質量で重み付け抽選した値を返すよう最小限追随する。
- bayes_eval.mjs: 114/130行を確認し、同様に落ちない形へ最小限追随する（run_all のゲート対象でなくても、壊れたまま残さない）。
- bayes_equiv.mjs: 単発技のみ使用しており変更不要。golden の再記録も不要（単発不変のため差分ゼロのはずであり、差分が出たら実装ミスとして扱う）。

## T05 の検証準備
- 構成要素の検証: convolveHitRolls([[10,11,12,13],[10,11,12,13]]) は合計値 23 に counts 4 / total 16 = 質量 0.25 を与える（手計算で確認済み）。これを「T01 の分布で観測23 → 質量25%」の形の単体確認として使う。
- エンジン側の検証: 複数ヒット技の実場面で processDamageInf → processDamageBayes を通し、(a) 真の候補が排除されない（事後確率 > 0、係数が max(質量, BAYES_FLOOR)）、(b) trig に reason が付かず applied になる、(c) moveSpec 無しの可変ヒットでは assumedHits が記録される、を確認するスクリプトを /tmp/check_mh001.mjs に用意する。
- 単発不変の検証: 修正前スナップショット（~/workspace/mh001_prefix/ の core.mjs + estimate_engine.mjs）で固定場面（相手攻撃 amt 観測＋自分攻撃 pct 観測）の事後分布と trig を記録し、修正後に同一場面を再実行して完全一致を比較する。同一スクリプトを SRC_DIR 切替で両方に使う。

## 契約の実物確認（2026-11-24、rev 20261124_1051 push 後）

- リポジトリ実 rev 20261124_1051 と、core.mjs / bundle.mjs の repo＝local 一致を型推定側でも検証した。
- damageDistribution の実シグネチャは設計前提と一致: 攻撃技 { dist:{values,counts,total}, min, max, hits, multi }（単発は multi:false・hits:1 で total=16、質量=件数/16）、{ status:true } / { immune:true } / { error }。opts.moveSpec は buildMove へ渡される。
- convolveHitRolls は values 昇順ソート済み。dmgDist の正規化はこの形をそのまま使える。設計はこれで最終確定とする。
- 残る着手条件は (1) ゲートの multihit 項の解除可否（ユーザーの判断待ち、総合経由で連絡が来る）だけである。

## 実施手順（push 完了連絡の後）
1. edit_lock claim（estimate_engine.mjs、必要なら tests/ のハーネス）。
2. estimate_engine.mjs の置き換え実装（import に damageDistribution を追加）。
3. ハーネス追随（bayes_sim / vgc_doubles_sim / bayes_eval）。
4. /tmp/check_mh001.mjs で T05 形と assumedHits を確認。単発不変を prefix と比較。
5. bundle.mjs 再構築（core + estimate_engine の export を含む従来のエントリで）。
6. bash tests/run_all.sh 全件 PASS（bayes_equiv の golden 差分ゼロを含む）。
7. push_update.py（--as 32274233）→ リポジトリ実 rev で検証 → 連絡チャットへ1行通知 → 総合へ完了報告（rev、変更ファイル、テスト結果、単発不変の確認方法）。
