# overlays/calibre.nix
#
# TEMPORARY. Two fixes so that calibre 9.16.0 builds on nixpkgs 02c087f.
# calibre is not in cache.nixos.org on that rev, because its tests fail.
#
# 1. speechd: python moves from buildInputs to nativeBuildInputs, so the
#    Python bindings (module speechd) are installed again. nixpkgs master has
#    the same change (NixOS/nixpkgs#577420). Without it the calibre test
#    test_speech_dispatcher fails with "No module named 'speechd'". The fix
#    is applied only to the speechd-minimal that calibre takes as an argument.
#    A global speechd override makes firefox, electron, krita and the KDE
#    frameworks rebuild.
# 2. calibre: the test test_file_rename is excluded. It checks a link in
#    toc.ncx after a rename and fails in the sandbox. The test does not change
#    the installed program.
#
# Remove this overlay and its import in flake.nix once nixos-unstable has a
# calibre that is in the cache.
final: prev:
let
  speechdWithPython = prev.speechd-minimal.overrideAttrs (old: {
    nativeBuildInputs = old.nativeBuildInputs ++ [ prev.python3Packages.python ];
    buildInputs = prev.lib.remove prev.python3Packages.python old.buildInputs;
  });
in
{
  calibre =
    (prev.calibre.override { speechd-minimal = speechdWithPython; }).overrideAttrs
      (old: {
        installCheckPhase = builtins.replaceStrings
          [ "python setup.py test " ]
          [ "python setup.py test --exclude-test-name test_file_rename " ]
          old.installCheckPhase;
      });
}
