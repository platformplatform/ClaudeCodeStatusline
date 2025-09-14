#!/bin/bash

# Post-tool-use hook for Bash commands
# Reminds AI about git commit restrictions after git operations

# Read the JSON input from stdin
input=$(cat)

# Extract the command from the JSON input
cmd=$(echo "$input" | sed -n 's/.*"command":"\([^"]*\)".*/\1/p')

# If it was a git command, remind about commit restrictions
case "$cmd" in
    *"git"*)
        echo "⚠️ REMINDER: Just because you were just asked to commit, this does NOT mean that you should now commit all new code. You MUST get explicit instruction from the user before EACH commit. The user should ALWAYS verify changes before committing." >&2
        ;;
esac

exit 0  # Always allow post-tool execution to proceed