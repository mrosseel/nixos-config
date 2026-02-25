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
      ExecStart = "${pkgs.nix}/bin/nix develop --command uv run shop_page.py --prod";
      Restart = "on-failure";
    };
  };

  systemd.services.starnightsshop = {
    description = "StarNights Shop";
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];
    environment = {
      NODE_ENV = "production";
    };
    path = [ pkgs.bash pkgs.nodejs ];
    serviceConfig = {
      Type = "simple";
      User = "mike";
      Group = "mike";
      WorkingDirectory = "/home/mike/starnights_shop/";
      ExecStart = "${pkgs.bash}/bin/bash -c '${pkgs.nodejs}/bin/npm start'";
      Restart = "on-failure";
      RestartSec = 5;
    };
  };
}
