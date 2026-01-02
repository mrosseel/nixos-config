# Installation Guide for nixtop (Framework Desktop)

This guide walks through installing NixOS on the Framework Desktop with btrfs, LUKS encryption, and disko.

## Hardware Specs
- **CPU**: AMD Ryzen 9 9950X
- **RAM**: 128GB
- **Storage**: 4TB NVMe (will be /dev/nvme0n1)
- **Machine**: Framework Desktop

## Prerequisites

1. **Create NixOS installation USB**:
   - Download latest NixOS unstable ISO (to get latest kernel for Ryzen 9950X)
   - Flash to USB drive: `dd if=nixos.iso of=/dev/sdX bs=4M status=progress`

2. **Boot from USB**:
   - Press F12 (or DEL) during boot to enter boot menu
   - Select USB drive
   - Boot into NixOS installer

## Installation Steps

### 1. Connect to Network

```bash
# For WiFi
sudo systemctl start wpa_supplicant
wpa_cli

# In wpa_cli:
> add_network
> set_network 0 ssid "YourSSID"
> set_network 0 psk "YourPassword"
> enable_network 0
> quit

# For Ethernet (should work automatically)
ping google.com  # Test connection
```

### 2. Set Up Encryption Password

```bash
# Create temporary password file for disko
echo "YourStrongPassword" > /tmp/secret.key
chmod 600 /tmp/secret.key
```

**IMPORTANT**: Remember this password! You'll need it every time you boot.

### 3. Clone Your Configuration

```bash
# Install git
nix-shell -p git

# Clone your config
git clone https://github.com/mrosseel/nixos-config /mnt/config
cd /mnt/config
```

### 4. Run Disko to Partition & Format

```bash
# This will:
# - Partition the 4TB NVMe drive
# - Create LUKS encrypted partition
# - Set up btrfs with subvolumes
# - Mount everything at /mnt

sudo nix --experimental-features "nix-command flakes" run github:nix-community/disko -- \
  --mode disko \
  /mnt/config/machines/nixtop/disko-config.nix
```

**This will DESTROY all data on /dev/nvme0n1!**

### 5. Install NixOS

```bash
# Copy your config to the new system
sudo mkdir -p /mnt/etc/nixos
sudo cp -r /mnt/config/* /mnt/etc/nixos/

# Install NixOS using the flake
sudo nixos-install --flake /mnt/config#nixtop

# Set root password when prompted
```

### 6. Reboot

```bash
sudo reboot
```

Remove the USB drive during reboot.

### 7. Post-Installation

After first boot:

```bash
# Update flake inputs
cd ~/nixos-config
nix flake update

# Rebuild to get latest packages
sudo nixos-rebuild switch --flake .#nixtop

# Set user password if not done
passwd mike
```

## Partition Layout

After disko runs, you'll have:

```
/dev/nvme0n1
├── /dev/nvme0n1p1  (1GB, FAT32, /boot)
└── /dev/nvme0n1p2  (~4TB, LUKS encrypted)
    └── /dev/mapper/crypted (btrfs)
        ├── @root      → /
        ├── @nix       → /nix
        ├── @home      → /home
        ├── @persist   → /persist
        └── @snapshots → /.snapshots
```

## Features Enabled

- ✅ **Encryption**: Full disk LUKS encryption
- ✅ **Compression**: zstd compression on all btrfs subvolumes
- ✅ **zram**: 5% (6.4GB) compressed swap in RAM
- ✅ **Desktop**: omarchy-nix (GNOME-based)
- ✅ **Bootloader**: systemd-boot
- ✅ **Hardware**: Framework Desktop AMD optimizations via nixos-hardware
- ✅ **Kernel**: Latest Linux kernel for Ryzen 9950X support

## Troubleshooting

### Boot Issues

If you can't boot:
1. Boot from USB again
2. Unlock encrypted partition: `cryptsetup luksOpen /dev/nvme0n1p2 crypted`
3. Mount btrfs: `mount -o subvol=@root /dev/mapper/crypted /mnt`
4. Mount boot: `mount /dev/nvme0n1p1 /mnt/boot`
5. Fix issues and reinstall: `nixos-install --flake /mnt/config#nixtop`

### Network Issues

If WiFi doesn't work after installation:
- Framework Desktop should have good Linux support
- Check `lspci | grep -i network` to identify WiFi card
- May need to add specific firmware packages

### Display Issues

If graphics are glitchy:
- Latest kernel should have good AMD support
- Try adding `boot.kernelParams = [ "amdgpu.sg_display=0" ];` if needed

## Updating the System

```bash
# Update and rebuild
cd ~/nixos-config
nix flake update
sudo nixos-rebuild switch --flake .#nixtop

# Or use the alias (defined in zsh config)
nixup
```

## Creating Snapshots

```bash
# Manual snapshot of @home
sudo btrfs subvolume snapshot /home /.snapshots/home-$(date +%Y%m%d-%H%M%S)

# List snapshots
sudo btrfs subvolume list /

# Restore from snapshot (boot from USB, mount, then):
sudo btrfs subvolume delete /mnt/@home
sudo btrfs subvolume snapshot /.snapshots/home-20250101-120000 /mnt/@home
```

## Next Steps

Consider setting up:
- Automatic btrfs snapshots with `snapper` or `btrbk`
- Backup strategy (btrfs send/receive to external drive)
- Additional user accounts
- Development tools and environments
