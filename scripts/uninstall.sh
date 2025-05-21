#!/bin/bash
set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

INFO="INFO"
WARN="WARN"
ERROR="ERROR"
SUCCESS="SUCCESS"

print_message() {
  local level="$1"
  local message="$2"
  local timestamp
  timestamp=$(date "+%Y-%m-%d %H:%M:%S")

  case "$level" in
    "$INFO")
      echo -e "[${timestamp}] ${BLUE}[INFO]${NC} $message"
      ;;
    "$WARN")
      echo -e "[${timestamp}] ${YELLOW}[WARNING]${NC} $message" >&2
      ;;
    "$ERROR")
      echo -e "[${timestamp}] ${RED}[ERROR]${NC} $message" >&2
      ;;
    "$SUCCESS")
      echo -e "[${timestamp}] ${GREEN}[SUCCESS]${NC} $message"
      ;;
    *)
      echo -e "[${timestamp}] $message"
      ;;
  esac
}

error_exit() {
  local message="$1"
  local exit_code="${2:-1}"

  print_message "$ERROR" "Error: ${message} (exit code: ${exit_code})"
  print_message "$INFO" "Uninstallation failed. Please check the error message above."
  exit "${exit_code}"
}

echo -e "${BLUE}┌────────────────────────────────────────────┐${NC}"
echo -e "${BLUE}│ Journal Management System - Uninstallation │${NC}"
echo -e "${BLUE}└────────────────────────────────────────────┘${NC}"
echo

INSTALL_DIR="${HOME}/.local/bin"
COMMON_LIB_DIR="${HOME}/.local/share/journal"
SYSTEMD_SERVICE="${HOME}/.config/systemd/user/journal-timestamp-monitor.service"

while [ $# -gt 0 ]; do
  case "$1" in
    --prefix=*)
      INSTALL_DIR="${1#*=}"
      print_message "$INFO" "Custom installation directory set: $INSTALL_DIR"
      ;;
    --help)
      echo -e "${BLUE}Usage:${NC} $0 [OPTIONS]"
      echo "Uninstall journal management scripts"
      echo
      echo -e "${BLUE}Options:${NC}"
      echo "  --prefix=DIR          Installation directory (default: ~/.local/bin)"
      echo "  --help                Display this help message and exit"
      exit 0
      ;;
    *)
      print_message "$ERROR" "Unknown option: $1"
      echo "Try '$0 --help' for more information."
      exit 1
      ;;
  esac
  shift
done

echo -e "${YELLOW}This will remove the Journal Management System from your computer.${NC}"
read -r -p "$(echo -e "${BLUE}Are you sure you want to continue? (y/N):${NC} ")" CONFIRM

if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
  print_message "$INFO" "Uninstallation cancelled"
  exit 0
fi

if [ -f "$SYSTEMD_SERVICE" ]; then
  print_message "$INFO" "Stopping and disabling journal timestamp monitor service..."

  if command -v systemctl >/dev/null 2>&1; then
    if systemctl --user is-active journal-timestamp-monitor.service >/dev/null 2>&1; then
      print_message "$INFO" "Stopping service..."
      systemctl --user stop journal-timestamp-monitor.service 2>/dev/null || {
        print_message "$WARN" "Failed to stop service, but continuing with uninstallation"
      }
    fi

    if systemctl --user is-enabled journal-timestamp-monitor.service >/dev/null 2>&1; then
      print_message "$INFO" "Disabling service..."
      systemctl --user disable journal-timestamp-monitor.service 2>/dev/null || {
        print_message "$WARN" "Failed to disable service, but continuing with uninstallation"
      }
    fi
  else
    print_message "$WARN" "systemd not found, cannot stop service automatically"
  fi

  print_message "$INFO" "Removing service file..."
  if ! rm -f "$SYSTEMD_SERVICE" 2>/dev/null; then
    print_message "$WARN" "Failed to remove service file: $SYSTEMD_SERVICE"
  else
    print_message "$SUCCESS" "Service file removed successfully"
  fi

  if command -v systemctl >/dev/null 2>&1; then
    print_message "$INFO" "Reloading systemd daemon..."
    systemctl --user daemon-reload 2>/dev/null || {
      print_message "$WARN" "Failed to reload systemd daemon"
    }
  fi

  print_message "$SUCCESS" "Journal timestamp monitor service uninstalled"
