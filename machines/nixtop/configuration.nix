# Hardware and boot configuration for nixtop
# DO NOT MODIFY unless necessary - put configuration in config.nix instead
{ config, lib, pkgs, inputs, ... }:

{
  imports = [
    ./disko-config.nix
  ];

  # Set the system platform
  nixpkgs.hostPlatform = "x86_64-linux";

  # Bootloader - systemd-boot for UEFI
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Kernel + firmware sourced from nixpkgs-kernel input (nixpkgs-unstable 01fbdee, 2026-04).
  # Currently tracking 7.0.1 — earlier 6.19.10 pin still hung amdgpu (sdma timeouts, MODE2
  # resets), so trying the latest in case newer SMU/DCN3.5 paths are healthier.
  boot.kernelPackages =
    let kernelPkgs = import inputs.nixpkgs-kernel { system = "x86_64-linux"; config = config.nixpkgs.config; };
    in kernelPkgs.linuxPackages_7_0;

  hardware.firmware = let
    kernelPkgs = import inputs.nixpkgs-kernel { system = "x86_64-linux"; config = config.nixpkgs.config; };
  in [ kernelPkgs.linux-firmware ];

  # AMD Ryzen AI 395 iGPU - AI workload optimized via TTM
  # Based on: https://strixhalo.wiki/AI/AI_Capabilities_Overview#memory-limits
  # 64GB allocation: pages_limit=16777216 (64 * 1024 * 1024 * 1024 / 4096)
  # 120GB allocation: pages_limit=31457280 (120GB with headroom)
  # VRAM: vramlimit in MB (65536 MB = 64GB for AI/GPU workloads)
  boot.extraModprobeConfig = ''
    options amdgpu vm_fragment_size=8 vramlimit=65536
    options ttm pages_limit=16777216
  '';

  # Optional: disable IOMMU for ~6% memory read performance gain
  # boot.kernelParams = [ "amd_iommu=off" ];
  # Optional: Increase VRAM allocation (if BIOS doesn't expose setting)
  # boot.kernelParams = [ "amdgpu.umafbsize=4096M" ];  # 4GB VRAM
  boot.kernelParams = [
    "printk.always_kmsg_dump=1"
    # Workaround for Strix Halo SMU wedge on VPE power-gate (msg_reg: 32 timeout)
    # causing GPU hangs / full freezes. Disables only the VPE_v6_1 IP block (bit 11
    # in detection order — verify in dmesg after kernel bumps). Mask = 0xffffffff
    # with bit 11 cleared. Revisit when vpe_v6_1 SMU path is fixed upstream.
    "amdgpu.ip_block_mask=0xfffff7ff"
  ];

  # Plymouth (enabled by omarchy-nix) hijacks the LUKS password prompt in
  # the systemd initrd and renders nothing on simpledrm before amdgpu loads,
  # producing a black screen with no visible prompt.
  boot.plymouth.enable = lib.mkForce false;

  # Panic on lockups/oops so pstore captures a record, then auto-reboot.
  # systemd-pstore.service archives /sys/fs/pstore to /var/lib/systemd/pstore on next boot.
  boot.kernel.sysctl = {
    "kernel.panic" = 10;
    "kernel.panic_on_oops" = 1;
    "kernel.softlockup_panic" = 1;
    "kernel.hardlockup_panic" = 1;
  };

  # AMD GPU - Vulkan and OpenGL (RADV is enabled by default)
  hardware.graphics = {
    enable = true;
    enable32Bit = true;  # For 32-bit applications/games
    extraPackages = with pkgs; [
      rocmPackages.clr.icd  # ROCm OpenCL
    ];
  };

  # zram swap - 5% of 128GB RAM (~6.4GB)
  zramSwap = {
    enable = true;
    memoryPercent = 5;
  };

  # Hostname
  networking.hostName = "nixtop";
  networking.networkmanager.enable = true;

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  # State version
  system.stateVersion = "25.05";
}
