#!/bin/bash
# Champions 対戦画面リーダーを起動する (Mac用)
# 初回は「画面収録」の許可ダイアログが出たら許可してください (ターミナルに対して許可)。
cd "$(dirname "$0")"
# OBS launch is gated until separate live/full-reader approval. QuickTime remains default.
OBS_MODE=0
PREV=""
for ARG in "$@"; do
  if [ "$PREV" = "--capture" ] && [ "$ARG" = "obs" ]; then OBS_MODE=1; fi
  PREV="$ARG"
done
if [ "$OBS_MODE" -eq 1 ]; then
  if [ "${CHAMPIONS_OBS_LIVE_APPROVED:-0}" != 1 ]; then
    echo "STOP: OBS full-reader execution requires separate approval. Use the isolated camera probe first." >&2
    exit 2
  fi
  OBS_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/champions-obs-app.XXXXXX") || exit 2
  chmod 700 "$OBS_ROOT" || exit 2
  OBS_APP="$OBS_ROOT/ChampionsOBSResearch.app"
  OBS_PLIST="research/preview/bridge/obs/OBSInfo.plist"
  trap 'rm -rf -- "$OBS_ROOT"' EXIT
  prepare_obs() {
    # This research launcher must not silently compile a synced production reader.
    [ "$(git hash-object reader.swift)" = "f4ad7d2c750fc3bfc2211602ed5e5c1181688131" ] || return 2
    [ "$(git hash-object "$OBS_PLIST")" = "6fc92ed007144c29b7efcfd775a9d97c8c3d0eaf" ] || return 2
    mkdir -p "$OBS_APP/Contents/MacOS" || return 2
    cp "$OBS_PLIST" "$OBS_APP/Contents/Info.plist" || return 2
    swiftc -swift-version 5 reader.swift -o "$OBS_APP/Contents/MacOS/reader-obs" || return 2
    codesign --force --sign - "$OBS_APP" || return 2
    codesign --verify "$OBS_APP" || return 2
  }
fi
# リーダーが終了コード 42 で抜けたら (新しいリーダーが同期で届いた合図)、
# そのまま新しい版で再起動する。
# それ以外の異常終了 (クラッシュ等) でも自動で再起動し、復旧を待つ。
# ただし起動直後に落ち続ける場合は無限ループを避けるため 5 回で諦める。
# Ctrl+C (130) と正常終了 (0) はそのまま終わる
CRASHES=0
while true; do
  START=$(date +%s)
  if [ "$OBS_MODE" -eq 1 ]; then
    prepare_obs || exit 2
    "$OBS_APP/Contents/MacOS/reader-obs" "$@"
  else
    swift reader.swift "$@"
  fi
  code=$?
  if [ $code -eq 42 ]; then
    echo "リーダーを再起動します"
    CRASHES=0
    continue
  fi
  if [ $code -eq 0 ] || [ $code -eq 130 ]; then exit $code; fi
  NOW=$(date +%s)
  if [ $((NOW - START)) -lt 5 ]; then
    CRASHES=$((CRASHES + 1))
  else
    CRASHES=1
  fi
  if [ $CRASHES -ge 5 ]; then
    echo "リーダーが起動直後に繰り返し終了するため、自動再起動を中止します (コード: $code)"
    exit $code
  fi
  echo "リーダーが予期せず終了しました (コード: $code)。2 秒後に再起動します"
  sleep 2
done
