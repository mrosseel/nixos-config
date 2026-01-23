# nixtop Machine Configuration

## Architecture

The nixtop configuration is split into multiple files for maintainability:

- **configuration.nix**: Hardware-specific and boot configuration ONLY
  - DO NOT modify unless absolutely necessary (hardware changes, boot loader, kernel)
  - Contains: imports, platform, bootloader, kernel settings, hostname, state version
  - Does NOT import config.nix (that's done in flake.nix)

- **config.nix**: All nixtop-specific services, packages, and user configuration
  - Put most nixtop-specific configuration changes here
  - Imported by flake.nix (not by configuration.nix)
  - Contains: services, packages, users, locale, networking services, etc.

- **disko-config.nix**: Disk partitioning configuration (DO NOT TOUCH)

- **flake.nix** (top-level): Orchestrates all modules and imports
  - Imports both configuration.nix and config.nix
  - Also imports shared modules (desktop, openssh, python, ai, etc.)

## General Guidelines

- Most nixtop-specific configuration should go in **config.nix**
- Shared modules across machines go in **modules/** (imported by flake.nix)
- Keep hardware-specific configs in **configuration.nix**
- All module imports are managed in **flake.nix**, not in configuration.nix

## Making Changes

When adding new features:
1. Add to config.nix if it's nixtop-specific
2. Create a new module file if it's a self-contained feature
3. Add to flake.nix modules if it should be shared across machines
4. Only touch configuration.nix for hardware/boot changes

## Elgato USB Devices

Power-cycled USB devices need udev rules to restart their services on reconnect.

| Device | USB ID | Restarts |
|--------|--------|----------|
| Wave:3 | 0fd9:0070 | wireplumber (+ `node.always-process` rule) |
| StreamDeck MK.2 | 0fd9:0080 | streamdeck-daemon |

Config in `config.nix`: `services.udev.extraRules` triggers `systemd.user.services.*-restart`.

**Troubleshooting:**
```bash
systemctl --user restart wireplumber   # mic issues
systemctl --user restart streamdeck-daemon  # streamdeck issues
pactl list sources short | grep elgato  # check mic (want RUNNING/IDLE)
```
