#!/bin/bash
# Check for unprocessed sources in raw/ that aren't in wiki/log.md
# Runs on SessionStart to alert the agent about new material

WIKI_DIR="wiki"
RAW_DIR="raw"
LOG_FILE="$WIKI_DIR/log.md"

# Exit silently if wiki or raw don't exist
[ -d "$WIKI_DIR" ] || exit 0
[ -d "$RAW_DIR" ] || exit 0
[ -f "$LOG_FILE" ] || exit 0

# Get list of files in raw/
raw_files=$(find "$RAW_DIR" -type f -not -name '.*' | sort)
[ -z "$raw_files" ] && exit 0

# Count unprocessed: files in raw/ not mentioned in log.md
unprocessed=0
unprocessed_list=""
while IFS= read -r file; do
  basename=$(basename "$file")
  if ! grep -q "$basename" "$LOG_FILE" 2>/dev/null; then
    unprocessed=$((unprocessed + 1))
    unprocessed_list="$unprocessed_list  - $file\n"
  fi
done <<< "$raw_files"

if [ "$unprocessed" -gt 0 ]; then
  echo "Wiki drift detected: $unprocessed unprocessed source(s) in raw/:"
  echo -e "$unprocessed_list"
  echo "Consider running wiki ingest to process them."
fi
