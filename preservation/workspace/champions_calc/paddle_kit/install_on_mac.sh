#!/bin/bash
# PaddleOCR サイドカー環境の導入 (Mac ローカル専用)。
# 仮想環境とモデルは ~/champions_paddle/ に置き、プロジェクトの
# 同期対象や ZIP には決して含めない。再実行可能 (既にあれば作り直さない)。
set -e
BASE="$HOME/champions_paddle"
VENV="$BASE/.venv"

echo "== PaddleOCR sidecar install =="
echo "base: $BASE"
python3 --version

if [ ! -d "$VENV" ]; then
  python3 -m venv "$VENV"
fi
# shellcheck disable=SC1091
source "$VENV/bin/activate"
python -m pip install --upgrade pip
python -m pip install "paddlepaddle==3.3.1" "paddleocr==3.7.0" "pillow" "numpy"

echo "== fetching models (small + medium) and verifying startup =="
python "$(dirname "$0")/fetch_models.py"

echo "== done =="
echo "venv: $VENV"
