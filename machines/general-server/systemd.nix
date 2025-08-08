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
      ExecStart = "${pkgs.uv}/bin/uv run --python ${pkgs.python313}/bin/python3 shop_page.py --prod";
      Restart = "on-failure";
    };
    environment = {
      # Allow dynamic linking
      LD_LIBRARY_PATH = "${pkgs.stdenv.cc.cc.lib}/lib:${pkgs.glibc}/lib";
    };
  };
}
