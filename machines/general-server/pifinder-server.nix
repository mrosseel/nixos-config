# PiFinder update infrastructure from the pifinder-server flake input: the
# Attic cache at cache.pifinder.eu and the delta server at
# deltas.pifinder.eu. The module defaults are this server's values.
{
  services.pifinder-attic.enable = true;

  services.pifinder-differ = {
    enable = true;
    monitoring.prometheus = true;
    monitoring.grafanaDashboard = true;
  };
}
