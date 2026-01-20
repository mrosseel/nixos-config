{ pkgs, inputs, ... }:
{
  systemd.services.pifinderhtml = {
    description = "PiFinder FastHTML website";
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];
    serviceConfig = {
      Type = "simple";
      User = "mike";
      Group = "mike";
      WorkingDirectory = "/home/mike/pifinder_shopping/";
      # Run inside the flake's dev shell - same environment as local dev
      ExecStart = "${pkgs.nix}/bin/nix develop --command uv run shop_page.py --prod";
      Restart = "on-failure";
    };
  };
}
