
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
      WorkingDirectory = "/home/mike/pifinder-eu-fasthtml/";
      ExecStart = "${pkgs.poetry}/bin/poetry run python main.py";
      Restart = "on-failure";
    };
  };
}
