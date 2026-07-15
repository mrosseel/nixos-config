# Override omarchy-shell idle timeouts (seconds before screensaver / lock).
#
# omarchy-nix vendors these in config/omarchy/shell.json (upstream defaults:
# screensaver 150, lock 300). The idle daemon reads that file directly with no
# per-user merge, so to change the timeouts we regenerate the whole file from
# the upstream default and override only the "idle" block.
{ lib, pkgs, inputs, ... }:
let
  base = lib.importJSON "${inputs.omarchy-nix}/config/omarchy/shell.json";
  merged = base // {
    idle = {
      screensaver = 60;   # blank/screensaver after 1 min idle
      lock = 120;         # lock after 2 min idle
    };
  };
in
{
  home.file.".local/share/omarchy/config/omarchy/shell.json".source =
    lib.mkForce (pkgs.writeText "omarchy-shell.json" (builtins.toJSON merged));
}
