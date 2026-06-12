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

  # Kernel + firmware sourced from nixpkgs-kernel input. Pinned to the same rev as the
  # main nixpkgs so the kernel's passthru (buildDTBs, target, ...) matches what the
  # NixOS modules expect — an older pin skews and fails eval on those attrs.
  # Currently tracking 7.0.12 — earlier 6.19.10 pin still hung amdgpu (sdma timeouts,
  # MODE2 resets), so tracking the latest 7.0.x in case newer SMU/DCN3.5 paths are healthier.
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

    # Strong host model. nixtop is dual-homed on 192.168.5.0/24 (wired enp191s0
    # + Wi-Fi wlan0). With the default weak host model it answered/announced the
    # wired IP (.170) out the Wi-Fi MAC too, so the router's ARP entry flipped
    # to Wi-Fi and the cable intermittently "dropped". These pin each IP to its
    # own NIC, so both interfaces can stay up safely.
    "net.ipv4.conf.all.arp_ignore" = 1;
    "net.ipv4.conf.all.arp_announce" = 2;
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
  # INFO instead of default WARN: keeps NM logging link/DHCP events while we
  # monitor the intermittent wired-drop issue (ARP flux from dual-homing).
  networking.networkmanager.logLevel = "INFO";

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  # State version
  system.stateVersion = "25.05";
}
