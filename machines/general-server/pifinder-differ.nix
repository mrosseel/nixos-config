{ config, lib, pkgs, ... }:

# pifinder-differ — on-demand + self-warming zstd delta server for PiFinder
# NixOS updates. Sits beside Attic (attic-service.nix) and serves byte-level
# patches between store-path export streams:
#
#   POST /delta   device names a target + the bases it holds → 200/202/204
#   POST /warm    precompute all stem-paired deltas between two toplevels
#   GET  /pairs   every computed pair with sizes/ratios (observability)
#   GET  /status  queues, counters, warm-run progress
#   GET  /blobs/* the patch blobs
#
# Test phase: bound to loopback only — reach it via SSH port-forward or
# curl on the host. No Caddy vhost until the device-side applier lands.
#
# The server hosts other apps. All compute is idle-priority and one core is
# always left free: 2 workers on this 4-core / 6 GiB machine (zstd -19
# --long=27 peaks ~800 MiB per job).

let
  pifinder-differ = pkgs.rustPlatform.buildRustPackage {
    pname = "pifinder-differ";
    version = "0.1.0";
    src = lib.cleanSourceWith {
      src = ./pifinder-differ;
      filter = path: _type: builtins.baseNameOf path != "target";
    };
    cargoLock.lockFile = ./pifinder-differ/Cargo.lock;
  };
in
{
  systemd.services.pifinder-differ = {
    description = "PiFinder delta (zstd --patch-from) server";
    wantedBy = [ "multi-user.target" ];
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];

    # nix / nix-store for copy+export, zstd for patches, df for the disk guard.
    path = [ config.nix.package pkgs.zstd pkgs.coreutils ];

    environment = {
      DIFFER_LISTEN = "127.0.0.1:8090";
      DIFFER_STATE_DIR = "/var/lib/pifinder-differ";
      DIFFER_WORKERS = "2";
      DIFFER_SUBSTITUTERS =
        "https://cache.pifinder.eu/pifinder https://cache.pifinder.eu/pifinder-release";
    };

    serviceConfig = {
      ExecStart = "${pifinder-differ}/bin/pifinder-differ";
      StateDirectory = "pifinder-differ";
      Restart = "on-failure";
      RestartSec = 5;

      # Root: `nix copy --no-check-sigs` into the store needs a trusted user.
      # Loopback-only endpoint on our own cache content keeps this acceptable.

      # Never compete with the co-hosted services.
      Nice = 19;
      IOSchedulingClass = "idle";
      CPUWeight = 20;
      MemoryHigh = "2500M";
      MemoryMax = "3G";
    };
  };
}
