# Makefile for Journal Management System

PREFIX ?= $(HOME)/.local
JOURNAL_DIR ?= $(HOME)/Journal
SCRIPTS_DIR = scripts

.PHONY: all help install install-service uninstall uninstall-service

all: help

help:
	@echo "Journal Management System - Makefile Targets"
	@echo "==========================================="
	@echo
	@echo "Installation targets:"
	@echo "  install         - Install the journal management scripts"
	@echo "  install-service - Install and start the systemd service"
	@echo
	@echo "Uninstallation targets:"
	@echo "  uninstall       - Uninstall the journal management scripts"
	@echo "  uninstall-service - Uninstall the systemd service"
	@echo
	@echo "Other targets:"
	@echo "  help            - Show this help message"
	@echo
	@echo "Configuration variables:"
	@echo "  PREFIX        - Installation prefix (default: $(PREFIX))"
	@echo "  JOURNAL_DIR   - Journal directory (default: $(JOURNAL_DIR))"
	@echo

install:
	@echo "Installing journal management scripts..."
	@$(SCRIPTS_DIR)/install.sh --prefix=$(PREFIX) --journal-dir=$(JOURNAL_DIR)

install-service: install
	@echo "Installing journal timestamp monitor service..."
	@bash src/bin/create_journal_entry.sh --directory=$(JOURNAL_DIR) --install-service

uninstall:
	@echo "Uninstalling journal management scripts..."
	@$(SCRIPTS_DIR)/uninstall.sh --prefix=$(PREFIX)

uninstall-service:
	@echo "Uninstalling journal timestamp monitor service..."
	@bash src/bin/create_journal_entry.sh --uninstall-service
