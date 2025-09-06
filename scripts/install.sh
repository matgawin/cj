#!/usr/bin/env bash
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
  print_message "$INFO" "Installation failed. Please check the error message above."
  exit "${exit_code}"
}

trap 'error_exit "An unexpected error occurred at line $LINENO."' ERR

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

INSTALL_DIR="${HOME}/.local/bin"
JOURNAL_DIR="${HOME}/Journal"
COMMON_LIB_DIR="${HOME}/.local/share/journal"

echo -e "${BLUE}┌──────────────────────────────────────────┐${NC}"
echo -e "${BLUE}│ Journal Management System - Installation │${NC}"
echo -e "${BLUE}└──────────────────────────────────────────┘${NC}"
echo

while [ $# -gt 0 ]; do
  case "$1" in
    --prefix=*)
      INSTALL_DIR="${1#*=}"
      print_message "$INFO" "Custom installation directory set: $INSTALL_DIR"
      ;;
    --journal-dir=*)
      JOURNAL_DIR="${1#*=}"
      print_message "$INFO" "Custom journal directory set: $JOURNAL_DIR"
      ;;
    --help)
      echo -e "${BLUE}Usage:${NC} $0 [OPTIONS]"
      echo "Install journal management scripts"
      echo
      echo -e "${BLUE}Options:${NC}"
      echo "  --prefix=DIR          Installation directory (default: ~/.local/bin)"
      echo "  --journal-dir=DIR     Journal directory (default: ~/Journal)"
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

print_message "$INFO" "Creating installation directory if it doesn't exist..."
if ! mkdir -p "${INSTALL_DIR}" 2>/dev/null; then
  error_exit "Failed to create installation directory: ${INSTALL_DIR}" 2
fi

if [ ! -w "${INSTALL_DIR}" ]; then
  error_exit "Installation directory is not writable: ${INSTALL_DIR}" 3
fi

mkdir -p "${COMMON_LIB_DIR}" 2>/dev/null || {
  print_message "$WARN" "Could not create common library directory: ${COMMON_LIB_DIR}"
  print_message "$INFO" "Will continue without installing common library"
}

if [ -d "${COMMON_LIB_DIR}" ] && [ -w "${COMMON_LIB_DIR}" ]; then
  if [ -f "${PROJECT_ROOT}/src/lib/common.sh" ]; then
    print_message "$INFO" "Installing common library to ${COMMON_LIB_DIR}..."
    cp "${PROJECT_ROOT}/src/lib/common.sh" "${COMMON_LIB_DIR}/" || {
      print_message "$WARN" "Failed to install common library, but continuing with main installation"
    }
  fi
fi

print_message "$INFO" "Installing scripts to ${INSTALL_DIR}..."
if ! cp "${PROJECT_ROOT}/src/bin/create_journal_entry.sh" "${INSTALL_DIR}/cj" 2>/dev/null; then
  error_exit "Failed to copy create_journal_entry.sh script" 4
fi

if ! cp "${PROJECT_ROOT}/src/bin/journal_timestamp_monitor.sh" "${INSTALL_DIR}/journal-timestamp-monitor" 2>/dev/null; then
  error_exit "Failed to copy journal_timestamp_monitor.sh script" 4
fi

print_message "$INFO" "Setting executable permissions..."
if ! chmod +x "${INSTALL_DIR}/cj" 2>/dev/null || ! chmod +x "${INSTALL_DIR}/journal-timestamp-monitor" 2>/dev/null; then
  error_exit "Failed to set executable permissions" 5
fi

print_message "$SUCCESS" "Journal management binaries installed to ${INSTALL_DIR}"

if [[ ":$PATH:" != *":${INSTALL_DIR}:"* ]]; then
  print_message "$WARN" "Installation directory is not in your PATH"
  echo -e "${YELLOW}Please add the following to your shell configuration file (e.g., ~/.bashrc):${NC}"
  echo -e "${BLUE}    export PATH=\"\$PATH:${INSTALL_DIR}\"${NC}"
  echo
