{ config, pkgs, lib, ... }:

let
  haMetricsScript = pkgs.writeShellScript "ha-metrics-push" ''
    set -euo pipefail

    TOKEN_FILE="/etc/secrets/ha-token"
    if [ ! -f "$TOKEN_FILE" ]; then
      echo "HA token file not found: $TOKEN_FILE" >&2
      exit 1
    fi
    HA_TOKEN=$(cat "$TOKEN_FILE")
    HA_URL="https://ha.miker.be"

    # Query Prometheus for current metrics
    PROM="http://127.0.0.1:9090/api/v1/query"

    cpu_idle=$(${pkgs.curl}/bin/curl -sf "$PROM" --data-urlencode 'query=100 - (avg(rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)' | ${pkgs.jq}/bin/jq -r '.data.result[0].value[1] // "0"')
    mem_used=$(${pkgs.curl}/bin/curl -sf "$PROM" --data-urlencode 'query=100 - ((node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes) * 100)' | ${pkgs.jq}/bin/jq -r '.data.result[0].value[1] // "0"')
    disk_used=$(${pkgs.curl}/bin/curl -sf "$PROM" --data-urlencode 'query=100 - ((node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"}) * 100)' | ${pkgs.jq}/bin/jq -r '.data.result[0].value[1] // "0"')

    # Round to 1 decimal
    cpu_idle=$(printf "%.1f" "$cpu_idle")
    mem_used=$(printf "%.1f" "$mem_used")
    disk_used=$(printf "%.1f" "$disk_used")

    # Push to HA as sensor states
    for sensor in "sensor.general_server_cpu:$cpu_idle:%:CPU Usage" "sensor.general_server_memory:$mem_used:%:Memory Usage" "sensor.general_server_disk:$disk_used:%:Disk Usage"; do
      IFS=: read -r entity value unit friendly <<< "$sensor"
      ${pkgs.curl}/bin/curl -sf -X POST "$HA_URL/api/states/$entity" \
        -H "Authorization: Bearer $HA_TOKEN" \
        -H "Content-Type: application/json" \
        -d "{\"state\": \"$value\", \"attributes\": {\"unit_of_measurement\": \"$unit\", \"friendly_name\": \"General Server $friendly\", \"icon\": \"mdi:server\"}}" > /dev/null
    done
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
      };

      compactor = {
        working_directory = "/var/lib/loki/compactor";
        retention_enabled = true;
        delete_request_store = "filesystem";
      };
    };
  };

  # --- Promtail ---
  services.promtail = {
    enable = true;
    configuration = {
      server = {
        http_listen_port = 9080;
        grpc_listen_port = 0;
      };

      positions.filename = "/var/lib/promtail/positions.yaml";

      clients = [{
        url = "http://127.0.0.1:3100/loki/api/v1/push";
      }];

      scrape_configs = [
        {
          job_name = "caddy-access-logs";
          static_configs = [{
            targets = [ "localhost" ];
            labels = {
              job = "caddy";
              __path__ = "/var/log/caddy/access.log";
            };
          }];
          pipeline_stages = [
            { json.expressions = {
              request_host = "request.host";
              status = "status";
              method = "request.method";
              uri = "request.uri";
              remote_ip = "request.remote_ip";
              duration = "duration";
            }; }
            { labels = {
              request_host = null;
              status = null;
              method = null;
            }; }
          ];
        }
        {
          job_name = "journal";
          journal = {
            max_age = "12h";
            labels = {
              job = "systemd-journal";
            };
          };
          relabel_configs = [{
            source_labels = [ "__journal__systemd_unit" ];
            target_label = "unit";
          }];
        }
      ];
    };
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
    description = "Push server metrics to Home Assistant every 5 minutes";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*:0/5";
      Persistent = true;
    };
  };

  # Promtail needs access to journal and Caddy logs under strict sandboxing
  systemd.services.promtail.serviceConfig = {
    ReadOnlyPaths = [ "/var/log/caddy" "/run/log/journal" "/var/log/journal" ];
  };

  # Ensure required directories exist
  systemd.tmpfiles.rules = [
    "d /var/log/caddy 0755 caddy caddy -"
    "d /var/lib/promtail 0750 promtail promtail -"
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
      # Grafana needs to read its secrets
      chown root:grafana /etc/secrets/grafana-admin-password /etc/secrets/grafana-secret-key
      chmod 640 /etc/secrets/grafana-admin-password /etc/secrets/grafana-secret-key
      chmod 600 /etc/secrets/ha-token
    '';
  };
}
