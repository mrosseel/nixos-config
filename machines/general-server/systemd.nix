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
      # Allow dynamic linking - includes libraries needed for WeasyPrint
      LD_LIBRARY_PATH = pkgs.lib.makeLibraryPath [
        pkgs.stdenv.cc.cc.lib
        pkgs.glib
        pkgs.gobject-introspection
        pkgs.pango
        pkgs.cairo
        pkgs.gdk-pixbuf
        pkgs.harfbuzz
        pkgs.fontconfig
        pkgs.freetype
      ];
    };
  };
}
