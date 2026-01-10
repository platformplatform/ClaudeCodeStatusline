#!/bin/bash

# =============================================================================
# Claude Code Custom Status Line Script
# =============================================================================
# Features: tokens, git status, session duration, API response time, costs
# =============================================================================

json_input=$(cat)

# -----------------------------------------------------------------------------
# Workspace / directory
# -----------------------------------------------------------------------------
current_directory=$(echo "$json_input" | jq -r '.workspace.current_dir // .cwd')
directory_name=$(basename "$current_directory")

# -----------------------------------------------------------------------------
# Git branch + dirty/clean indicator + ahead/behind remote
# -----------------------------------------------------------------------------
git_display=""
if git -C "$current_directory" rev-parse --git-dir > /dev/null 2>&1; then
    git_branch=$(git -C "$current_directory" --no-optional-locks rev-parse --abbrev-ref HEAD 2>/dev/null)
    if [ -n "$git_branch" ]; then
        # Check for uncommitted changes (dirty)
        if git -C "$current_directory" --no-optional-locks diff --quiet 2>/dev/null && \
           git -C "$current_directory" --no-optional-locks diff --cached --quiet 2>/dev/null; then
            is_dirty=false
        else
            is_dirty=true
        fi

        # Check ahead/behind remote
        ahead_behind=""
        if git -C "$current_directory" --no-optional-locks rev-parse --abbrev-ref '@{upstream}' >/dev/null 2>&1; then
            behind=$(git -C "$current_directory" --no-optional-locks rev-list --count HEAD..@{upstream} 2>/dev/null || echo "0")
            ahead=$(git -C "$current_directory" --no-optional-locks rev-list --count @{upstream}..HEAD 2>/dev/null || echo "0")
            down_arrow=$'\xe2\x86\x93'
            up_arrow=$'\xe2\x86\x91'
            [ "$behind" -gt 0 ] 2>/dev/null && ahead_behind="${down_arrow}$behind"
            [ "$ahead" -gt 0 ] 2>/dev/null && ahead_behind="$ahead_behind${up_arrow}$ahead"
            [ -n "$ahead_behind" ] && ahead_behind=" $ahead_behind"
        fi

        # Build git display
        if [ "$is_dirty" = true ]; then
            # Yellow when dirty
            git_display="\033[33m🌿 $git_branch$ahead_behind\033[0m"
        else
            git_display="🌿 $git_branch$ahead_behind"
        fi
    fi
fi

# -----------------------------------------------------------------------------
# Model
# -----------------------------------------------------------------------------
model_display_name=$(echo "$json_input" | jq -r '.model.display_name' | sed 's/ context)/)/g')

# -----------------------------------------------------------------------------
# Token counts + percentage
# -----------------------------------------------------------------------------
token_details=""
usage=$(echo "$json_input" | jq '.context_window.current_usage')

if [ "$usage" != "null" ]; then
    input_tokens=$(echo "$usage" | jq -r '.input_tokens // 0')
    cache_read=$(echo "$usage" | jq -r '.cache_read_input_tokens // 0')
    cache_creation=$(echo "$usage" | jq -r '.cache_creation_input_tokens // 0')
    total_input=$((input_tokens + cache_read + cache_creation))

    session_output=$(echo "$json_input" | jq -r '.context_window.total_output_tokens // 0')

    input_k=$(((total_input + 999) / 1000))
    output_k=$(((session_output + 999) / 1000))

    # Determine context window size based on model
    if echo "$model_display_name" | grep -q "(1M)"; then
        context_window=1000000
    else
        context_window=200000
    fi

    # Calculate percentage (round up)
    percentage=$(((total_input * 100 + context_window - 1) / context_window))

    # Color coding based on context usage (warning for autocompact)
    # Yellow > 60%, Red > 70%
    if [ "$percentage" -gt 70 ]; then
        # Red
        token_details="\033[31m🧠 ${percentage}% | 📥 ${input_k}k 📤 ${output_k}k\033[0m"
    elif [ "$percentage" -gt 60 ]; then
        # Yellow
        token_details="\033[33m🧠 ${percentage}% | 📥 ${input_k}k 📤 ${output_k}k\033[0m"
    else
        token_details="🧠 ${percentage}% | 📥 ${input_k}k 📤 ${output_k}k"
    fi
fi

# -----------------------------------------------------------------------------
# Session duration (from cost.total_duration_ms)
# -----------------------------------------------------------------------------
session_duration=""
total_duration_ms=$(echo "$json_input" | jq -r '.cost.total_duration_ms // 0')
if [ "$total_duration_ms" -gt 0 ] 2>/dev/null; then
    total_seconds=$((total_duration_ms / 1000))
    hours=$((total_seconds / 3600))
    minutes=$(((total_seconds % 3600) / 60))
    if [ "$hours" -gt 0 ]; then
        session_duration="${hours}h${minutes}m"
    else
        session_duration="${minutes}m"
    fi
fi

# -----------------------------------------------------------------------------
# Last API response time (from cost.total_api_duration_ms / message count estimate)
# -----------------------------------------------------------------------------
api_time=""
total_api_ms=$(echo "$json_input" | jq -r '.cost.total_api_duration_ms // 0')
if [ "$total_api_ms" -gt 0 ] 2>/dev/null; then
    # Show total API time in seconds
    api_seconds=$((total_api_ms / 1000))
    api_time="⧖ ${api_seconds}s"
fi

# -----------------------------------------------------------------------------
# ccusage-based cost info
# -----------------------------------------------------------------------------
ccusage_output=$(echo "$json_input" | ccusage statusline --no-offline --cost-source cc --no-cache 2>/dev/null)

# Extract session cost (we'll append duration to it)
session_cost_raw=$(echo "$ccusage_output" | sed -n 's/.*\$\([0-9.]*\) session.*/\1/p')
if [ -n "$session_cost_raw" ] && [ -n "$session_duration" ]; then
    session_cost="💰 \$${session_cost_raw} (${session_duration})"
elif [ -n "$session_cost_raw" ]; then
    session_cost="💰 \$${session_cost_raw} session"
else
    session_cost=""
fi

block_time=$(echo "$ccusage_output" | sed -n 's/.*\$[0-9.]* block (\([^)]*\) left).*/⏰️ New block in \1/p')
daily_cost=$(echo "$ccusage_output" | sed -n 's/.*\$\([0-9.]*\) today.*/📅 $\1 today/p')

# -----------------------------------------------------------------------------
# Build final output
# -----------------------------------------------------------------------------
output="📁 $directory_name"

[ -n "$git_display" ] && output="$output | $git_display"
[ -n "$model_display_name" ] && output="$output | 🤖 $model_display_name"
[ -n "$token_details" ] && output="$output | $token_details"
[ -n "$api_time" ] && output="$output | $api_time"
[ -n "$block_time" ] && output="$output | $block_time"
[ -n "$session_cost" ] && output="$output | $session_cost"
[ -n "$daily_cost" ] && output="$output | $daily_cost"

echo -e "$output"
