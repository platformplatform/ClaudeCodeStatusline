#!/bin/bash

# Parse JSON input from Claude Code
SESSION_INFO=$(cat)

# Preprocess model name for shorter display
SESSION_INFO=$(echo "$SESSION_INFO" | sed 's/"Sonnet 4 (with 1M token context)"/"Sonnet 4 (1M tokens)"/g')

# Try using ccusage for accurate calculations first
if command -v ccusage >/dev/null 2>&1; then
    CCUSAGE_OUTPUT=$(echo "$SESSION_INFO" | ccusage statusline 2>/dev/null)
    if [ $? -eq 0 ] && [ -n "$CCUSAGE_OUTPUT" ]; then
        # Fix percentage calculation for 1M token models
        MODEL_NAME=$(echo "$SESSION_INFO" | jq -r '.model.display_name // ""' 2>/dev/null || echo "$SESSION_INFO" | sed -n 's/.*"display_name":"\([^"]*\)".*/\1/p')
        if [[ "$MODEL_NAME" == *"1M token"* ]] && [[ "$CCUSAGE_OUTPUT" == *"("*"%)"* ]]; then
            # Extract token count and recalculate percentage for correct context window
            TOKEN_COUNT=$(echo "$CCUSAGE_OUTPUT" | sed -n 's/.*🧠 \([0-9.]*\).*/\1/p')
            if [ -n "$TOKEN_COUNT" ] && [ "$TOKEN_COUNT" != "0" ]; then
                # Calculate percentage: tokens / 1M * 100
                CORRECT_PCT=$(echo "$TOKEN_COUNT" | awk '{printf "%.0f", ($1 * 1000) / 1000000 * 100}')
                # Replace the incorrect percentage with correct one
                CCUSAGE_OUTPUT=$(echo "$CCUSAGE_OUTPUT" | sed 's/([0-9.]*%)/('$CORRECT_PCT'%)/')
            fi
        fi
        
        # Change block format and separators
        CCUSAGE_OUTPUT=$(echo "$CCUSAGE_OUTPUT" | sed 's/\$[0-9.]*[[:space:]]*block[[:space:]]*(\([^)]*\)[[:space:]]*left)/⏰ New block in \1/')
        CCUSAGE_OUTPUT=$(echo "$CCUSAGE_OUTPUT" | sed 's/ \/ / | /g')
        
        # Add calendar emoji to "today" and reorder elements
        CCUSAGE_OUTPUT=$(echo "$CCUSAGE_OUTPUT" | sed 's/\$\([0-9.]*\) today/📅 $\1 today/')
        
        # Reorder: session | today | hourly | block | tokens
        # Extract components using regex groups
        if [[ "$CCUSAGE_OUTPUT" =~ \$([0-9.]*)[[:space:]]*session.*📅[[:space:]]*(\$[0-9.]*[[:space:]]*today).*(\$[0-9.]*\/hr).*⏰[[:space:]]*(New[[:space:]]*block[[:space:]]*in[[:space:]]*[^|]*).*🧠[[:space:]]*([0-9.]*[[:space:]]*\([^)]*\)) ]]; then
            SESSION="${BASH_REMATCH[1]}"
            TODAY="${BASH_REMATCH[2]}"
            HOURLY="${BASH_REMATCH[3]}"
            BLOCK="${BASH_REMATCH[4]}"
            TOKENS="${BASH_REMATCH[5]}"
            CCUSAGE_OUTPUT="💰 \$${SESSION} session | ${TODAY} | 🔥 ${HOURLY} | ⏰ ${BLOCK} | 🧠 ${TOKENS}"
        fi
        # Get git info
        GIT_BRANCH=$(git symbolic-ref --short HEAD 2>/dev/null || echo "no-git")
        REPO_NAME=$(basename "$(git rev-parse --show-toplevel 2>/dev/null)" 2>/dev/null || echo "no-repo")
        
        # Extract session_id and construct current transcript path
        SESSION_ID=$(echo "$SESSION_INFO" | jq -r '.session_id // ""' 2>/dev/null || echo "$SESSION_INFO" | sed -n 's/.*"session_id":"\([^"]*\)".*/\1/p')
        CWD=$(echo "$SESSION_INFO" | jq -r '.cwd // ""' 2>/dev/null || echo "$SESSION_INFO" | sed -n 's/.*"cwd":"\([^"]*\)".*/\1/p')
        
        # Build transcript path using current session (match Claude Code's encoding)
        ENCODED_PATH=$(echo "$CWD" | sed 's/\//-/g' | sed 's/\./-/g')
        CURRENT_TRANSCRIPT="$HOME/.claude/projects/$ENCODED_PATH/$SESSION_ID.jsonl"
        LAST_USER_MSG=""
        
        
        if [ -n "$CURRENT_TRANSCRIPT" ] && [ -f "$CURRENT_TRANSCRIPT" ]; then
            # Get last actual user text message (skip tool results and interruptions)
            LAST_USER_MSG=$(grep '"type":"user"' "$CURRENT_TRANSCRIPT" | grep -v '"type":"tool_result"' | tail -1 | jq -r 'if (.message.content | type) == "string" then .message.content else .message.content[0].text // "" end' 2>/dev/null || echo "")
            
            # If last message is an interruption, get the previous one
            if [ "$LAST_USER_MSG" = "[Request interrupted by user]" ]; then
                LAST_USER_MSG=$(grep '"type":"user"' "$CURRENT_TRANSCRIPT" | grep -v '"type":"tool_result"' | tail -2 | head -1 | jq -r 'if (.message.content | type) == "string" then .message.content else .message.content[0].text // "" end' 2>/dev/null || echo "")
            fi
            
            # Convert actual newlines to ↩ emoji using python
            LAST_USER_MSG=$(printf "%s" "$LAST_USER_MSG" | python3 -c "import sys; print(sys.stdin.read().replace('\n', ' ↩ ').strip().rstrip(' ↩'))" | sed 's/  */ /g')
            if [ ${#LAST_USER_MSG} -gt 180 ]; then
                LAST_USER_MSG="${LAST_USER_MSG:0:147}..."
            fi
        fi
        
        # Get terminal width
        TERM_WIDTH=$(tput cols 2>/dev/null || echo "80")
        
        # Build main statusline
        MAIN_LINE="🌿 $GIT_BRANCH | $CCUSAGE_OUTPUT"
        
        # Calculate padding needed (account for emoji width issues)
        CONTENT_LENGTH=${#MAIN_LINE}
        PADDING=$((TERM_WIDTH - CONTENT_LENGTH))
        
        # Add padding spaces if needed
        if [ $PADDING -gt 0 ]; then
            SPACES=$(printf "%*s" $PADDING "")
            echo "$MAIN_LINE$SPACES"
        else
            echo "$MAIN_LINE"
        fi
        
        # Display last user message if available
        if [ -n "$LAST_USER_MSG" ]; then
            USER_LINE="💬 $LAST_USER_MSG"
            USER_LENGTH=${#USER_LINE}
            USER_PADDING=$((TERM_WIDTH - USER_LENGTH))
            
            if [ $USER_PADDING -gt 0 ]; then
                USER_SPACES=$(printf "%*s" $USER_PADDING "")
                echo "$USER_LINE$USER_SPACES"
            else
                echo "$USER_LINE"
            fi
        fi
        
        exit 0
    fi
fi

# Fallback: Basic statusline if ccusage fails
if command -v jq >/dev/null 2>&1; then
    MODEL=$(echo "$SESSION_INFO" | jq -r '.model.display_name // "Unknown Model"' | sed 's/Sonnet 4 (with 1M token context)/Sonnet 4 (1M tokens)/')
    TOTAL_COST=$(echo "$SESSION_INFO" | jq -r '.cost.total_cost_usd // 0')
else
    MODEL=$(echo "$SESSION_INFO" | sed -n 's/.*"display_name":"\([^"]*\)".*/\1/p' | sed 's/Sonnet 4 (with 1M token context)/Sonnet 4 (1M tokens)/')
    TOTAL_COST=$(echo "$SESSION_INFO" | sed -n 's/.*"total_cost_usd":\([^,}]*\).*/\1/p')
fi

GIT_BRANCH=$(git symbolic-ref --short HEAD 2>/dev/null || echo "no-git")
export LC_NUMERIC=C
SESSION_COST=$(echo "$TOTAL_COST" | awk '{printf "%.2f", $1}')

echo "🌿 $GIT_BRANCH | 🤖 $MODEL | 💰 \$$SESSION_COST session"