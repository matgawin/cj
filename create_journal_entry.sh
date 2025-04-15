#!/bin/bash

# create_journal_entry.sh
# Script to create a daily journal entry from a template

# Exit immediately if a command exits with a non-zero status
set -e

# Usage function
usage() {
  echo "Usage: $0 [OPTIONS]"
  echo "Creates a daily journal entry from a template"
  echo
  echo "Options:"
  echo "  -t, --template FILE    Template file (default: journal.template.daily.md)"
  echo "  -e, --edit             Open the journal entry in editor after creation"
  echo "  -E, --editor EDITOR    Specify editor to use (default: $EDITOR)"
  echo "  -h, --help             Display this help message and exit"
  echo
}

# Default values
TEMPLATE_FILE="journal.template.daily.md"
EDITOR="${EDITOR:-vi}"
OPEN_EDITOR=false

# Parse command line arguments
while [[ "$#" -gt 0 ]]; do
  case $1 in
  -t | --template)
    TEMPLATE_FILE="$2"
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
CURRENT_YEAR=$(date +"%Y")
CURRENT_MONTH=$(date +"%m")
CURRENT_DAY=$(date +"%d")

# Calculate previous month for monthly revision
if [[ "$CURRENT_MONTH" == "01" ]]; then
  PREV_MONTH_YEAR=$((CURRENT_YEAR - 1))
  PREV_MONTH="12"
else
  PREV_MONTH_YEAR=$CURRENT_YEAR
  PREV_MONTH=$(printf "%02d" $((10#$CURRENT_MONTH - 1)))
fi

# Previous year for yearly revision
PREV_YEAR=$((CURRENT_YEAR - 1))

# Define output filename
OUTPUT_FILE="journal.daily.${CURRENT_YEAR}.${CURRENT_MONTH}.${CURRENT_DAY}.md"

# Check if file already exists
if [[ -f "$OUTPUT_FILE" ]]; then
  echo "Warning: Journal entry for today already exists: $OUTPUT_FILE"
  read -p "Do you want to overwrite it? (y/N): " CONFIRM
  if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    echo "Operation cancelled"
    exit 0
  fi
fi

# Create journal entry from template
echo "Creating journal entry: $OUTPUT_FILE"

# Replace template variables
sed -e "s/{{ CURRENT_YEAR }}/$CURRENT_YEAR/g" \
  -e "s/{{ CURRENT_MONTH }}/$CURRENT_MONTH/g" \
  -e "s/{{ CURRENT_DAY }}/$CURRENT_DAY/g" \
  "$TEMPLATE_FILE" >"$OUTPUT_FILE"

# Update monthly and yearly revision links with previous dates
sed -i -e "/### Monthly:/,/### Yearly:/ s/$CURRENT_YEAR\.$CURRENT_MONTH/$PREV_MONTH_YEAR\.$PREV_MONTH/g" \
  -e "/### Yearly:/,/##/ s/$CURRENT_YEAR/$PREV_YEAR/g" \
  "$OUTPUT_FILE"

# Set current timestamp in the file
CURRENT_TIMESTAMP=$(date +%s%3N)
sed -i "s/updated: [0-9]*/updated: $CURRENT_TIMESTAMP/" "$OUTPUT_FILE"
sed -i "s/created: [0-9]*/created: $CURRENT_TIMESTAMP/" "$OUTPUT_FILE"

echo "Journal entry created successfully!"

# Open editor if requested
if [[ "$OPEN_EDITOR" = true ]]; then
  echo "Opening journal entry in $EDITOR..."
  "$EDITOR" "$OUTPUT_FILE"
fi

exit 0

