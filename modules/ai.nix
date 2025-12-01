{ pkgs, inputs, ... }:
{
  environment.systemPackages = [
    pkgs.claude-code
    # pkgs.gemini-cli  # Disabled due to CVE-2024-23342 in ecdsa dependency
  ];
}

