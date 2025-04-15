#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

# Usage function
usage() {
  echo "Usage: $0 [OPTIONS]"
  echo "Creates a daily journal entry from a template"
  echo
  echo "Options:"
  echo "  -t, --template FILE    Template file (default: journal.template.daily.md)"
  echo "  -o, --output FILE      Output file (default: journal.daily.YYYY.MM.DD.md)"
  echo "  -e, --edit             Open the journal entry in editor after creation"
  echo "  -E, --editor EDITOR    Specify editor to use (default: $EDITOR)"
  echo "  -d, --directory DIR    Directory to save the journal entry (default: current directory)"
  echo "  -f, --force            Force overwrite without confirmation"
  echo "  -h, --help             Display this help message and exit"
  echo
}

# Default values
TEMPLATE_FILE="journal.template.daily.md"
EDITOR="${EDITOR:-vi}"
OPEN_EDITOR=false
OUTPUT_FILE=""
OUTPUT_DIR="."
FORCE=false

# Determine sed in-place edit command (for macOS compatibility)
if [[ "$(uname)" == "Darwin" ]]; then
  SED_IN_PLACE=(-i "")
else
  SED_IN_PLACE=(-i)
fi

# Parse command line arguments
while [[ "$#" -gt 0 ]]; do
  case $1 in
  -t | --template)
    TEMPLATE_FILE="$2"
    shift
    ;;
  -o | --output)
    OUTPUT_FILE="$2"
    shift
    ;;
  -e | --edit)
    OPEN_EDITOR=true
    ;;
  -E | --editor)
    EDITOR="$2"
    OPEN_EDITOR=true
    shift
    ;;
  -d | --directory)
    OUTPUT_DIR="$2"
    shift
    ;;
  -f | --force)
    FORCE=true
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  *)
    echo "Unknown parameter: $1"
    usage
    exit 1
    ;;
  esac
  shift
done

# Check if template file exists
if [[ ! -f "$TEMPLATE_FILE" ]]; then
  echo "Error: Template file '$TEMPLATE_FILE' not found"
  exit 1
fi

# Get current date components
CURRENT_DATE=$(date +"%Y-%m-%d, %H:%M:%S")
CURRENT_YEAR=$(date +"%Y")
CURRENT_MONTH=$(date +"%m")
CURRENT_DAY=$(date +"%d")

# Calculate days since October 21, 2022
START_DATE="2022-10-21"
if [[ "$(uname)" == "Darwin" ]]; then
  # macOS version
  CURRENT_SECONDS=$(date -j -f "%Y-%m-%d" "$(date +%Y-%m-%d)" +%s)
  START_SECONDS=$(date -j -f "%Y-%m-%d" "$START_DATE" +%s)
else
  # Linux version
  CURRENT_SECONDS=$(date -d "$(date +%Y-%m-%d)" +%s)
  START_SECONDS=$(date -d "$START_DATE" +%s)
fi
DAY_COUNT=$(((CURRENT_SECONDS - START_SECONDS) / 86400 - 2))

# Calculate previous month for monthly revision using date command
PREV_MONTH_DATE=$(date -d "$CURRENT_YEAR-$CURRENT_MONTH-01 -1 month" "+%Y.%m" 2>/dev/null ||
  date -v-1m -j -f "%Y-%m-%d" "$CURRENT_YEAR-$CURRENT_MONTH-01" "+%Y.%m" 2>/dev/null)
PREV_YEAR=$((CURRENT_YEAR - 1))

# Define output filename if not specified
if [[ -z "$OUTPUT_FILE" ]]; then
  OUTPUT_FILE="journal.daily.${CURRENT_YEAR}.${CURRENT_MONTH}.${CURRENT_DAY}.md"
fi

# Ensure output directory exists
mkdir -p "$OUTPUT_DIR"
OUTPUT_FILE="$OUTPUT_DIR/$OUTPUT_FILE"

# Check if file already exists
if [[ -f "$OUTPUT_FILE" && "$FORCE" == "false" ]]; then
  echo "Warning: Journal entry already exists: $OUTPUT_FILE"
  read -p "Do you want to overwrite it? (y/N): " CONFIRM
  if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    echo "Operation cancelled"
    exit 0
  fi
  # Create backup of existing file
  cp "$OUTPUT_FILE" "${OUTPUT_FILE}.bak"
  echo "Backup created: ${OUTPUT_FILE}.bak"
fi

# Create journal entry from template
echo "Creating journal entry: $OUTPUT_FILE"

# Replace template variables
sed -e "s/{{ CURRENT_YEAR }}/$CURRENT_YEAR/g" \
  -e "s/{{ CURRENT_MONTH }}/$CURRENT_MONTH/g" \
  -e "s/{{ CURRENT_DAY }}/$CURRENT_DAY/g" \
  -e "s/{{ CURRENT_DATE }}/$CURRENT_DATE/g" \
  -e "s/{{ DAY_COUNT }}/$DAY_COUNT/g" \
  "$TEMPLATE_FILE" >"$OUTPUT_FILE"

# Update monthly and yearly revision links with previous dates
CURRENT_TIMESTAMP=$(date +%s%3N)
HUMAN_TIMESTAMP=$(date "+%Y-%m-%d %H:%M:%S")

sed "${SED_IN_PLACE[@]}" \
  -e "/### Monthly:/,/### Yearly:/ s/$CURRENT_YEAR\.$CURRENT_MONTH/$PREV_MONTH_DATE/g" \
  -e "/### Yearly:/,/##/ s/$CURRENT_YEAR/$PREV_YEAR/g" \
  -e "s|<!-- TIMESTAMP -->|$HUMAN_TIMESTAMP|g" \
  "$OUTPUT_FILE"

echo "Journal entry created successfully!"

# Open editor if requested
if [[ "$OPEN_EDITOR" = true ]]; then
  if command -v "$EDITOR" >/dev/null 2>&1; then
    echo "Opening journal entry in $EDITOR..."
    "$EDITOR" "$OUTPUT_FILE"
  else
    echo "Error: Editor '$EDITOR' not found, cannot open journal entry"
    exit 1
  fi
fi

exit 0
