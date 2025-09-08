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

# Create with verbose output (useful for encryption troubleshooting)
cj --verbose

# Create entry for specific date
cj --date 2024-01-15

# Migrate existing entries to encrypted format
cj --migrate-to-encrypted

# Use custom SOPS configuration
cj --sops-config /path/to/.sops.yaml
```

### Working with Encrypted Entries

Once encryption is set up, the journal system handles encryption automatically:

```bash
# Create encrypted entry (automatic if .sops.yaml exists)
cj -e

# Edit existing encrypted entry (uses sops automatically)
cj --open existing-entry.md

# View encrypted entry content
sops --decrypt journal.daily.2024.01.15.md

# Manually encrypt an unencrypted entry
sops --encrypt --in-place journal.daily.2024.01.15.md
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

## Encryption Support (SOPS)

This journal system supports automatic encryption of journal entries using [Mozilla SOPS](https://github.com/mozilla/sops) with Age encryption. This ensures your personal journal entries are encrypted at rest while remaining easy to edit.

### Quick Setup Guide

Here's a complete step-by-step guide to set up Age encryption with SOPS:

#### Step 1: Install Required Tools

```bash
# Install SOPS
https://github.com/getsops/sops

# Install Age
# On NixOS:
nix profile install nixpkgs#age

# On Arch:
sudo pacman -S age

# On Ubuntu/Debian:
sudo apt install age
```

#### Step 2: Generate Age Key Pair

```bash
# Create directory for Age keys
mkdir -p ~/.config/sops/age

# Generate a new Age key pair
age-keygen -o ~/.config/sops/age/keys.txt

# This will output something like:
# Public key: age1abc123def456...
# (The private key is saved to keys.txt)
```

**Important**: Save the public key that was printed - you'll need it in the next step!

#### Step 3: Create SOPS Configuration

Create a `.sops.yaml` file in your journal directory:

```bash
# Navigate to your journal directory
cd ~/Journal  # or wherever you keep your journal

# Create the SOPS configuration file
cat > .sops.yaml << 'EOF'
creation_rules:
  - path_regex: \.md$
    age: >-
      age1abc123def456...,
      age1xyz789ghi012...
    # Replace the above with your actual public key(s)
    # You can add multiple public keys separated by commas for shared access
EOF
```

**Replace `age1abc123def456...` with your actual public key from Step 2!**

#### Step 4: Set Age Key Environment

Add this to your shell profile (`~/.bashrc`, `~/.zshrc`, etc.):

```bash
# SOPS Age key configuration
export SOPS_AGE_KEY_FILE="$HOME/.config/sops/age/keys.txt"
```

Then reload your shell:
```bash
source ~/.bashrc  # or ~/.zshrc
```

#### Step 5: Test the Setup

```bash
# Test SOPS encryption
echo "test_data: hello world" | sops --encrypt --age $(grep public ~/.config/sops/age/keys.txt | cut -d' ' -f4) /dev/stdin

# Create a test journal entry to verify everything works
cd ~/Journal
cj --verbose

# If encryption is working, you should see:
# "SOPS encryption enabled and tested successfully"
# "Journal entry encrypted successfully"
```

#### Step 6: Migrate Existing Entries (Optional)

If you have existing unencrypted journal entries:

```bash
# Navigate to your journal directory
cd ~/Journal

# Migrate all existing .md files to encrypted format
cj --migrate-to-encrypted --verbose
```

### Advanced Configuration

#### Multiple Users/Keys

To share encrypted journal entries across multiple devices or users:

```yaml
# .sops.yaml
creation_rules:
  - path_regex: \.md$
    age: >-
      age1abc123def456...,
      age1device2key789...,
      age1backupkey012...
```

#### Key Rotation

To rotate your Age keys:

1. Generate a new key pair: `age-keygen -o ~/.config/sops/age/new_keys.txt`
2. Update `.sops.yaml` with the new public key
3. Re-encrypt existing files: `find . -name "*.md" -exec sops updatekeys {} \;`
4. Replace the old key file: `mv ~/.config/sops/age/new_keys.txt ~/.config/sops/age/keys.txt`

### Troubleshooting Encryption

#### Common Issues and Solutions

1. **"Error: sops command not found"**
   - Install SOPS following Step 1 above
   - Verify installation: `sops --version`

2. **"No key could decrypt"**
   - Check that `SOPS_AGE_KEY_FILE` is set correctly
   - Verify the private key file exists and is readable
   - Ensure the Age key in `.sops.yaml` matches your public key

3. **"No creation rule matched"**
   - Check that your `.sops.yaml` is in the journal directory
   - Verify the `path_regex` matches your file names (`.md` files)
   - Use `cj --verbose` to see detailed configuration checking

4. **"Failed to encrypt journal entry"**
   - Test SOPS manually: `echo "test: data" | sops --encrypt /dev/stdin`
   - Check `.sops.yaml` syntax with: `sops --encrypt --in-place .sops.yaml`
   - Verify file permissions on the journal directory

#### Getting Help

Use the verbose mode for detailed troubleshooting information:

```bash
cj --verbose
```

This will show:
- SOPS version and availability
- Configuration file validation
- Encryption functionality testing
- Detailed error messages with guidance

### Security Notes

- **Key Storage**: Keep your Age private key (`~/.config/sops/age/keys.txt`) secure and backed up
- **Key Sharing**: Only share public keys, never private keys
- **Backups**: Consider storing encrypted backups of your Age key in a password manager
- **Multiple Keys**: Use multiple Age keys for redundancy (different devices, backup keys)

## Common Workflows

### Setting Up Encryption for a New Journal

```bash
# 1. Navigate to your journal directory
cd ~/Journal

# 2. Create SOPS configuration (replace with your Age public key)
cat > .sops.yaml << 'EOF'
creation_rules:
  - path_regex: \.md$
    age: >-
      age1your_actual_public_key_here
EOF

# 3. Test the setup
cj --verbose

# 4. Create your first encrypted entry
cj -e
```

### Migrating Existing Journal to Encrypted Format

```bash
# 1. Navigate to existing journal directory
cd ~/Journal

# 2. Create SOPS configuration (see above)

# 3. Run migration (creates backup first)
cj --migrate-to-encrypted --verbose

# 4. Verify migration worked
# All .md files should now contain "sops:" metadata
grep -l "sops:" *.md
```

### Using Multiple Devices/Keys

```bash
# Generate keys on each device
age-keygen -o ~/.config/sops/age/keys.txt

# Update .sops.yaml with all public keys
cat > .sops.yaml << 'EOF'
creation_rules:
  - path_regex: \.md$
    age: >-
      age1device1_public_key,
      age1device2_public_key,
      age1backup_public_key
EOF

# Re-encrypt existing files for new keys
find . -name "*.md" -exec sops updatekeys {} \;
```

### Daily Usage (After Setup)

```bash
# Create today's entry (automatically encrypted if .sops.yaml exists)
cj

# Create and edit today's entry
cj -e

# Create entry for specific date
cj --date 2024-01-15

# Edit existing entry (will automatically detect if encrypted)
cj --open journal.daily.2024.01.15.md

# View encrypted entry content
sops --decrypt journal.daily.2024.01.15.md
```

### Troubleshooting Common Issues

```bash
# Check if encryption is working
cj --verbose

# Test SOPS manually
echo "test: data" | sops --encrypt /dev/stdin

# View detailed migration process
cj --migrate-to-encrypted --verbose

# Check for Age key environment
echo $SOPS_AGE_KEY_FILE
cat $SOPS_AGE_KEY_FILE
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
    
    # SOPS/Encryption support
    enableSopsSupport = true;  # Enable encryption support in services (default: true)
    sopsConfig = "${config.home.homeDirectory}/Journal/.sops.yaml";  # Optional: specify sops config path
    sopsAgeKeyFile = "${config.home.homeDirectory}/.config/sops/age/keys.txt";  # Optional: specify Age key file path
  };
}
```

#### Home-Manager SOPS Options

- `enableSopsSupport` - Enable SOPS encryption support for journal services (default: true)
- `sopsConfig` - Path to SOPS configuration file. If null, auto-detection is used
- `sopsAgeKeyFile` - Path to Age private key file. If null, uses SOPS_AGE_KEY_FILE environment variable or default location

## Testing

The project includes comprehensive integration tests for SOPS encryption:

```bash
# Run all tests (requires sops and age to be installed)
./scripts/run_tests.sh

# Run only SOPS integration tests
./scripts/test_sops_integration.sh
```

The test suite validates:
- SOPS detection and configuration
- Automatic encryption workflows
- Migration from unencrypted to encrypted
- Custom SOPS configuration paths
- Error handling and recovery
- Mixed environment support (encrypted + unencrypted files)
- Service integration
- Atomic operations

## Exit Codes

The `cj` command uses standard exit codes:

- `0` - Success
- `1` - General error (invalid arguments, missing files, etc.)
- `2` - SOPS/encryption related errors
- `3` - Configuration errors
- `4` - Service management errors

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