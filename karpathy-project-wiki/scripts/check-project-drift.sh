#!/bin/bash
# Check for code changes since last wiki update
# Runs on SessionStart to alert the agent about drift

WIKI_DIR="wiki"
LOG_FILE="$WIKI_DIR/log.md"

# Exit silently if wiki doesn't exist
[ -d "$WIKI_DIR" ] || exit 0
[ -f "$LOG_FILE" ] || exit 0

# Extract last date from log.md (format: ## [YYYY-MM-DD])
last_date=$(grep -oP '(?<=^## \[)\d{4}-\d{2}-\d{2}' "$LOG_FILE" | tail -1)
[ -z "$last_date" ] && exit 0

# Check if we're in a git repo
git rev-parse --git-dir >/dev/null 2>&1 || exit 0

# Count changes since last wiki update
changed_files=$(git diff --name-only --since="$last_date" HEAD 2>/dev/null | wc -l | tr -d ' ')
commit_count=$(git log --oneline --since="$last_date" 2>/dev/null | wc -l | tr -d ' ')

if [ "$changed_files" -gt 0 ] || [ "$commit_count" -gt 0 ]; then
  echo "Project wiki drift detected since $last_date:"
  echo "  - $commit_count commit(s)"
  echo "  - $changed_files file(s) changed"
  echo ""
  echo "Key changes:"
  git log --oneline --since="$last_date" 2>/dev/null | head -10
  echo ""
  echo "Consider updating the project wiki to reflect these changes."
fi
