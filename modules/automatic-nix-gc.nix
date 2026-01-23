{ config, lib, pkgs, ... }:

let
  cfg = config.services.automatic-nix-gc;

  GiBtoKiB = n: n * 1024 * 1024;
  GiBtoBytes = n: n * 1024 * 1024 * 1024;

  gcScript = pkgs.writeShellScript "automatic-nix-gc" ''
    set -euo pipefail

    available_kib=$(df --sync /nix --output=avail | tail -n1 | tr -d ' ')
    threshold_kib=${toString (GiBtoKiB cfg.diskThreshold)}

    echo "Disk space check: ''${available_kib} KiB available, threshold: ''${threshold_kib} KiB"

    if [ "$available_kib" -lt "$threshold_kib" ]; then
      echo "Below threshold, running garbage collection..."
      ${config.nix.package}/bin/nix-collect-garbage \
        --delete-older-than "${cfg.preserveGenerations}" \
        --max-freed "${toString (GiBtoBytes cfg.maxFreed)}"
      echo "Garbage collection complete"
    else
      echo "Sufficient space available, skipping GC"
    fi
  '';
in
{
  options.services.automatic-nix-gc = {
    enable = lib.mkEnableOption "automatic Nix garbage collection";

    # Time-based GC options
    dates = lib.mkOption {
      type = lib.types.str;
      default = "weekly";
      description = "How often to run scheduled GC (systemd calendar format).";
    };

    olderThan = lib.mkOption {
      type = lib.types.str;
      default = "14d";
      description = "Delete generations older than this in scheduled GC.";
    };

    # Disk-based GC options
    diskBased.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable disk-space-based GC (runs when disk is low).";
    };

    interval = lib.mkOption {
      type = lib.types.str;
      default = "1h";
      description = "How often to check disk space (systemd time format).";
    };

    diskThreshold = lib.mkOption {
      type = lib.types.int;
      default = 20;
      description = "Trigger disk-based GC when available space falls below this (GiB).";
    };

    maxFreed = lib.mkOption {
      type = lib.types.int;
      default = 50;
      description = "Maximum space to free per disk-based GC run (GiB).";
    };

    preserveGenerations = lib.mkOption {
      type = lib.types.str;
      default = "14d";
      description = "Keep generations younger than this in disk-based GC.";
    };
  };

  config = lib.mkIf cfg.enable {
    # Store optimization
    nix.settings.auto-optimise-store = true;
    nix.optimise.automatic = true;

    # Time-based scheduled GC
    nix.gc = {
      automatic = true;
      dates = cfg.dates;
      options = "--delete-older-than ${cfg.olderThan}";
    };

    # Disk-based GC service and timer
    systemd.services.automatic-nix-gc = lib.mkIf cfg.diskBased.enable {
      description = "Disk-based Nix garbage collection";
      script = "${gcScript}";
      serviceConfig = {
        Type = "oneshot";
        Nice = 19;
        IOSchedulingClass = "idle";
      };
    };

    systemd.timers.automatic-nix-gc = lib.mkIf cfg.diskBased.enable {
      description = "Disk-based Nix garbage collection timer";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "5m";
        OnUnitActiveSec = cfg.interval;
        RandomizedDelaySec = "5m";
      };
    };
  };
}
