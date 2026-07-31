{ config, pkgs, lib, ... }:

# Weather refresh behind the live dashboard on https://spain2026.miker.be .
#
# The site is a plain file_server, so the data it reads has to be sitting in the
# web root as static JSON. A timer fetches it instead of the browser because
# aviationweather.gov sends no CORS header at all, and because Open-Meteo's free
# tier should not take a request per visitor. Writes are atomic and failures are
# non-fatal, so the page keeps serving the last good fetch.
#
# Input:  /var/www/spain2026.miker.be/data/sites.json  (from the content rsync)
# Output: forecast.json, metar.json, updated.json      (beside it)

let
  webRoot = "/var/www/spain2026.miker.be";
in {
  # ReadWritePaths cannot namespace a directory that does not exist yet, so the
  # unit fails at NAMESPACE rather than skipping cleanly on a machine that has
  # not had the content rsync run. Create it up front.
  systemd.tmpfiles.rules = [
    "d ${webRoot}/data 0755 mike users - -"
  ];

  systemd.services.spain2026-weather = {
    description = "Refresh spain2026.miker.be forecast and METAR data";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    serviceConfig = {
      Type = "oneshot";
      User = "mike";
      Group = "users";
      # Skip cleanly until the content deploy has put sites.json in place,
      # so a fresh machine does not log failures before the first rsync.
      ExecCondition = "${pkgs.coreutils}/bin/test -f ${webRoot}/data/sites.json";
      ExecStart = "${pkgs.python3}/bin/python3 ${./spain2026-weather.py}";
      # ProtectSystem=strict plus a bare python3 means urllib has no CA bundle
      # to fall back on, so point it at one explicitly.
      Environment = [
        "SPAIN2026_WEB=${webRoot}"
        "SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
      ];
      TimeoutStartSec = "10m";
      PrivateTmp = true;
      ProtectSystem = "strict";
      ReadWritePaths = [ "${webRoot}/data" ];
      ProtectHome = "read-only";
      NoNewPrivileges = true;
    };
  };

  # The timer fires at the fastest rate the schedule ever needs and the script
  # decides whether a run is due, so the cadence ramp -- 20 min a fortnight out,
  # 5 min from three days -- lives in one place next to the budget it has to fit,
  # and a skipped run costs a process start rather than an API call.
  systemd.timers.spain2026-weather = {
    description = "Refresh spain2026.miker.be weather data (cadence set by the script)";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "2m";
      OnUnitActiveSec = "5m";
      # Spread load off the exact minute; Open-Meteo is a free service.
      RandomizedDelaySec = "45s";
      Persistent = true;
    };
  };
}
