# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Architecture Overview

This is a NixOS configuration repository using flakes to manage multiple machines and home-manager for dotfiles. The configuration is structured as follows:

- **flake.nix**: Main entry point defining all system configurations, inputs, and outputs
- **machines/**: Machine-specific configurations for different systems
  - `airelon` (Darwin/macOS ARM64)
  - `nix270` (NixOS desktop)
  - `nixair` (NixOS desktop with omarchy-nix)
  - `nixtop` (NixOS desktop - Framework Desktop with AMD Ryzen AI 395, 128GB RAM, 4TB disk, AI workload optimized)
  - `general-server` (NixOS server)
  - `piDSC` (home-manager only for ARM64 Linux)
- **modules/**: Reusable configuration modules
  - `darwin/`: macOS-specific configurations
  - `home-manager/`: User environment and dotfiles
  - Various service modules (openssh, mail server, etc.)
- **config/**: Application configurations (symlinked via home-manager)
  - `nvim/`: Neovim configuration using lazy.nvim
  - `streamdeck/`: StreamDeck UI button configurations

## Common Commands

### Building and Switching Configurations

For NixOS systems:
```bash
# Switch current system
sudo nixos-rebuild switch --flake ~/nixos-config/.#

# Switch specific machine
sudo nixos-rebuild switch --flake ~/nixos-config/.#nixair

# Build without switching
sudo nixos-rebuild build --flake ~/nixos-config/.#
```

For macOS (Darwin):
```bash
# Switch Darwin configuration
sudo darwin-rebuild switch --flake ~/nixos-config/.#airelon
```

### Updating and Maintenance

```bash
# Update flake inputs
nix flake update

# Update and rebuild (aliases defined in zsh config)
nixup      # NixOS update and rebuild
nixupmac   # macOS update and rebuild
```

### Useful Aliases (defined in home-manager)

- `nixsw`: `sudo nixos-rebuild switch --flake ~/nixos-config/.#`
- `nixswmac`: `sudo darwin-rebuild switch --flake ~/nixos-config/.#`
- `nixup`: Update flake and rebuild NixOS
- `nixupmac`: Update flake and rebuild macOS

## Key Configuration Details

### User Configuration
- Primary user: `mike`
- Shell: zsh with starship prompt
- Editor: neovim (custom configuration in config/nvim/)

### System Features
- Home-manager integration for all systems
- Flakes enabled with experimental features
- SSH key-based authentication (no password auth)
- Shared nixpkgs configuration with unfree packages allowed

### Darwin-specific
- Aerospace window manager
- Homebrew integration for casks/brews
- Custom macOS system defaults and preferences

### NixOS-specific
- Multiple desktop environments (GNOME on nixair)
- Server configurations with Caddy and mail services
- Auto-update service for server deployments

## Development Notes

When modifying configurations:
1. Test changes with `nixos-rebuild build` before switching
2. Each machine has its own configuration file but shares common modules
3. Home-manager configurations are shared across all systems
4. The omarchy-nix input is used for the nixair machine configuration