# overlays/brave.nix
#
# nixpkgs' Brave wrapper does not read ~/.config/brave-flags.conf, so the flags
# are folded into the package here. Applied as an overlay (rather than a one-off
# override) so omarchy-nix's brave package, its desktop entry, and the Super+B
# keybind all resolve to the same patched binary instead of a colliding plain one.
#
# commandLineArgs is appended after the wrapper's own flags. Chromium honours only
# the last --enable-features / --disable-features on the command line, so each list
# restates the wrapper defaults plus the additions. --enable-wayland-ime=true is a
# separate switch set by the wrapper and stays enabled.
final: prev: {
  brave = prev.brave.override {
    commandLineArgs = builtins.concatStringsSep " " [
      # AcceleratedVideo* + WaylandWindowDecorations: wrapper defaults, restated.
      # TouchpadOverscrollHistoryNavigation: two-finger swipe back/forward.
      "--enable-features=AcceleratedVideoDecodeLinuxGL,AcceleratedVideoEncoder,WaylandWindowDecorations,TouchpadOverscrollHistoryNavigation"
      # OutdatedBuildDetector + UseChromeOSDirectVideoDecoder: wrapper defaults, restated.
      # WaylandWpColorManagerV1: Hyprland color-management crash workaround (hyprwm/Hyprland#11957).
      # WaylandTextInputV3: fixes intermittent text-selection/input freeze on wlroots (brave-browser#45183).
      "--disable-features=OutdatedBuildDetector,UseChromeOSDirectVideoDecoder,WaylandWpColorManagerV1,WaylandTextInputV3"
    ];
  };
}
