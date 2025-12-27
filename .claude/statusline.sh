#!/bin/bash

# =============================================================================
# Claude Code Custom Status Line Script
# =============================================================================
# Uses transcript file parsing + output token adjustment for accurate counts.
# Formula: input_tokens + cache_tokens + (50% of cumulative output_tokens)
# This matches /context within 1-2% accuracy.
# =============================================================================

# Read JSON input from Claude Code
json_input=$(cat)

# -----------------------------------------------------------------------------
# Extract workspace and directory information
# -----------------------------------------------------------------------------
current_directory=$(echo "$json_input" | jq -r '.workspace.current_dir // .cwd')
directory_name=$(basename "$current_directory")

# -----------------------------------------------------------------------------
# Get git branch
# -----------------------------------------------------------------------------
git_branch=""
if git -C "$current_directory" rev-parse --git-dir > /dev/null 2>&1; then
    git_branch=$(git -C "$current_directory" --no-optional-locks rev-parse --abbrev-ref HEAD 2>/dev/null)
fi

# -----------------------------------------------------------------------------
# Extract model information
# -----------------------------------------------------------------------------
model_display_name=$(echo "$json_input" | jq -r '.model.display_name' | sed 's/ context)/)/g')

# -----------------------------------------------------------------------------
# Extract context window size
# -----------------------------------------------------------------------------
context_window_size=$(echo "$json_input" | jq -r '.context_window.context_window_size // 200000')

# -----------------------------------------------------------------------------
# Calculate context usage by parsing transcript file
# -----------------------------------------------------------------------------
transcript_path=$(echo "$json_input" | jq -r '.transcript_path')

context_display=""
estimated_context_tokens=""

if [ -n "$transcript_path" ] && [ -f "$transcript_path" ] && [ "$context_window_size" -gt 0 ]; then
    # Get the last valid entry's input tokens
    last_input_tokens=$(grep "input_tokens" "$transcript_path" 2>/dev/null | tail -1 | jq -r '
        ((.message.usage.input_tokens // 0) +
         (.message.usage.cache_read_input_tokens // 0) +
         (.message.usage.cache_creation_input_tokens // 0))
    ' 2>/dev/null)

    # Sum ALL output tokens from the entire session
    total_output_tokens=$(grep "output_tokens" "$transcript_path" 2>/dev/null | jq -r '.message.usage.output_tokens // 0' 2>/dev/null | awk '{sum+=$1} END {print int(sum)}')

    if [ -n "$last_input_tokens" ] && [ "$last_input_tokens" -gt 0 ] 2>/dev/null; then
        # Add 100% of cumulative output tokens + 10% overhead factor
        # The 50% formula underestimates; /context includes additional overhead
        output_adjustment=$((total_output_tokens))
        overhead_adjustment=$((last_input_tokens / 10))  # ~10% for prompt/tool overhead
        estimated_context_tokens=$((last_input_tokens + output_adjustment + overhead_adjustment))
    fi
fi

# Fallback to JSON context_window data if transcript parsing fails
if [ -z "$estimated_context_tokens" ] || [ "$estimated_context_tokens" = "0" ]; then
    current_usage=$(echo "$json_input" | jq -r '.context_window.current_usage')
    total_output=$(echo "$json_input" | jq -r '.context_window.total_output_tokens // 0')

    if [ "$current_usage" != "null" ]; then
        input_tokens=$(echo "$current_usage" | jq -r '
            ((.input_tokens // 0) + (.cache_read_input_tokens // 0) + (.cache_creation_input_tokens // 0))
        ')
        output_adjustment=$((total_output))
        overhead_adjustment=$((input_tokens / 10))
        estimated_context_tokens=$((input_tokens + output_adjustment + overhead_adjustment))
    fi
fi

if [ -n "$estimated_context_tokens" ] && [ "$estimated_context_tokens" -gt 0 ] 2>/dev/null; then
    # Calculate percentage of context window used
    context_percentage=$((estimated_context_tokens * 100 / context_window_size))

    # Calculate values including the 45k autocompact buffer
    autocompact_buffer_tokens=45000
    context_tokens_with_buffer=$((estimated_context_tokens + autocompact_buffer_tokens))
    percentage_with_buffer=$((context_tokens_with_buffer * 100 / context_window_size))

    # Format token counts with "k" suffix
    tokens_in_thousands=$((estimated_context_tokens / 1000))
    tokens_with_buffer_in_thousands=$((context_tokens_with_buffer / 1000))
    context_display="🧠 ${tokens_in_thousands}k (${context_percentage}%) - ${tokens_with_buffer_in_thousands}k (${percentage_with_buffer}%)"
fi

# -----------------------------------------------------------------------------
# Get cost/block info from ccusage
# -----------------------------------------------------------------------------
ccusage_output=$(echo "$json_input" | ccusage statusline --no-offline --cost-source cc --no-cache 2>/dev/null)

# Extract specific parts from ccusage output
session_cost=$(echo "$ccusage_output" | sed -n 's/.*\$\([0-9.]*\) session.*/💰 $\1 session/p')
block_time=$(echo "$ccusage_output" | sed -n 's/.*\$[0-9.]* block (\([^)]*\) left).*/⏰️ New block in \1/p')
daily_cost=$(echo "$ccusage_output" | sed -n 's/.*\$\([0-9.]*\) today.*/📅 $\1 today/p')

# -----------------------------------------------------------------------------
# Build final output
# -----------------------------------------------------------------------------
output="📁 $directory_name"

if [ -n "$git_branch" ]; then
    output="$output | 🌿 $git_branch"
fi

if [ -n "$model_display_name" ]; then
    output="$output | 🤖 $model_display_name"
fi

if [ -n "$context_display" ]; then
    output="$output | $context_display"
fi

if [ -n "$block_time" ]; then
    output="$output | $block_time"
fi

if [ -n "$session_cost" ]; then
    output="$output | $session_cost"
fi

if [ -n "$daily_cost" ]; then
    output="$output | $daily_cost"
fi

echo "$output"
