{ pkgs, inputs, ... }:
{
  environment.systemPackages = [
    pkgs.claude-code
    pkgs.gemini-cli
  ]; 
}

