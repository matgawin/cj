#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

INSTALL_DIR="${HOME}/.local/bin"
JOURNAL_DIR="${HOME}/Journal"

while [ $# -gt 0 ]; do
  case "$1" in
    --prefix=*)
      INSTALL_DIR="${1#*=}"
      ;;
    --journal-dir=*)
      JOURNAL_DIR="${1#*=}"
      ;;
    --help)
      echo "Usage: $0 [OPTIONS]"
      echo "Install journal management scripts"
      echo
      echo "Options:"
      echo "  --prefix=DIR          Installation directory (default: ~/.local/bin)"
      echo "  --journal-dir=DIR     Journal directory (default: ~/Journal)"
      echo "  --help                Display this help message and exit"
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      echo "Try '$0 --help' for more information."
      exit 1
      ;;
  esac
  shift
done

mkdir -p "${INSTALL_DIR}"

echo "Installing scripts to ${INSTALL_DIR}..."
cp "${PROJECT_ROOT}/src/bin/create_journal_entry.sh" "${INSTALL_DIR}/cj"
cp "${PROJECT_ROOT}/src/bin/journal_timestamp_monitor.sh" "${INSTALL_DIR}/journal-timestamp-monitor"

chmod +x "${INSTALL_DIR}/cj"
chmod +x "${INSTALL_DIR}/journal-timestamp-monitor"

echo "Journal management binaries installed to ${INSTALL_DIR}"
echo "Make sure this directory is in your PATH"

read -r -p "Do you want to install the timestamp monitor service? (y/N): " INSTALL_SERVICE
if [ "$INSTALL_SERVICE" = "y" ] || [ "$INSTALL_SERVICE" = "Y" ]; then
  mkdir -p "${JOURNAL_DIR}"
  mkdir -p "${HOME}/.config/systemd/user"

  cat > "${HOME}/.config/systemd/user/journal-timestamp-monitor.service" << EOF
[Unit]
Description=Journal Timestamp Monitor Service
After=network.target

[Service]
Type=simple
ExecStart=${INSTALL_DIR}/journal-timestamp-monitor ${JOURNAL_DIR}
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=default.target
EOF

  systemctl --user daemon-reload
  systemctl --user enable journal-timestamp-monitor.service
  systemctl --user start journal-timestamp-monitor.service

  echo "Journal timestamp monitor service installed and started"
  echo "You can check its status with: systemctl --user status journal-timestamp-monitor.service"
fi

echo "Installation complete!"