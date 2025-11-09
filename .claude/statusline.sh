#!/bin/bash

# Parse JSON input from Claude Code and pipe to ccusage
echo "$(cat)" | ccusage statusline --no-offline --cost-source cc --no-cache 2>/dev/null | \
    # Change " / " separators to " | "
    sed 's/ \/ / | /g' | \
    # Change "$X.XX block (Xh Xm left)" to "⏰ New block in Xh Xm"
    sed 's/| \$[0-9.]* block (\([^)]*\) left)/| ⏰ New block in \1/' | \
    # Add calendar emoji to "today"
    sed 's/| \$\([0-9.]*\) today/| 📅 $\1 today/'