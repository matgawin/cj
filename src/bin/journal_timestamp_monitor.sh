#!/bin/bash

set -e

JOURNAL_DIR="$1"
if [ -z "$JOURNAL_DIR" ]; then
  echo "Error: Journal directory not specified"
  echo "Usage: $0 <journal_directory>"
  exit 1
fi

LOG_FILE="/tmp/journal_timestamp_monitor.log"
touch "$LOG_FILE"

log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >>"$LOG_FILE"
}

log "Starting journal timestamp monitor for directory: $JOURNAL_DIR"

# Function to update the timestamp in a file
update_timestamp() {
  local file="$1"
  local current_time

  current_time=$(date +"%Y-%m-%d, %H:%M:%S")

  # Only update if the file is a markdown file with our journal format
  if [[ "$file" == *.md && $(grep -c "^---$" "$file" | head -n 2) -ge 2 ]]; then
    log "Updating timestamp for file: $file"

    if [[ "$(uname)" == "Darwin" ]]; then
      sed -i "" "s/^updated:.*$/updated: $current_time/" "$file"
    else
      sed -i "s/^updated:.*$/updated: $current_time/" "$file"
    fi
  fi
}

# Use inotifywait if available, otherwise fallback to periodic checking
if command -v inotifywait >/dev/null 2>&1; then
  log "Using inotifywait for file monitoring"

  # Monitor directory continuously
  while true; do
    inotifywait -q -e modify -e close_write --format "%w%f" "$JOURNAL_DIR" | while read -r file; do
      if [[ "$file" == *.md ]]; then
        update_timestamp "$file"
      fi
    done
  done
else
  log "inotifywait not found, using periodic checking instead"

  # Fallback to periodic checking
  while true; do
    log "Checking for modified files"
    find "$JOURNAL_DIR" -name "*.md" -mmin -1 | while read -r file; do
      update_timestamp "$file"
    done
    sleep 60
  done
fi
