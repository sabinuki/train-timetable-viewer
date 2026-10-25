#!/bin/bash
# テキスト形式の時刻表を、アプリで読み込める JSON に変換する。書式は scripts/README.md を参照
# 使い方: scripts/make-timetable.sh <入力.txt> [-o <出力.json>]
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
swift build --package-path "$ROOT/Packages/TimetableCore" --product timetable-convert -c release --quiet
exec "$(swift build --package-path "$ROOT/Packages/TimetableCore" -c release --show-bin-path)/timetable-convert" "$@"
