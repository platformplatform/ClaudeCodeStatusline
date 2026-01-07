#!/bin/bash

# =============================================================================
# Claude Code Custom Status Line Script
# =============================================================================
# Simple token display from current_usage.
# Note: These values may undercount vs /context by ~15-20%.
# =============================================================================

json_input=$(cat)

# -----------------------------------------------------------------------------
# Workspace / directory
# -----------------------------------------------------------------------------
current_directory=$(echo "$json_input" | jq -r '.workspace.current_dir // .cwd')
directory_name=$(basename "$current_directory")

# -----------------------------------------------------------------------------
# Git branch
# -----------------------------------------------------------------------------
git_branch=""
if git -C "$current_directory" rev-parse --git-dir > /dev/null 2>&1; then
    git_branch=$(git -C "$current_directory" --no-optional-locks rev-parse --abbrev-ref HEAD 2>/dev/null)
fi

# -----------------------------------------------------------------------------
# Model
# -----------------------------------------------------------------------------
model_display_name=$(echo "$json_input" | jq -r '.model.display_name' | sed 's/ context)/)/g')

# -----------------------------------------------------------------------------
# Token counts
# -----------------------------------------------------------------------------
token_details=""
usage=$(echo "$json_input" | jq '.context_window.current_usage')

if [ "$usage" != "null" ]; then
    # Input tokens = uncached + cached
    input_tokens=$(echo "$usage" | jq -r '.input_tokens // 0')
    cache_read=$(echo "$usage" | jq -r '.cache_read_input_tokens // 0')
    cache_creation=$(echo "$usage" | jq -r '.cache_creation_input_tokens // 0')
    total_input=$((input_tokens + cache_read + cache_creation))

    # Cumulative session output
    session_output=$(echo "$json_input" | jq -r '.context_window.total_output_tokens // 0')

    # Format
    input_k=$((total_input / 1000))
    output_k=$((session_output / 1000))
    token_details="📥 ${input_k}k 📤 ${output_k}k"
fi

# -----------------------------------------------------------------------------
# ccusage-based cost info
# -----------------------------------------------------------------------------
ccusage_output=$(echo "$json_input" | ccusage statusline --no-offline --cost-source cc --no-cache 2>/dev/null)

session_cost=$(echo "$ccusage_output" | sed -n 's/.*\$\([0-9.]*\) session.*/💰 $\1 session/p')
block_time=$(echo "$ccusage_output" | sed -n 's/.*\$[0-9.]* block (\([^)]*\) left).*/⏰️ New block in \1/p')
daily_cost=$(echo "$ccusage_output" | sed -n 's/.*\$\([0-9.]*\) today.*/📅 $\1 today/p')

# -----------------------------------------------------------------------------
# Build final output
# -----------------------------------------------------------------------------
output="📁 $directory_name"

[ -n "$git_branch" ] && output="$output | 🌿 $git_branch"
[ -n "$model_display_name" ] && output="$output | 🤖 $model_display_name"
[ -n "$token_details" ] && output="$output | $token_details"
[ -n "$block_time" ] && output="$output | $block_time"
[ -n "$session_cost" ] && output="$output | $session_cost"
[ -n "$daily_cost" ] && output="$output | $daily_cost"

echo "$output"
