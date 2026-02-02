{ pkgs, inputs, lib, ... }:
{
  services.openssh = {
    enable = true;
    # require public key authentication for better security
    settings.PasswordAuthentication = false;
    settings.KbdInteractiveAuthentication = false;
    settings.X11Forwarding = lib.mkDefault false;
    settings.PermitRootLogin = lib.mkDefault "no";
  };
  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOvpuaWhiyWISrRYXtOpBLo6Fo/+NzZ0812RHlorSuNF mike.rosseel@gmail.com"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGrPg9hSgxwg0EECxXSpYi7t3F/w/BgpymlD1uUDedRz mike@nixtop"
  ];
  users.users.mike.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOvpuaWhiyWISrRYXtOpBLo6Fo/+NzZ0812RHlorSuNF mike.rosseel@gmail.com"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGrPg9hSgxwg0EECxXSpYi7t3F/w/BgpymlD1uUDedRz mike@nixtop"
  ];
}