fi

echo
print_message "$INFO" "The timestamp monitor service can automatically update timestamps in your journal entries when they are modified."
read -r -p "$(echo -e "${BLUE}Do you want to install the timestamp monitor service? (y/N):${NC} ")" INSTALL_SERVICE

if [ "$INSTALL_SERVICE" = "y" ] || [ "$INSTALL_SERVICE" = "Y" ]; then
  print_message "$INFO" "Creating journal directory: ${JOURNAL_DIR}"
  if ! mkdir -p "${JOURNAL_DIR}" 2>/dev/null; then
    error_exit "Failed to create journal directory: ${JOURNAL_DIR}" 6
  fi

  print_message "$INFO" "Setting up systemd service..."
  SYSTEMD_DIR="${HOME}/.config/systemd/user"
  if ! mkdir -p "${SYSTEMD_DIR}" 2>/dev/null; then
    error_exit "Failed to create systemd user directory: ${SYSTEMD_DIR}" 7
  fi

  SERVICE_FILE="${SYSTEMD_DIR}/journal-timestamp-monitor.service"
  print_message "$INFO" "Creating service file: ${SERVICE_FILE}"

  cat > "${SERVICE_FILE}" << EOF || error_exit "Failed to create service file" 8
[Unit]
Description=Journal Timestamp Monitor Service
After=network.target

[Service]
Type=simple
ExecStart=${INSTALL_DIR}/journal-timestamp-monitor ${JOURNAL_DIR}
Restart=on-failure
RestartSec=5s
Environment="JOURNAL_LOG_LEVEL=INFO"
Environment="JOURNAL_POLLING_INTERVAL=60"

[Install]
WantedBy=default.target
EOF

  if ! command -v systemctl >/dev/null 2>&1; then
    print_message "$WARN" "systemd not found, cannot enable service automatically"
    print_message "$INFO" "To manually start the service, run: ${INSTALL_DIR}/journal-timestamp-monitor ${JOURNAL_DIR}"
  else
    print_message "$INFO" "Reloading systemd daemon..."
    if ! systemctl --user daemon-reload 2>/dev/null; then
      print_message "$WARN" "Failed to reload systemd daemon"
    fi

    print_message "$INFO" "Enabling journal timestamp monitor service..."
    if ! systemctl --user enable journal-timestamp-monitor.service 2>/dev/null; then
      print_message "$WARN" "Failed to enable service"
    fi

    print_message "$INFO" "Starting journal timestamp monitor service..."
    if ! systemctl --user start journal-timestamp-monitor.service 2>/dev/null; then
      print_message "$WARN" "Failed to start service"
      print_message "$INFO" "You can try starting it manually: systemctl --user start journal-timestamp-monitor.service"
    else
      print_message "$SUCCESS" "Journal timestamp monitor service installed and started"

      sleep 1
      if systemctl --user is-active journal-timestamp-monitor.service >/dev/null 2>&1; then
        print_message "$SUCCESS" "Service is running successfully"
      else
        print_message "$WARN" "Service may not be running properly. Check status with: systemctl --user status journal-timestamp-monitor.service"
      fi
    fi

    echo -e "${BLUE}You can check the service status anytime with:${NC}"
    echo -e "  ${GREEN}systemctl --user status journal-timestamp-monitor.service${NC}"
  fi
fi

echo
echo -e "${GREEN}┌─────────────────────────────────────────┐${NC}"
echo -e "${GREEN}│ Installation Complete!                  │${NC}"
echo -e "${GREEN}└─────────────────────────────────────────┘${NC}"
echo
echo -e "${BLUE}Next steps:${NC}"
echo -e "  ${GREEN}cj --help${NC}              View available commands"
echo -e "  ${GREEN}cj${NC}                     Create a journal entry for today"
echo -e "  ${GREEN}cj -e${NC}                  Create and open today's entry in your editor"
echo -e "  ${GREEN}cj -d \"${JOURNAL_DIR}\"${NC}    Create entry in your journal directory"
echo