# PiFinder update infrastructure from the pifinder-server flake input: the
# Attic cache at cache.pifinder.io and the delta server at deltas.pifinder.io.
# The .eu names stay as aliases, because devices in the field use them.
{
  services.pifinder-attic = {
    enable = true;
    domain = "cache.pifinder.io";
  };
  services.caddy.virtualHosts."cache.pifinder.io".serverAliases = [ "cache.pifinder.eu" ];

  services.pifinder-differ = {
    enable = true;
    domain = "deltas.pifinder.io";
    monitoring.prometheus = true;
    monitoring.grafanaDashboard = true;
  };
  services.caddy.virtualHosts."deltas.pifinder.io".serverAliases = [ "deltas.pifinder.eu" ];
}
