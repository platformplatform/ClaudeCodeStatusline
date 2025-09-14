#!/bin/bash

# Pre-tool-use hook for Bash commands
# This hook blocks git commits without explicit permission and enforces pp CLI usage

# Read the JSON input from stdin
input=$(cat)

# Extract the command from the JSON input
cmd=$(echo "$input" | sed -n 's/.*"command":"\([^"]*\)".*/\1/p')

# Check the command and decide whether to block it
case "$cmd" in
    *"git merge"*|*"git rebase"*|*"git cherry-pick"*|*"git reset"*|*"git revert"*|*"git stash"*|*"git branch -"*|*"git tag"*|*"git rm"*|*"git clean"*|*"git push"*|*"git remote"*|*"git config"*)
        echo "❌ BLOCKED: This git operation could affect your repository in unexpected ways" >&2
        echo "Command attempted: $cmd" >&2
        echo "" >&2
        echo "Please run this command yourself if you want to proceed." >&2
        echo "Only 'git add' and 'git commit' are allowed for AI use." >&2
        echo "" >&2
        echo "Ask the user: 'Would you like to run this command yourself?'" >&2
        exit 2  # Exit code 2 blocks the tool call
        ;;
    *"dotnet build"*|*"dotnet test"*|*"dotnet format"*)
        echo "❌ BLOCKED: Use pp CLI instead of dotnet commands" >&2
        echo "Command: $cmd" >&2
        echo "" >&2
        echo "Use these instead:" >&2
        echo "• dotnet build → pp build" >&2
        echo "• dotnet test → pp test" >&2
        echo "• dotnet format → pp format" >&2
        exit 2  # Exit code 2 blocks the tool call
        ;;
    *"npm run format"*|*"npm test"*|*"npm run build"*)
        echo "❌ BLOCKED: Use pp CLI instead of npm commands" >&2
        echo "Command: $cmd" >&2
        echo "" >&2
        echo "Use these instead:" >&2
        echo "• npm run format → pp format" >&2
        echo "• npm test → pp test" >&2
        echo "• npm run build → pp build" >&2
        exit 2  # Exit code 2 blocks the tool call
        ;;
    *"npx playwright test"*)
        echo "❌ BLOCKED: Use pp CLI instead of npx commands" >&2
        echo "Command: $cmd" >&2
        echo "" >&2
        echo "Use these instead:" >&2
        echo "• npx playwright test → pp e2e" >&2
        exit 2  # Exit code 2 blocks the tool call
        ;;
    *)
        exit 0  # Exit code 0 allows the tool call to proceed
        ;;
esac