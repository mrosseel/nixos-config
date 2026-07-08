{ pkgs, inputs, lib, ... }:
let
  authorizedKeys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOvpuaWhiyWISrRYXtOpBLo6Fo/+NzZ0812RHlorSuNF mike.rosseel@gmail.com"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGrPg9hSgxwg0EECxXSpYi7t3F/w/BgpymlD1uUDedRz mike@nixtop"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAKaG5LnWy8A0kPHbgisuxk7THjtMDBmSfpyDY5JcFdL mike@nixos"  # nix270
  ];
in
{
  services.openssh = {
    enable = true;
    # require public key authentication for better security
    settings.PasswordAuthentication = lib.mkDefault false;
    settings.KbdInteractiveAuthentication = false;
    settings.X11Forwarding = lib.mkDefault false;
    settings.PermitRootLogin = lib.mkDefault "no";
    settings.ClientAliveInterval = 30;
    settings.ClientAliveCountMax = 10;
  };
  users.users.root.openssh.authorizedKeys.keys = authorizedKeys;
  users.users.mike.openssh.authorizedKeys.keys = authorizedKeys;
}
