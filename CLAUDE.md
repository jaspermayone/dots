# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

This is a Nix configuration repository using nix-darwin for macOS system configuration and home-manager for user environment management. The repository is structured as a flake-based Nix configuration that can be applied to multiple machines.

## Common Commands

### Apply Configuration
```bash
# Build and switch to new configuration (requires sudo)
darwin-rebuild switch --flake .

# Build configuration without switching (useful for testing)
darwin-rebuild build --flake .

# Check if configuration builds successfully
nix flake check
```

### Development Workflow
```bash
# Validate flake syntax and check for errors
nix flake check

# Show what will be built/downloaded
darwin-rebuild build --flake . --dry-run

# Update flake inputs (updates flake.lock)
nix flake update

# Update specific input
nix flake update nixpkgs
```

## Architecture

### Directory Structure
- `flake.nix` - Main flake configuration defining machine configurations
- `machines/` - Machine-specific configurations
  - `machines/remus/` - Configuration for the "remus" macbook
    - `configuration.nix` - System-level configuration
    - `home.nix` - User-level configuration
- `modules/` - Reusable configuration modules organized by category:
  - `development/` - Development tools and environments (Node.js, Python, Docker, Git)
  - `system/` - Core system configurations (shell, networking, base packages)
  - `users/` - User account and SSH key management
  - `services/` - Background services (cron jobs)

### Module System
The configuration uses a modular approach where `modules/default.nix` exports organized categories of modules that can be imported by machine configurations. Each module is self-contained and focuses on a specific aspect of the system.

### Key Features
- **Git Configuration**: Comprehensive Git setup with aliases, delta for better diffs, and GitHub CLI
- **Development Environment**: Node.js 20, Python 3, Docker with convenient aliases
- **System Preferences**: Consistent macOS defaults across machines (Dock, Finder settings)
- **User Management**: Automated user setup with SSH key configuration
- **Shell Environment**: Zsh with development-focused aliases and customizations

### Adding New Machines
1. Create `machines/[machine-name]/configuration.nix` and `machines/[machine-name]/home.nix`
2. Import appropriate modules from `modules/default.nix`
3. Add machine configuration to `flake.nix` in `darwinConfigurations`
4. Set machine-specific settings like hostname and architecture

### Testing Changes
Always run `nix flake check` before applying changes to validate syntax and configuration integrity. Use `darwin-rebuild build --flake . --dry-run` to preview what will change without applying.