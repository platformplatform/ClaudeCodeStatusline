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

    # Calculate our own percentage
    if echo "$model_display_name" | grep -q "(1M)"; then
        context_window=1000000
    else
        context_window=200000
    fi
    our_percentage=$(((total_input * 100 + context_window - 1) / context_window))

    # Try to get official percentages from Claude Code
    used_pct=$(echo "$json_input" | jq -r '.context_window.used_percentage // empty')
    remaining_pct=$(echo "$json_input" | jq -r '.context_window.remaining_percentage // empty')

    # Build percentage display
    if [ -n "$used_pct" ]; then
        official_pct=${used_pct%.*}  # Remove decimal part
        remaining=${remaining_pct%.*}
        # Show official percentage with remaining
        pct_display="🧠 ${official_pct}% (${remaining}% left)"
        percentage=$official_pct

        # Check if our calculation differs by more than 2% - warn if so
        diff=$((our_percentage - official_pct))
        [ "$diff" -lt 0 ] && diff=$((-diff))  # Absolute value
        if [ "$diff" -gt 2 ]; then
            token_warning="⚠️ "
        else
            token_warning=""
        fi
    else
        pct_display="🧠 ${our_percentage}%"
        percentage=$our_percentage
        token_warning=""
    fi

    # Color coding based on context usage (warning for autocompact)
    # Yellow > 60%, Red > 70%
    if [ "$percentage" -gt 70 ]; then
        # Red
        token_details="\033[31m${pct_display} | ${token_warning}📥 ${input_k}k 📤 ${output_k}k\033[0m"
    elif [ "$percentage" -gt 60 ]; then
        # Yellow
        token_details="\033[33m${pct_display} | ${token_warning}📥 ${input_k}k 📤 ${output_k}k\033[0m"
    else
        token_details="${pct_display} | ${token_warning}📥 ${input_k}k 📤 ${output_k}k"
    fi
else
    # No usage data yet (session start) - show placeholder
    token_details="🧠 --% | 📥 --k 📤 --k"
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
# Build final output (responsive based on terminal width)
# -----------------------------------------------------------------------------

# Get terminal width by querying parent shell's TTY directly
get_term_width() {
    local pid=$$
    for _ in 1 2 3 4 5 6 7 8 9 10; do
        local tty_device=$(ps -o tty= -p "$pid" 2>/dev/null | tr -d ' ')
        if [ -n "$tty_device" ] && [ "$tty_device" != "??" ]; then
            local size=$(stty -f "/dev/$tty_device" size 2>/dev/null)
            if [ -n "$size" ]; then
                echo "$size" | awk '{print $2}'
                return
            fi
        fi
        # Get parent PID
        pid=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')
        [ -z "$pid" ] && break
    done
    echo "150"
}
term_width=$(get_term_width)
# Ensure we have a valid number
[[ "$term_width" =~ ^[0-9]+$ ]] || term_width=150
# Reserve 25 chars for system messages on the right
term_width=$((term_width - 25))

# Function to get display width (accounts for emojis taking 2 columns)
get_display_width() {
    # Strip ANSI codes
    local stripped
    stripped=$(echo -e "$1" | sed $'s/\033\[[0-9;]*m//g' | sed 's/\\033\[[0-9;]*m//g')
    local char_count=${#stripped}
    # Count emojis (they take 2 columns each, so add 1 extra per emoji)
    local emoji_count=$(echo -e "$stripped" | grep -o '[📁🌿🤖🧠📥📤⧖💰📅⏰🔥↑↓⬆⬇⚠️]' | wc -l | tr -d ' ')
    printf '%s' "$((char_count + emoji_count))"
}

# Build full output in desired order
full_output=""
[ -n "$directory_name" ] && full_output="📁 $directory_name"
[ -n "$git_display" ] && { [ -n "$full_output" ] && full_output="$full_output | $git_display" || full_output="$git_display"; }
[ -n "$model_display_name" ] && { [ -n "$full_output" ] && full_output="$full_output | 🤖 $model_display_name" || full_output="🤖 $model_display_name"; }
[ -n "$token_details" ] && { [ -n "$full_output" ] && full_output="$full_output | $token_details" || full_output="$token_details"; }
[ -n "$api_time" ] && { [ -n "$full_output" ] && full_output="$full_output | $api_time" || full_output="$api_time"; }
[ -n "$session_cost" ] && { [ -n "$full_output" ] && full_output="$full_output | $session_cost" || full_output="$session_cost"; }
[ -n "$daily_cost" ] && { [ -n "$full_output" ] && full_output="$full_output | $daily_cost" || full_output="$daily_cost"; }
[ -n "$block_time" ] && { [ -n "$full_output" ] && full_output="$full_output | $block_time" || full_output="$block_time"; }

# Check if it fits
current_width=$(get_display_width "$full_output")

# If too wide, progressively remove lowest priority items
# Priority order to remove: block_time, api_time, directory, daily_cost, session_cost, git
if [ "$current_width" -gt "$term_width" ] && [ -n "$block_time" ]; then
    full_output=$(echo "$full_output" | sed "s/ | ${block_time//\//\\/}//")
    current_width=$(get_display_width "$full_output")
fi
if [ "$current_width" -gt "$term_width" ] && [ -n "$api_time" ]; then
    full_output=$(echo "$full_output" | sed "s/ | ${api_time//\//\\/}//")
    current_width=$(get_display_width "$full_output")
fi
if [ "$current_width" -gt "$term_width" ] && [ -n "$directory_name" ]; then
    full_output=$(echo "$full_output" | sed "s/📁 ${directory_name} | //")
    current_width=$(get_display_width "$full_output")
fi
if [ "$current_width" -gt "$term_width" ] && [ -n "$daily_cost" ]; then
    full_output=$(echo "$full_output" | sed "s/ | ${daily_cost//\//\\/}//")
    current_width=$(get_display_width "$full_output")
fi
if [ "$current_width" -gt "$term_width" ] && [ -n "$session_cost" ]; then
    full_output=$(echo "$full_output" | sed "s/ | ${session_cost//\//\\/}//")
    current_width=$(get_display_width "$full_output")
fi
if [ "$current_width" -gt "$term_width" ] && [ -n "$git_display" ]; then
    # Git display has ANSI codes, need to handle carefully
    full_output=$(echo -e "$full_output" | sed 's/[^|]*🌿[^|]* | //')
    current_width=$(get_display_width "$full_output")
fi

echo -e "$full_output"
