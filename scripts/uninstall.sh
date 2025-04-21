#!/bin/bash
set -e

INSTALL_DIR="${HOME}/.local/bin"

while [ $# -gt 0 ]; do
  case "$1" in
    --prefix=*)
      INSTALL_DIR="${1#*=}"
      ;;
    --help)
      echo "Usage: $0 [OPTIONS]"
      echo "Uninstall journal management scripts"
      echo
      echo "Options:"
      echo "  --prefix=DIR          Installation directory (default: ~/.local/bin)"
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

echo "Removing scripts from ${INSTALL_DIR}..."
rm -f "${INSTALL_DIR}/cj"
rm -f "${INSTALL_DIR}/journal-timestamp-monitor"

echo "Journal management binaries removed"

if [ -f "${HOME}/.config/systemd/user/journal-timestamp-monitor.service" ]; then
  echo "Stopping and disabling journal timestamp monitor service..."
  systemctl --user stop journal-timestamp-monitor.service 2>/dev/null || true
  systemctl --user disable journal-timestamp-monitor.service 2>/dev/null || true
  rm -f "${HOME}/.config/systemd/user/journal-timestamp-monitor.service"
  systemctl --user daemon-reload

  echo "Journal timestamp monitor service uninstalled"
fi

echo "Uninstallation complete!"