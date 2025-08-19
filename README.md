# Journal Management System

A complete journal management system that helps you create and maintain journal entries with automatic timestamp updates and home manager support.

## Features

- Create daily journal entries from a customizable template
- Automatic timestamp updating for journal entries
- Systemd service for monitoring and updating journal files
- Multiple installation options (Nix, Make, or manual)

## Project Structure

The project is organized into the following directories:

- `src/bin/` - Core script files
- `scripts/` - Install and uninstall scripts
- `nix/` - Nix configuration for home-manager

## Installation

Choose one of the following installation methods:

### Option 1: Using Nix

If you have Nix installed:

```bash
# Install to your profile
nix profile install .

# Or run directly without installing
nix run .
```

### Option 2: Using Make

For users who don't use Nix:

```bash
# Install scripts to ~/.local/bin
make install

# Install scripts and systemd service
make install-service

# Install to a different location
make install PREFIX=/usr/local

# Uninstall
make uninstall
make uninstall-service
```

### Option 3: Manual installation with shell scripts

```bash
# Install (interactive)
./scripts/install.sh

# Install with custom options
./scripts/install.sh --prefix=/usr/local --journal-dir=~/Journal

# Uninstall
./scripts/uninstall.sh
```

## Usage

### Create a journal entry

```bash
# Create a journal entry for today
cj

# Create and immediately edit the entry
cj -e

# Use a custom template
cj -t my-template.md

# Specify output directory
cj -d ~/Journal

# Show all options
cj --help
```

### Timestamp Monitor Service

The timestamp monitor service watches your journal directory and automatically updates the timestamp in the file's metadata when you modify an entry.

To manually install the service:

```bash
cj --install-service
```

To manually uninstall the service:

```bash
cj --uninstall-service
```

## Configuration

### Home-Manager Integration

Add to your `flake.nix` inputs:
```nix
{
  inputs = {
    journal-management = {
      url = "github:matgawin/cj";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };
}
```

Then create `cj.nix` and import into your `home.nix`:

```nix
# cj.nix
{
  inputs,
  config,
  ...
}: {
  imports = [
    inputs.journal-management.homeManagerModule.default
  ];

  services.journal-management = {
    enable = true;
    journalDirectory = "${config.home.homeDirectory}/Journal";
    enableTimestampMonitor = true;
    enableAutoCreation = true;
    autoCreationTime = "22:00";
    startDate = "2022-10-21";
  };
}
```

## Development

```bash
# Setup development environment using Nix
nix develop

# optional
direnv allow

# Run shellcheck on all shell scripts
shellcheck src/bin/*.sh scripts/*.sh
```

## Structure Details

### Nix Flake Structure

The Nix flake configuration is split across couple files for better maintainability:

- `flake.nix` - Main entry point that imports all other Nix files
- `nix/` - Home Manager module definitions