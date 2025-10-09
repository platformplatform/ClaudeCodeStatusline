#!/bin/bash

# Parse JSON input from Claude Code
SESSION_INFO=$(cat)

# Try using ccusage for accurate calculations first (with ORIGINAL model names)
if command -v ccusage >/dev/null 2>&1; then
    CCUSAGE_OUTPUT=$(echo "$SESSION_INFO" | ccusage statusline --no-cache 2>&1)
    CCUSAGE_EXIT=$?

    if [ $CCUSAGE_EXIT -eq 0 ] && [ -n "$CCUSAGE_OUTPUT" ] && [[ "$CCUSAGE_OUTPUT" != *"Invalid input format"* ]]; then
        # Shorten model names AFTER ccusage processes them
        CCUSAGE_OUTPUT=$(echo "$CCUSAGE_OUTPUT" | sed 's/Sonnet 4 (with 1M token context)/Sonnet 4 (1M)/g')
        CCUSAGE_OUTPUT=$(echo "$CCUSAGE_OUTPUT" | sed 's/Sonnet 4.5 (with 1M token context)/Sonnet 4.5 (1M)/g')
        # Extract CWD to find project directory
        CWD=$(echo "$SESSION_INFO" | jq -r '.cwd // ""' 2>/dev/null || echo "$SESSION_INFO" | sed -n 's/.*"cwd":"\([^"]*\)".*/\1/p')

        # Build project path (match Claude Code's encoding)
        ENCODED_PATH=$(echo "$CWD" | sed 's/\//-/g' | sed 's/\./-/g')
        PROJECT_DIR="$HOME/.claude/projects/$ENCODED_PATH"

        # Find the most recently modified transcript file (current session)
        CURRENT_TRANSCRIPT=$(ls -t "$PROJECT_DIR"/*.jsonl 2>/dev/null | head -1)
        LAST_USER_MSG=""

        # Calculate real token count from transcript and replace at the END (ccusage is broken)
        REAL_TOKEN_COUNT=0
        REAL_TOKEN_PCT=0
        if [ -n "$CURRENT_TRANSCRIPT" ] && [ -f "$CURRENT_TRANSCRIPT" ]; then
            # Get the cumulative context from the LAST assistant message
            LAST_USAGE=$(grep '"type":"assistant"' "$CURRENT_TRANSCRIPT" | tail -1 | jq -r '.message.usage // empty' 2>/dev/null)
            if [ -n "$LAST_USAGE" ]; then
                # Calculate total context: input + cached + output tokens
                INPUT=$(echo "$LAST_USAGE" | jq -r '.input_tokens // 0')
                CACHED=$(echo "$LAST_USAGE" | jq -r '.cache_read_input_tokens // 0')
                OUTPUT=$(echo "$LAST_USAGE" | jq -r '.output_tokens // 0')
                REAL_TOKEN_COUNT=$((INPUT + CACHED + OUTPUT))

                # Determine context window size
                MODEL_NAME=$(echo "$SESSION_INFO" | jq -r '.model.display_name // ""' 2>/dev/null || echo "$SESSION_INFO" | sed -n 's/.*"display_name":"\([^"]*\)".*/\1/p')
                CONTEXT_WINDOW=200000
                if [[ "$MODEL_NAME" == *"1M"* ]]; then
                    CONTEXT_WINDOW=1000000
                fi

                # Calculate percentage
                if [ "$REAL_TOKEN_COUNT" -gt 0 ]; then
                    REAL_TOKEN_PCT=$(echo "$REAL_TOKEN_COUNT $CONTEXT_WINDOW" | awk '{printf "%.0f", ($1 / $2) * 100}')
                    # Format token count with thousands separator
                    REAL_TOKEN_FORMATTED=$(echo "$REAL_TOKEN_COUNT" | awk '{printf "%.3f", $1/1000}')
                    # Replace ccusage's broken token count
                    NEW_TOKEN_DISPLAY="| 🧠 $REAL_TOKEN_FORMATTED ($REAL_TOKEN_PCT%)"
                    CCUSAGE_OUTPUT=$(echo "$CCUSAGE_OUTPUT" | python3 -c "import sys, re; line = sys.stdin.read(); replacement = '''$NEW_TOKEN_DISPLAY'''; print(re.sub(r'\| 🧠 [^|]*', replacement, line), end='')")
                fi
            fi
        fi

        # Apply formatting transformations AFTER token replacement
        # Change block format and separators
        CCUSAGE_OUTPUT=$(echo "$CCUSAGE_OUTPUT" | sed 's/\$[0-9.]*[[:space:]]*block[[:space:]]*(\([^)]*\)[[:space:]]*left)/⏰ New block in \1/')
        CCUSAGE_OUTPUT=$(echo "$CCUSAGE_OUTPUT" | sed 's/ \/ / | /g')

        # Add calendar emoji to "today"
        CCUSAGE_OUTPUT=$(echo "$CCUSAGE_OUTPUT" | sed 's/\$\([0-9.]*\) today/📅 $\1 today/')

        # Swap to group money measures together: session | today | hourly | block | brain
        CCUSAGE_OUTPUT=$(echo "$CCUSAGE_OUTPUT" | sed 's/\(.*📅 [^|]*\) | \(⏰ [^|]*\) | \(🔥 [^|]*\) | \(.*\)/\1 | \3 | \2 | \4/')

        # Output single line statusline
        echo "$CCUSAGE_OUTPUT"
        
        exit 0
    fi
fi

# Fallback: Basic statusline if ccusage fails
if command -v jq >/dev/null 2>&1; then
    MODEL=$(echo "$SESSION_INFO" | jq -r '.model.display_name // "Unknown Model"' | sed 's/Sonnet 4 (with 1M token context)/Sonnet 4 (1M)/' | sed 's/Sonnet 4.5 (with 1M token context)/Sonnet 4.5 (1M)/')
    TOTAL_COST=$(echo "$SESSION_INFO" | jq -r '.cost.total_cost_usd // 0')
else
    MODEL=$(echo "$SESSION_INFO" | sed -n 's/.*"display_name":"\([^"]*\)".*/\1/p' | sed 's/Sonnet 4 (with 1M token context)/Sonnet 4 (1M)/' | sed 's/Sonnet 4.5 (with 1M token context)/Sonnet 4.5 (1M)/')
    TOTAL_COST=$(echo "$SESSION_INFO" | sed -n 's/.*"total_cost_usd":\([^,}]*\).*/\1/p')
fi

export LC_NUMERIC=C
SESSION_COST=$(echo "$TOTAL_COST" | awk '{printf "%.2f", $1}')

echo "🤖 $MODEL | 💰 \$$SESSION_COST session"