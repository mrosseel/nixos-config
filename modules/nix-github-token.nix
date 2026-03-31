{ config, lib, ... }:
let
  # Each machine's user needs ~/.config/nix/access-tokens.conf containing:
  #   access-tokens = github.com=ghp_YOUR_TOKEN_HERE
  # Generate a token at https://github.com/settings/tokens (no scopes needed)
  # Or run: gh auth login && gh auth token
  tokenFile = "/home/mike/.config/nix/access-tokens.conf";
in {
  nix.extraOptions = ''
    !include ${tokenFile}
  '';
}
