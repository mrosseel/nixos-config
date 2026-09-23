{ pkgs, lib, options, inputs, hostname ? "", ... }:
let
  # Mirror tmux.nix: workstations I sit at use ctrl+a; anything I SSH into
  # (servers, the Pi) keeps the default ctrl+b so a single prefix chord never
  # collides across hops. Keep this list in sync with tmux.nix's mainMachines.
  mainMachines = [ "nixtop" "airelon" "nix270" "nixair" ];
  isMain = builtins.elem hostname mainMachines;
  prefixKey = if isMain then "ctrl+a" else "ctrl+b";

  # Settings every host gets.
  baseSettings = {
    onboarding = false;
    keys.prefix = prefixKey;
    # Attention queue rather than grouping by space. Toggling this in the TUI
    # persists because the file is writable.
    ui.agent_panel_sort = "priority";
    experimental = {
      # Forward the kitty graphics protocol to the host terminal so image
      # previews (yazi and friends) render as pixels instead of dropping to
      # the chafa/ASCII fallback. Needs a host terminal that speaks the
      # protocol -- kitty does, foot only does sixel, which herdr does not
      # pass through.
      kitty_graphics = true;
      # Keep pane scrollback across full server restarts. Agent panes come
      # back with their history instead of a blank screen.
      pane_history = true;
    };
  };

  # Overrides on top of the Omarchy herdr config.
  omarchySettings = lib.recursiveUpdate baseSettings {
    keys = {
      # Omarchy also binds alt+1..9 to tabs; alt+1..9 focuses agents here.
      switch_tab = "prefix+1..9";
      # Omarchy's prefix+k closes a tab; prefix+j/k switch agents here.
      # prefix+shift+x is the herdr default.
      close_tab = "prefix+shift+x";
      next_agent = "prefix+j";
      previous_agent = "prefix+k";
      # alt+1..9 focuses agent row 1..9 (the Planck tmux layer sends these).
      indexed.agents = "alt";
    };
  };

  # Herdr rewrites config.toml itself (agent panel sort, onboarding state), so a
  # read-only /nix/store symlink makes every such write fail with EROFS and the
  # settings reset on restart. The file has to be a real, writable copy.
  #
  # omarchy-nix already solves this: it ships a pristine config under
  # ~/.local/share/omarchy/config and seeds a writable copy into ~/.config once
  # (home.activation.seedShippedUserConfigs). On those hosts we replace the
  # pristine source with the Omarchy config plus omarchySettings, so a single
  # seeder still owns the path and omarchy-refresh-config restores this merge.
  # Hosts without omarchy get an equivalent seeder below.
  #
  # Either way Nix stops controlling the live file after the first seed. Run
  # `omarchy-refresh-herdr` to apply a change here (it keeps a backup), or edit
  # ~/.config/herdr/config.toml directly and run `herdr server reload-config`.

  toml = pkgs.formats.toml { };
  configTemplate = toml.generate "herdr-config.toml" baseSettings;
  omarchyConfig = toml.generate "herdr-config.toml" (lib.recursiveUpdate
    (lib.importTOML "${inputs.omarchy-nix}/config/herdr/config.toml")
    omarchySettings);

  # The omarchy home-manager module defines config.omarchy.*; nixair and the
  # servers pull modules/home-manager without it.
  hasOmarchy = options ? omarchy;
in
{
  home.packages = [ pkgs.herdr ];

  home.file.".local/share/omarchy/config/herdr/config.toml" =
    lib.mkIf hasOmarchy { source = lib.mkForce omarchyConfig; };

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
