# Portable AI coding-agent CLIs shared across every host, macOS included.
# Kept separate from ai.nix (the full Linux/GPU workstation stack: ollama +
# ROCm, opencode, amdgpu VRAM tooling) so airelon can pull just the codex CLI
# without dragging in Linux-only options. ai.nix imports this base.
#
# codex ships from the codex-cli-nix flake input. Agent multiplexers (herdr)
# label a pane by the basename of the foreground process's argv[0]. The
# upstream codex-cli-nix wrapper execs "codex-raw", so herdr sees "codex-raw"
# and never labels the pane as codex. Re-exec with argv[0] = "codex" while
# keeping the upstream wrapper's env/PATH setup.
{ pkgs, inputs, ... }:
let
  codex-cli = inputs.codex-cli-nix.packages.${pkgs.stdenv.hostPlatform.system}.default;
  codex-cli-argv0 = pkgs.symlinkJoin {
    name = "codex-argv0-fixed";
    paths = [ codex-cli ];
    postBuild = ''
      rm -f $out/bin/codex
      sed 's|^exec "|exec -a codex "|' ${codex-cli}/bin/codex > $out/bin/codex
      chmod +x $out/bin/codex
    '';
  };
in
{
  environment.systemPackages = [ codex-cli-argv0 ];
}
