#!/bin/bash

# Get git branch
BRANCH=$(git symbolic-ref --short HEAD 2>/dev/null)

# Parse JSON input from Claude Code and pipe to ccusage
OUTPUT=$(cat | ccusage statusline --no-offline --cost-source cc --no-cache 2>/dev/null | \
    sed 's/ \/ / | /g' | \
    sed 's/| \$[0-9.]* block (\([^)]*\) left)/| ⏰ New block in \1/' | \
    sed 's/| \$\([0-9.]*\) today/| 📅 $\1 today/')

# Prepend branch if available
if [ -n "$BRANCH" ]; then
    echo "🌿 $BRANCH | $OUTPUT"
else
    echo "$OUTPUT"
fi