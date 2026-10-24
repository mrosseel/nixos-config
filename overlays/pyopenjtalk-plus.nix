# overlays/pyopenjtalk-plus.nix
#
# TEMPORARY. Adds the test fix for Cython 3.3.0 to python3Packages.pyopenjtalk-plus.
#
# Reason: on nixpkgs 02c087f one test of pyopenjtalk-plus 0.4.1-post9 fails
# (test_run_njd_from_mecab_invalid_input_should_not_break_next_call), because
# Cython 3.3.0 changed the TypeError message. The build is not in
# cache.nixos.org, and neither are piper-tts and calibre, which depend on it.
# nixpkgs master has the same patch (NixOS/nixpkgs PR 576063).
#
# Remove this overlay and its import in flake.nix once nixos-unstable has the
# patch.
final: prev: {
  pythonPackagesExtensions = prev.pythonPackagesExtensions ++ [
    (pyfinal: pyprev: {
      pyopenjtalk-plus = pyprev.pyopenjtalk-plus.overrideAttrs (old: {
        patches = (old.patches or [ ]) ++ [
          (prev.fetchpatch {
            name = "fix-cython-3.3.0.patch";
            url = "https://github.com/tsukumijima/pyopenjtalk-plus/commit/90b644f9e9d397882e6eafe4dcd1843a4fde6a63.patch";
            includes = [ "tests/test_frontend.py" ];
            hash = "sha256-Jb7T/bRUHxqwBLwV6xYC/teaFHm5GmqJxA7sCX+oiNI=";
          })
        ];
      });
    })
  ];
}
