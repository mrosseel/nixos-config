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

    # Forward the kitty graphics protocol to the host terminal so image previews
    # (yazi and friends) render as pixels instead of dropping to the chafa/ASCII
    # fallback. Needs a host terminal that speaks the protocol -- kitty does,
    # foot only does sixel, which herdr does not pass through.
    [experimental]
    kitty_graphics = true
  '';
}
