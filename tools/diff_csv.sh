#!/bin/bash
# CSV diff ツール: 帳簿出力の比較
# Usage: ./tools/diff_csv.sh <file1.csv> <file2.csv>

set -euo pipefail

if [ $# -ne 2 ]; then
    echo "Usage: $0 <baseline.csv> <current.csv>"
    echo "  帳簿 CSV 出力を比較し、差分を表示します"
    exit 2
fi

FILE1="$1"
FILE2="$2"

if [ ! -f "$FILE1" ]; then echo "Error: $FILE1 が見つかりません"; exit 2; fi
if [ ! -f "$FILE2" ]; then echo "Error: $FILE2 が見つかりません"; exit 2; fi

echo "=== CSV Diff ==="
echo "Baseline: $FILE1"
echo "Current:  $FILE2"
echo ""

# ヘッダー比較
HEAD1=$(head -1 "$FILE1")
HEAD2=$(head -1 "$FILE2")
if [ "$HEAD1" != "$HEAD2" ]; then
    echo "⚠️  ヘッダーが異なります:"
    echo "  Baseline: $HEAD1"
    echo "  Current:  $HEAD2"
    echo ""
fi

# 行数比較
LINES1=$(wc -l < "$FILE1" | tr -d ' ')
LINES2=$(wc -l < "$FILE2" | tr -d ' ')
echo "行数: Baseline=$LINES1, Current=$LINES2"

# ソートして差分比較
DIFF_OUTPUT=$(diff <(sort "$FILE1") <(sort "$FILE2") || true)

if [ -z "$DIFF_OUTPUT" ]; then
    echo "✅ 一致: 差分なし"
    exit 0
else
    echo "❌ 差分あり:"
    echo "$DIFF_OUTPUT"
    exit 1
fi
