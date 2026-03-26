#!/bin/bash
# ProjectProfit Agent Team 実行スクリプト
# 使用方法: ./run_agent.sh <week> <role>
# 例: ./run_agent.sh 1 plan
#     ./run_agent.sh 1 impl_domain
#     ./run_agent.sh 1 review

set -e

WEEK=$1
ROLE=$2
MODEL="claude-opus-4-6"
REPO_DIR="$(pwd)"
PROMPT_DIR="${REPO_DIR}/prompts"

if [ -z "$WEEK" ] || [ -z "$ROLE" ]; then
    echo "使用方法: ./run_agent.sh <week_number> <role>"
    echo ""
    echo "Roles:"
    echo "  plan           - 計画 Agent（Architect）"
    echo "  impl_domain    - 実装 Agent（Domain）"
    echo "  impl_infra     - 実装 Agent（Infrastructure）"
    echo "  impl_tax       - 実装 Agent（Tax Domain）"
    echo "  impl_pipeline  - 実装 Agent（Evidence Pipeline）"
    echo "  impl_posting   - 実装 Agent（Posting）"
    echo "  impl_books     - 実装 Agent（Books）"
    echo "  impl_automation- 実装 Agent（Automation）"
    echo "  impl_vat       - 実装 Agent（VAT）"
    echo "  impl_form      - 実装 Agent（Form Engine）"
    echo "  impl_ui        - 実装 Agent（UI）"
    echo "  impl_export    - 実装 Agent（Export/Import）"
    echo "  impl_test      - 実装 Agent（Test）"
    echo "  impl_qa        - 実装 Agent（QA Integration）"
    echo "  impl_fix       - 実装 Agent（Bug Fix）"
    echo "  review         - レビュー Agent"
    echo ""
    echo "例:"
    echo "  ./run_agent.sh 1 plan"
    echo "  ./run_agent.sh 4 impl_tax"
    echo "  ./run_agent.sh 12 review"
    exit 1
fi

WEEK_PADDED=$(printf "%02d" $WEEK)
PROMPT_FILE="${PROMPT_DIR}/week${WEEK_PADDED}/w${WEEK}_${ROLE}_agent.md"

if [ ! -f "$PROMPT_FILE" ]; then
    echo "エラー: プロンプトファイルが見つかりません: ${PROMPT_FILE}"
    echo "先に prompts/week${WEEK_PADDED}/ ディレクトリにプロンプトを作成してください"
    exit 1
fi

echo "============================================"
echo " ProjectProfit Agent Team Runner"
echo "============================================"
echo " Week:    ${WEEK}"
echo " Role:    ${ROLE}"
echo " Model:   ${MODEL}"
echo " Prompt:  ${PROMPT_FILE}"
echo "============================================"
echo ""

# 前提ファイルの存在確認
if [ ! -f "GOLDEN_RULES.md" ]; then
    echo "警告: GOLDEN_RULES.md が見つかりません。リポジトリルートに配置してください。"
fi

if [ $WEEK -gt 1 ]; then
    PREV_WEEK=$((WEEK - 1))
    HANDOFF="WEEK_${PREV_WEEK}_HANDOFF.md"
    if [ ! -f "$HANDOFF" ]; then
        echo "警告: ${HANDOFF} が見つかりません。前週のレビューが完了しているか確認してください。"
    fi
fi

# Agent 起動メッセージの構築
START_MSG="以下の手順で作業を開始してください：
1. GOLDEN_RULES.md を読む"

if [ $WEEK -gt 1 ]; then
    START_MSG="${START_MSG}
2. WEEK_$((WEEK - 1))_HANDOFF.md を読む
3. REVIEW_W$((WEEK - 1)).md の未対応指摘を確認"
fi

START_MSG="${START_MSG}
最後に、プロンプトで指定された全タスクを実行してください。"

# Claude Code で実行
echo "Agent を起動します..."
echo ""

claude --model "$MODEL" \
    --system-prompt "$(cat "$PROMPT_FILE")" \
    "$START_MSG"
