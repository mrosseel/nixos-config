{ config, lib, pkgs, modulesPath, ... }:

{
  imports = [
    (modulesPath + "/profiles/qemu-guest.nix")
  ];

  nixpkgs.hostPlatform = "x86_64-linux";

  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    trusted-users = [ "root" "mike" ];
  };

  boot.loader.grub.enable = true;
  boot.loader.grub.device = "/dev/sda";
  boot.tmp.cleanOnBoot = true;
  zramSwap.enable = true;

  boot.initrd.availableKernelModules = [ "ata_piix" "uhci_hcd" "virtio_pci" "virtio_scsi" "sd_mod" "sr_mod" ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ ];
  boot.extraModulePackages = [ ];

  fileSystems."/" = {
    device = "/dev/disk/by-label/nixos";
    fsType = "ext4";
  };

  networking.hostName = "proxnix";
  networking.useDHCP = false;
  networking.interfaces.ens18 = {
    ipv4.addresses = [{
      address = "192.168.5.12";
      prefixLength = 24;
    }];
  };
  networking.defaultGateway = "192.168.5.1";
  networking.nameservers = [ "192.168.5.1" "8.8.8.8" ];

  services.qemuGuest.enable = true;

  system.stateVersion = "24.11";
}
