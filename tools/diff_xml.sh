#!/bin/bash
# XML 正規化 diff ツール: e-Tax XML 出力の比較
# Usage: ./tools/diff_xml.sh <file1.xml> <file2.xml>

set -euo pipefail

if [ $# -ne 2 ]; then
    echo "Usage: $0 <baseline.xml> <current.xml>"
    echo "  e-Tax XML 出力を正規化して比較します"
    exit 2
fi

FILE1="$1"
FILE2="$2"

if [ ! -f "$FILE1" ]; then echo "Error: $FILE1 が見つかりません"; exit 2; fi
if [ ! -f "$FILE2" ]; then echo "Error: $FILE2 が見つかりません"; exit 2; fi

echo "=== XML Diff ==="
echo "Baseline: $FILE1"
echo "Current:  $FILE2"
echo ""

# xmllint で正規化 (利用可能な場合)
if command -v xmllint &> /dev/null; then
    NORM1=$(xmllint --c14n "$FILE1" 2>/dev/null || cat "$FILE1")
    NORM2=$(xmllint --c14n "$FILE2" 2>/dev/null || cat "$FILE2")
else
    echo "⚠️  xmllint が見つかりません。正規化なしで比較します"
    NORM1=$(cat "$FILE1")
    NORM2=$(cat "$FILE2")
fi

DIFF_OUTPUT=$(diff <(echo "$NORM1") <(echo "$NORM2") || true)

if [ -z "$DIFF_OUTPUT" ]; then
    echo "✅ 一致: 差分なし"
    exit 0
else
    echo "❌ 差分あり:"
    echo "$DIFF_OUTPUT"
    exit 1
fi