fi

print_message "$INFO" "Removing scripts from ${INSTALL_DIR}..."

if [ ! -d "$INSTALL_DIR" ]; then
  print_message "$WARN" "Installation directory not found: $INSTALL_DIR"
else
  if [ -f "${INSTALL_DIR}/cj" ]; then
    if ! rm -f "${INSTALL_DIR}/cj" 2>/dev/null; then
      print_message "$WARN" "Failed to remove script: ${INSTALL_DIR}/cj"
    else
      print_message "$SUCCESS" "Removed: ${INSTALL_DIR}/cj"
    fi
  else
    print_message "$INFO" "Script not found: ${INSTALL_DIR}/cj"
  fi

  if [ -f "${INSTALL_DIR}/journal-timestamp-monitor" ]; then
    if ! rm -f "${INSTALL_DIR}/journal-timestamp-monitor" 2>/dev/null; then
      print_message "$WARN" "Failed to remove script: ${INSTALL_DIR}/journal-timestamp-monitor"
    else
      print_message "$SUCCESS" "Removed: ${INSTALL_DIR}/journal-timestamp-monitor"
    fi
  else
    print_message "$INFO" "Script not found: ${INSTALL_DIR}/journal-timestamp-monitor"
  fi
fi

if [ -d "$COMMON_LIB_DIR" ]; then
  print_message "$INFO" "Removing common library directory..."

  if [ -f "${COMMON_LIB_DIR}/common.sh" ]; then
    if ! rm -f "${COMMON_LIB_DIR}/common.sh" 2>/dev/null; then
      print_message "$WARN" "Failed to remove common library: ${COMMON_LIB_DIR}/common.sh"
    else
      print_message "$SUCCESS" "Removed common library"
    fi
  fi

  if [ -z "$(ls -A "$COMMON_LIB_DIR" 2>/dev/null)" ]; then
    if ! rmdir "$COMMON_LIB_DIR" 2>/dev/null; then
      print_message "$WARN" "Failed to remove directory: $COMMON_LIB_DIR"
    else
      print_message "$SUCCESS" "Removed directory: $COMMON_LIB_DIR"
    fi
  else
    print_message "$INFO" "Common library directory not empty, skipping removal"
  fi
fi

INCOMPLETE=false
if [ -f "${INSTALL_DIR}/cj" ] || [ -f "${INSTALL_DIR}/journal-timestamp-monitor" ] || [ -f "$SYSTEMD_SERVICE" ] || [ -f "${COMMON_LIB_DIR}/common.sh" ]; then
  INCOMPLETE=true
fi

echo
if [ "$INCOMPLETE" = true ]; then
  echo -e "${YELLOW}┌─────────────────────────────────────────────────┐${NC}"
  echo -e "${YELLOW}│ Uninstallation Completed with Warnings          │${NC}"
  echo -e "${YELLOW}└─────────────────────────────────────────────────┘${NC}"
  echo
  print_message "$WARN" "Some components could not be removed. Check the warnings above."
  print_message "$INFO" "You may need to manually remove remaining files with elevated privileges."
else
  echo -e "${GREEN}┌─────────────────────────────────────────┐${NC}"
  echo -e "${GREEN}│ Uninstallation Complete!                │${NC}"
  echo -e "${GREEN}└─────────────────────────────────────────┘${NC}"
  echo
  print_message "$SUCCESS" "Journal Management System has been completely removed"
fi

echo
print_message "$INFO" "Note: Your journal files have NOT been removed."
print_message "$INFO" "If you want to remove them, you can do so manually."
echo