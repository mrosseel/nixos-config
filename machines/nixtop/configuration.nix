# Hardware and boot configuration for nixtop
# DO NOT MODIFY unless necessary - put configuration in config.nix instead
{ config, pkgs, ... }:

{
  imports = [
    ./disko-config.nix
  ];

  # Set the system platform
  nixpkgs.hostPlatform = "x86_64-linux";

  # Enable flakes
  nix.settings.experimental-features = ["nix-command" "flakes"];

  # Bootloader - systemd-boot for UEFI
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Latest kernel for Framework Desktop
  boot.kernelPackages = pkgs.linuxPackages_latest;

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
  boot.kernelParams = [];

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
