{ pkgs, ... }:

{
  environment.systemPackages = [
    (pkgs.symlinkJoin {
      name = "anydesk-x11";
      paths = [ pkgs.anydesk ];
      buildInputs = [ pkgs.makeWrapper ];
      postBuild = ''
        wrapProgram $out/bin/anydesk --set GDK_BACKEND x11
      '';
    })
    pkgs.nettools
  ];

  systemd.packages = [ pkgs.anydesk ];
  systemd.services.anydesk.wantedBy = [ "multi-user.target" ];
}
