{ pkgs, lib, options, hostname ? "", ... }:
let
  # Mirror tmux.nix: workstations I sit at use ctrl+a; anything I SSH into
  # (servers, the Pi) keeps the default ctrl+b so a single prefix chord never
  # collides across hops. Keep this list in sync with tmux.nix's mainMachines.
  mainMachines = [ "nixtop" "airelon" "nix270" "nixair" ];
  isMain = builtins.elem hostname mainMachines;
  prefixKey = if isMain then "ctrl+a" else "ctrl+b";

  # Herdr rewrites config.toml itself (agent panel sort, onboarding state), so a
  # read-only /nix/store symlink makes every such write fail with EROFS and the
  # settings reset on restart. The file has to be a real, writable copy.
  #
  # omarchy-nix already solves this: it ships a pristine config under
  # ~/.local/share/omarchy/config and seeds a writable copy into ~/.config once
  # (home.activation.seedShippedUserConfigs). On those hosts we only swap the
  # pristine source for our own, so a single seeder still owns the path and
  # omarchy-refresh-config restores this config instead of the upstream one.
  # Hosts without omarchy get an equivalent seeder below.
  #
  # Either way Nix stops controlling the live file after the first seed. Edit
  # ~/.config/herdr/config.toml directly, then run `herdr server reload-config`.
  configTemplate = pkgs.writeText "herdr-config.toml" ''
    [keys]
    prefix = "${prefixKey}"

    [ui]
    # Attention queue rather than grouping by space. Toggling this in the TUI
    # persists now that the file is writable.
    agent_panel_sort = "priority"

    [experimental]
    # Forward the kitty graphics protocol to the host terminal so image previews
    # (yazi and friends) render as pixels instead of dropping to the chafa/ASCII
    # fallback. Needs a host terminal that speaks the protocol -- kitty does,
    # foot only does sixel, which herdr does not pass through.
    kitty_graphics = true
    # Keep pane scrollback across full server restarts. Agent panes come back
    # with their history instead of a blank screen.
    pane_history = true
  '';

  # The omarchy home-manager module defines config.omarchy.*; nixair and the
  # servers pull modules/home-manager without it.
  hasOmarchy = options ? omarchy;
in
{
  home.packages = [ pkgs.herdr ];

  home.file.".local/share/omarchy/config/herdr/config.toml" =
    lib.mkIf hasOmarchy { source = lib.mkForce configTemplate; };

  home.activation.seedHerdrConfig = lib.mkIf (!hasOmarchy) (
    lib.hm.dag.entryAfter [ "linkGeneration" ] ''
      herdrConfig="$HOME/.config/herdr/config.toml"
      if [ ! -e "$herdrConfig" ]; then
        echo "Seeding $herdrConfig from the Nix template"
        mkdir -p "$(dirname "$herdrConfig")"
        install -m 0644 ${configTemplate} "$herdrConfig"
      fi
    ''
  );
}
