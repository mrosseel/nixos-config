{ pkgs, hostname ? "", ... }:
let
  # Mirror tmux.nix: workstations I sit at use ctrl+a; anything I SSH into
  # (servers, the Pi) keeps the default ctrl+b so a single prefix chord never
  # collides across hops. Keep this list in sync with tmux.nix's mainMachines.
  mainMachines = [ "nixtop" "airelon" "nix270" "nixair" ];
  isMain = builtins.elem hostname mainMachines;
  prefixKey = if isMain then "ctrl+a" else "ctrl+b";
in
{
  home.packages = [ pkgs.herdr ];

  xdg.configFile."herdr/config.toml".text = ''
    [keys]
    prefix = "${prefixKey}"
  '';
}
