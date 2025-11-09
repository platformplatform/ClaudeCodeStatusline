#!/bin/bash

# Pre-tool-use hook for Bash commands
# This hook blocks git commits without explicit permission and enforces pp CLI usage

# Read the JSON input from stdin
input=$(cat)

# Extract the command from the JSON input
cmd=$(echo "$input" | sed -n 's/.*"command":"\([^"]*\)".*/\1/p')

# Check the command and decide whether to block it
case "$cmd" in
    *"git merge"*|*"git rebase"*|*"git cherry-pick"*|*"git reset"*|*"git revert"*|*"git branch -"*|*"git tag"*|*"git rm"*|*"git clean"*|*"git push"*|*"git remote"*|*"git config"*) echo "❌ Dangerous git operation. Only 'git add' and 'git commit' allowed. Run this yourself." >&2; exit 2 ;;
    *"dotnet build"*) echo "❌ Use **build** pp command instead" >&2; exit 2 ;;
    *"dotnet test"*) echo "❌ Use **test** pp command instead" >&2; exit 2 ;;
    *"dotnet format"*) echo "❌ Use **format** pp command instead" >&2; exit 2 ;;
    *"npm run format"*) echo "❌ Use **format** pp command instead" >&2; exit 2 ;;
    *"npm test"*) echo "❌ Use **test** pp command instead" >&2; exit 2 ;;
    *"npm run build"*) echo "❌ Use **build** pp command instead" >&2; exit 2 ;;
    *"npx playwright test"*) echo "❌ Use **e2e** pp command instead" >&2; exit 2 ;;
    *) exit 0 ;;
esac