#!/bin/bash
# 使用率データとチャンピオンズ実装リストを最新化する。
# レギュレーション変更時: data/regulation.json の "rule" を新しいルール番号に書き換えてから実行する。
# (シーズンとレギュレーション名は pokedb のページから自動検出される)
cd "$(dirname "$0")"
node fetch_usage.mjs && node fetch_champions_dex.mjs && echo "データを更新しました。ブラウザで UI を再読み込みしてください。"
