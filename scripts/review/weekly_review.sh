#!/bin/bash
# 報告の週 1 回判定（launchd com.kureho.adblockkeshi-review-packet・毎週月曜 06:30）
#   1. 判定用の束を作る（本体のチェックアウトの build_review_packet.py・Claude なし・D1 は読み取りのみ）
#   2. 未判定があれば Claude が判定し、関門を通ったものだけ main に載せる（このファイルと同じ版の auto_judge.py）
# launchd はこのファイルを .review-packets/.tools-wt（origin/main と同じ中身・plist が毎回最新にする）から呼ぶ。
# 束の作成が失敗しても 2 は呼ぶ（auto_judge.py が「今日の束が無い」を失敗として記録し、朝のレポートに出る）
set -u
SRC="$(cd "$(dirname "$0")/../.." && pwd)"
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
REPO="$(dirname "$(git -C "$SRC" rev-parse --path-format=absolute --git-common-dir)")"
PY=/opt/homebrew/bin/python3

echo "[$(date '+%F %T')] 週 1 回判定を開始（scripts=$(git -C "$SRC" rev-parse --short HEAD)）"
"$PY" -B "$REPO/scripts/review/build_review_packet.py"
"$PY" -B "$SRC/scripts/review/auto_judge.py"
