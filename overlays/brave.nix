# overlays/brave.nix
#
# nixpkgs' Brave wrapper does not read ~/.config/brave-flags.conf, so the flags
# are folded into the package here. Applied as an overlay (rather than a one-off
# override) so omarchy-nix's brave package, its desktop entry, and the Super+B
# keybind all resolve to the same patched binary instead of a colliding plain one.
#
# commandLineArgs is appended after the wrapper's own flags. Chromium honours only
# the last --enable-features / --disable-features on the command line, so each list
# restates the wrapper defaults plus the additions.
#
# Text-selection/input freeze on Hyprland (brave-browser#45183): disabling the
# WaylandTextInputV3 feature alone did NOT stop it, because the nixpkgs wrapper
# hard-forces --enable-wayland-ime=true, so the Wayland IME machinery still engages
# and deadlocks the text-input on wlroots. We override that switch to false (last
# value on the cmdline wins), disabling the Wayland IME path entirely. Trade-off:
# no in-browser Wayland input-method (fcitx5/ibus CJK, IME compose); plain Latin
# typing and text selection work. WaylandTextInputV3 stays disabled belt-and-suspenders.
final: prev: {
  brave = prev.brave.override {
    commandLineArgs = builtins.concatStringsSep " " [
      # AcceleratedVideo* + WaylandWindowDecorations: wrapper defaults, restated.
      # TouchpadOverscrollHistoryNavigation: two-finger swipe back/forward.
      "--enable-features=AcceleratedVideoDecodeLinuxGL,AcceleratedVideoEncoder,WaylandWindowDecorations,TouchpadOverscrollHistoryNavigation"
      # OutdatedBuildDetector + UseChromeOSDirectVideoDecoder: wrapper defaults, restated.
      # WaylandWpColorManagerV1: Hyprland color-management crash workaround (hyprwm/Hyprland#11957).
      # WaylandTextInputV3: part of the text-selection freeze fix (brave-browser#45183).
      "--disable-features=OutdatedBuildDetector,UseChromeOSDirectVideoDecoder,WaylandWpColorManagerV1,WaylandTextInputV3"
      # Override the wrapper's forced --enable-wayland-ime=true; this is the switch
      # that actually stops the Hyprland text-selection/input freeze (#45183).
      "--enable-wayland-ime=false"
    ];
  };
}
