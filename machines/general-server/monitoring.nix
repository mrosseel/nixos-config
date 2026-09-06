{ config, pkgs, lib, ... }:

let
  # One list of public endpoints. The blackbox scrape jobs and the Home
  # Assistant push both read it, so the two can no longer disagree about
  # which sites exist.
  #
  # `codes` are the HTTP statuses that mean healthy. thailand sits behind
  # basic auth and deltas refuses a bare root, so their normal answer is
  # 401 and 403.
  siteDefs = [
    { host = "miker.be"; icon = "mdi:web"; }
    { host = "astro.miker.be"; icon = "mdi:telescope"; }
    { host = "astro.miker.be"; path = "/api/tonight"; icon = "mdi:api"; name = "astro API"; }
    { host = "sun.miker.be"; icon = "mdi:weather-sunny"; }
    { host = "messier.miker.be"; icon = "mdi:star-shooting"; }
    { host = "asterisms.miker.be"; icon = "mdi:vector-triangle"; }
    { host = "blog.miker.be"; icon = "mdi:post"; }
    { host = "mars.miker.be"; icon = "mdi:rocket-launch"; }
    { host = "dice.miker.be"; icon = "mdi:dice-5"; }
    { host = "spain2026.miker.be"; icon = "mdi:weather-night"; }
    { host = "hiddentreasures.miker.be"; icon = "mdi:treasure-chest"; }
    { host = "rays.miker.be"; icon = "mdi:moon-waning-crescent"; }
    { host = "hextopia.miker.be"; path = "/healthz"; icon = "mdi:hexagon-multiple"; name = "hextopia"; }
    { host = "joeri.miker.be"; icon = "mdi:account"; }
    { host = "1901.miker.be"; icon = "mdi:calendar"; }
    { host = "shop.starnights.be"; icon = "mdi:cart"; }
    { host = "pifinder.eu"; icon = "mdi:compass"; }
    { host = "catalogs.pifinder.eu"; icon = "mdi:book-open-variant"; }
    { host = "cache.pifinder.eu"; icon = "mdi:package-variant"; }
    { host = "files.pifinder.eu"; icon = "mdi:file-download"; }
    { host = "deltas.pifinder.eu"; icon = "mdi:delta"; codes = [ 403 ]; }
    { host = "thailand.miker.be"; icon = "mdi:map-marker-path"; codes = [ 401 ]; }
  ];

  mkSite = s:
    let
      path = s.path or "/";
      url = "https://${s.host}${path}";
      slug = lib.replaceStrings [ "." "/" "-" ":" ] [ "_" "_" "_" "_" ] "${s.host}${path}";
    in
    {
      inherit url;
      id = lib.removeSuffix "_" slug;
      name = s.name or s.host;
      icon = s.icon or "mdi:web";
      codes = s.codes or [ 200 ];
    };

  sites = map mkSite siteDefs;

  # Blackbox needs one module per set of acceptable status codes.
  codeSets = lib.unique (map (s: s.codes) sites);
  moduleName = codes: "http_" + lib.concatMapStringsSep "_" toString codes;

  blackboxModules = lib.listToAttrs (map
    (codes: lib.nameValuePair (moduleName codes) {
      prober = "http";
      timeout = "10s";
      http = {
        valid_http_versions = [ "HTTP/1.1" "HTTP/2.0" ];
        valid_status_codes = codes;
        follow_redirects = true;
      };
    })
    codeSets);

  blackboxJobs = map
    (codes: {
      # The plain-200 job keeps its old name so 30 days of history stay
      # attached to the same job label.
      job_name = if codes == [ 200 ] then "blackbox-sites" else "blackbox-${moduleName codes}";
      metrics_path = "/probe";
      params.module = [ (moduleName codes) ];
      static_configs = [{
        targets = map (s: s.url) (lib.filter (s: s.codes == codes) sites);
      }];
      scrape_interval = "60s";
      relabel_configs = [
        { source_labels = [ "__address__" ]; target_label = "__param_target"; }
        { source_labels = [ "__param_target" ]; target_label = "instance"; }
        { target_label = "__address__"; replacement = "127.0.0.1:9115"; }
      ];
    })
    codeSets;

  # url|entity id|icon|friendly name, one per line, read by the push script.
  siteTable = lib.concatMapStringsSep "\n" (s: "${s.url}|${s.id}|${s.icon}|${s.name}") sites;

  alertRules = {
    groups = [
      {
        name = "availability";
        rules = [
          {
            alert = "SiteDown";
            expr = "probe_success == 0";
            "for" = "3m";
            labels.severity = "critical";
            annotations.summary = "{{ $labels.instance }} does not answer";
          }
          {
            alert = "SiteSlow";
            expr = "probe_duration_seconds > 5";
            "for" = "10m";
            labels.severity = "warning";
            annotations.summary = "{{ $labels.instance }} takes over 5s to answer";
          }
          {
            alert = "ScrapeTargetDown";
            expr = "up == 0";
            "for" = "5m";
            labels.severity = "critical";
            annotations.summary = "Prometheus cannot scrape {{ $labels.job }} at {{ $labels.instance }}";
          }
          {
            alert = "CaddyUpstreamDown";
            expr = "caddy_reverse_proxy_upstreams_healthy == 0";
            "for" = "3m";
            labels.severity = "critical";
            annotations.summary = "Backend {{ $labels.upstream }} is unhealthy";
          }
          {
            alert = "CaddyConfigReloadFailed";
            expr = "caddy_config_last_reload_successful == 0";
            "for" = "5m";
            labels.severity = "warning";
            annotations.summary = "Caddy rejected its last config reload";
          }
        ];
      }
      {
        name = "tls";
        rules = [
          {
            alert = "CertExpiringSoon";
            expr = "(probe_ssl_earliest_cert_expiry - time()) / 86400 < 14";
            "for" = "1h";
            labels.severity = "warning";
            annotations.summary = "TLS certificate for {{ $labels.instance }} expires in under 14 days";
          }
          {
            alert = "CertExpiringCritical";
            expr = "(probe_ssl_earliest_cert_expiry - time()) / 86400 < 3";
            "for" = "10m";
            labels.severity = "critical";
            annotations.summary = "TLS certificate for {{ $labels.instance }} expires in under 3 days";
          }
        ];
      }
      {
        name = "host";
        rules = [
          {
            alert = "DiskSpaceLow";
            expr = ''100 - (node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"} * 100) > 85'';
            "for" = "10m";
            labels.severity = "warning";
            annotations.summary = "Root filesystem is over 85% full";
          }
          {
            alert = "DiskSpaceCritical";
            expr = ''100 - (node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"} * 100) > 93'';
            "for" = "5m";
            labels.severity = "critical";
            annotations.summary = "Root filesystem is over 93% full";
          }
          {
            alert = "DiskFillingUp";
            expr = ''predict_linear(node_filesystem_avail_bytes{mountpoint="/"}[6h], 24 * 3600) < 0'';
            "for" = "30m";
            labels.severity = "warning";
            annotations.summary = "Root filesystem runs out of space within 24 hours at this rate";
          }
          {
            alert = "MemoryHigh";
            expr = "100 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes * 100) > 90";
            "for" = "15m";
            labels.severity = "warning";
            annotations.summary = "Memory use is over 90%";
          }
          {
            alert = "CpuHigh";
            expr = ''100 - (avg(rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100) > 90'';
            "for" = "20m";
            labels.severity = "warning";
            annotations.summary = "CPU use is over 90%";
          }
          {
            alert = "SystemdUnitFailed";
            expr = ''node_systemd_unit_state{state="failed"} == 1'';
            "for" = "5m";
            labels.severity = "warning";
            annotations.summary = "systemd unit {{ $labels.name }} has failed";
          }
        ];
      }
      {
        name = "traffic";
        rules = [
          {
            # Caddy's Prometheus metrics carry no host label, so this is the
            # whole server. Per-site error rates live in the Loki dashboard.
            alert = "HttpErrorRateHigh";
            expr = ''sum(rate(caddy_http_response_duration_seconds_count{code=~"5.."}[5m])) / sum(rate(caddy_http_response_duration_seconds_count[5m])) > 0.01'';
            "for" = "10m";
            labels.severity = "warning";
            annotations.summary = "Over 1% of responses are 5xx";
          }
        ];
      }
    ];
  };

  haMetricsScript = pkgs.writeShellScript "ha-metrics-push" ''
    set -euo pipefail

    TOKEN_FILE="/etc/secrets/ha-token"
    if [ ! -f "$TOKEN_FILE" ]; then
      echo "HA token file not found: $TOKEN_FILE" >&2
      exit 1
    fi
    HA_TOKEN=$(cat "$TOKEN_FILE")
    HA_URL="https://ha.miker.be"
    PROM="http://127.0.0.1:9090/api/v1/query"

    prom() {
      ${pkgs.curl}/bin/curl -sf "$PROM" --data-urlencode "query=$1" \
        || echo '{"data":{"result":[]}}'
    }

    # Three queries, then one jq pass that builds every payload. The old
    # version spawned a jq per site and burned ~2.9s of CPU a minute.
    # The vitals ride in on a single expression, tagged by a `k` label.
    vitals=$(prom '
      label_replace(100 - (avg(rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100), "k", "cpu", "", "")
      or label_replace(100 - ((node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes) * 100), "k", "mem", "", "")
      or label_replace(100 - ((node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"}) * 100), "k", "disk", "", "")
      or label_replace(min((probe_ssl_earliest_cert_expiry - time()) / 86400), "k", "certdays", "", "")
    ')
    probes=$(prom 'probe_success')
    alerts=$(prom 'ALERTS{alertstate="firing"}')

    payloads=$(${pkgs.jq}/bin/jq -rn \
      --argjson v "$vitals" --argjson p "$probes" --argjson a "$alerts" \
      --arg sites "${siteTable}" '
        def num($x): if $x == null then 0 else (try ((($x | tonumber) * 10 | round) / 10) catch 0) end;
        def vit($k): [ $v.data.result[] | select(.metric.k == $k) | .value[1] ] | first;
        def row($id; $body): "\($id)\t\($body | tojson)";
        def gauge($id; $value; $unit; $name; $icon):
          row($id; {
            state: ($value | tostring),
            attributes: {
              unit_of_measurement: $unit,
              friendly_name: $name,
              state_class: "measurement",
              icon: $icon
            }
          });

        ($a.data.result // []) as $al
        | ($al | length) as $count
        | ($al | map(select(.metric.severity == "critical")) | length) as $crit
        | ($al | map(.metric.alertname + (if .metric.instance then " @ " + .metric.instance else "" end))) as $detail
        | [
            gauge("sensor.general_server_cpu"; num(vit("cpu")); "%"; "General Server CPU Usage"; "mdi:server"),
            gauge("sensor.general_server_memory"; num(vit("mem")); "%"; "General Server Memory Usage"; "mdi:memory"),
            gauge("sensor.general_server_disk"; num(vit("disk")); "%"; "General Server Disk Usage"; "mdi:harddisk"),
            gauge("sensor.general_server_cert_days"; num(vit("certdays")); "d"; "General Server soonest cert expiry"; "mdi:certificate"),
            row("binary_sensor.general_server_alerts"; {
              state: (if $count > 0 then "on" else "off" end),
              attributes: {
                friendly_name: "General Server alerts",
                device_class: "problem",
                icon: "mdi:fire",
                count: $count,
                critical: $crit,
                alerts: ($al | map(.metric.alertname)),
                detail: $detail,
                text: ($detail | join(", "))
              }
            }),
            row("sensor.general_server_alert_count"; {
              state: ($count | tostring),
              attributes: {
                friendly_name: "General Server firing alerts",
                state_class: "measurement",
                icon: "mdi:alert",
                critical: $crit,
                detail: $detail
              }
            })
          ]
          + ( $sites | split("\n") | map(select(length > 0)) | map(
                split("|") as $s
                | ([ $p.data.result[] | select(.metric.instance == $s[0]) | .value[1] ] | first) as $ok
                | row("binary_sensor.site_" + $s[1]; {
                    state: (if $ok == "1" then "on" else "off" end),
                    attributes: {
                      friendly_name: $s[3],
                      device_class: "connectivity",
                      icon: $s[2]
                    }
                  })
            ))
        | .[]
      ')

    while IFS=$'\t' read -r entity body; do
      [ -n "$entity" ] || continue
      ${pkgs.curl}/bin/curl -sf -X POST "$HA_URL/api/states/$entity" \
        -H "Authorization: Bearer $HA_TOKEN" \
        -H "Content-Type: application/json" \
        -d "$body" > /dev/null
    done <<< "$payloads"
  '';

in
{
  # --- Tailscale for private access to Grafana ---
  services.tailscale.enable = true;
  networking.firewall.trustedInterfaces = [ "tailscale0" ];

  # --- Prometheus ---
  services.prometheus = {
    enable = true;
    listenAddress = "127.0.0.1";
    port = 9090;
    retentionTime = "30d";

    exporters.node = {
      enable = true;
      listenAddress = "127.0.0.1";
      port = 9100;
      enabledCollectors = [ "systemd" "processes" ];
    };

    exporters.blackbox = {
      enable = true;
      listenAddress = "127.0.0.1";
      port = 9115;
      configFile = pkgs.writeText "blackbox.yml" (builtins.toJSON {
        modules = blackboxModules;
      });
    };

    scrapeConfigs = [
      {
        job_name = "node";
        static_configs = [{
          targets = [ "127.0.0.1:9100" ];
        }];
        scrape_interval = "15s";
      }
      {
        job_name = "caddy";
        static_configs = [{
          targets = [ "127.0.0.1:2019" ];
        }];
        scrape_interval = "15s";
      }
    ] ++ blackboxJobs;

    ruleFiles = [
      (pkgs.writeText "alerts.yml" (builtins.toJSON alertRules))
    ];
  };

  # --- Loki ---
  services.loki = {
    enable = true;
    configuration = {
      auth_enabled = false;

      server = {
        http_listen_address = "127.0.0.1";
        http_listen_port = 3100;
      };

      common = {
        path_prefix = "/var/lib/loki";
        ring = {
          instance_addr = "127.0.0.1";
          kvstore.store = "inmemory";
        };
        replication_factor = 1;
      };

      # Server uses ens18, not eth0/en0
      common.instance_interface_names = [ "ens18" "lo" ];
      memberlist.bind_addr = [ "127.0.0.1" ];

      schema_config.configs = [{
        from = "2024-01-01";
        store = "tsdb";
        object_store = "filesystem";
        schema = "v13";
        index = {
          prefix = "index_";
          period = "24h";
        };
      }];

      storage_config.filesystem.directory = "/var/lib/loki/chunks";

      limits_config = {
        retention_period = "30d";
        allow_structured_metadata = false;
        ingestion_rate_mb = 32;
        ingestion_burst_size_mb = 64;
      };

      compactor = {
        working_directory = "/var/lib/loki/compactor";
        retention_enabled = true;
        delete_request_store = "filesystem";
      };
    };
  };

  # --- Grafana Alloy (replaces promtail, which was removed from nixpkgs) ---
  services.alloy = {
    enable = true;
    configPath = pkgs.writeText "config.alloy" ''
      loki.write "default" {
        endpoint {
          url = "http://127.0.0.1:3100/loki/api/v1/push"
        }
      }

      local.file_match "caddy" {
        path_targets = [
          {
            __path__ = "/var/log/caddy/access*.log",
            job      = "caddy",
          },
        ]
      }

      loki.source.file "caddy" {
        targets    = local.file_match.caddy.targets
        forward_to = [loki.process.caddy.receiver]
      }

      loki.process "caddy" {
        forward_to = [loki.write.default.receiver]

        stage.json {
          expressions = {
            request_host = "request.host",
            status       = "status",
            method       = "request.method",
            uri          = "request.uri",
            remote_ip    = "request.remote_ip",
            duration     = "duration",
          }
        }

        stage.labels {
          values = {
            request_host = "",
            status       = "",
            method       = "",
          }
        }
      }

      loki.relabel "journal" {
        forward_to = []

        rule {
          source_labels = ["__journal__systemd_unit"]
          target_label  = "unit"
        }
      }

      loki.source.journal "journal" {
        max_age       = "12h"
        labels        = { job = "systemd-journal" }
        forward_to    = [loki.write.default.receiver]
        relabel_rules = loki.relabel.journal.rules
      }
    '';
  };

  # --- Grafana ---
  services.grafana = {
    enable = true;
    settings = {
      server = {
        http_addr = "0.0.0.0";
        http_port = 3000;
      };
      security = {
        admin_user = "admin";
        admin_password = "$__file{/etc/secrets/grafana-admin-password}";
        secret_key = "$__file{/etc/secrets/grafana-secret-key}";
      };
    };

    provision = {
      dashboards.settings.providers = [{
        name = "default";
        options.path = ./grafana-dashboards;
      }];
      datasources.settings.datasources = [
        {
          name = "Prometheus";
          type = "prometheus";
          url = "http://127.0.0.1:9090";
          isDefault = true;
        }
        {
          name = "Loki";
          type = "loki";
          url = "http://127.0.0.1:3100";
        }
      ];
    };
  };

  # --- HA metrics push timer ---
  systemd.services.ha-metrics-push = {
    description = "Push server metrics to Home Assistant";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = haMetricsScript;
    };
  };

  systemd.timers.ha-metrics-push = {
    description = "Push server metrics and firing alerts to Home Assistant";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      # Every minute: the push only reads Prometheus now, so it is cheap,
      # and an alert that reaches the phone 5 minutes late is a bad alert.
      OnCalendar = "minutely";
      Persistent = true;
    };
  };

  # Alloy needs access to journal and Caddy logs under strict sandboxing
  systemd.services.alloy.serviceConfig = {
    ReadOnlyPaths = [ "/var/log/caddy" "/run/log/journal" "/var/log/journal" ];
    SupplementaryGroups = [ "caddy" "systemd-journal" ];
  };

  # Ensure required directories exist
  systemd.tmpfiles.rules = [
    "d /var/log/caddy 0750 caddy caddy -"
    "z /var/log/caddy/access*.log 0640 caddy caddy -"
    "d /etc/secrets 0750 root grafana -"
  ];

  # Create placeholder secret files if they don't exist yet
  systemd.services.init-monitoring-secrets = {
    description = "Initialize monitoring secret files with placeholders";
    wantedBy = [ "multi-user.target" ];
    before = [ "grafana.service" "ha-metrics-push.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      for f in grafana-admin-password grafana-secret-key ha-token; do
        if [ ! -f "/etc/secrets/$f" ]; then
          echo -n "CHANGE_ME" > "/etc/secrets/$f"
        fi
      done
      # Generate a real secret key if it's still the placeholder
      if [ "$(cat /etc/secrets/grafana-secret-key)" = "CHANGE_ME" ]; then
        ${pkgs.openssl}/bin/openssl rand -hex 32 > /etc/secrets/grafana-secret-key
      fi
      # Fix Caddy log permissions so Promtail can read them
      chmod -R g+r /var/log/caddy/ 2>/dev/null || true

      # Grafana needs to read its secrets
      chown root:grafana /etc/secrets/grafana-admin-password /etc/secrets/grafana-secret-key
      chmod 640 /etc/secrets/grafana-admin-password /etc/secrets/grafana-secret-key
      chmod 600 /etc/secrets/ha-token
    '';
  };
}
