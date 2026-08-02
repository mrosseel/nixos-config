{ pkgs, ... }:

# Nightly one-way export of the trip plan to Google Drive, as a native Google
# Sheet in the same folder as the planning doc. See drive-export.py for why this
# exists alongside the git backup: it is the copy a non-technical traveller can
# still read if the site is down.
#
# Separate unit from thailand-planner so the API service stays stdlib-only and
# a Drive outage can never affect saving.
#
# One-time setup, on the server:
#
#   sudo -i
#   HOME=/root rclone config    # new remote named 'gdrive', type: drive,
#                               # scope: drive.file, then the browser step
#   install -m 0600 /root/.config/rclone/rclone.conf \
#           /var/lib/thailand-planner-secrets/rclone.conf
#   systemctl start thailand-drive-export   # verify, then it runs nightly
#
# It runs as root because thailand-planner uses DynamicUser, which leaves its
# state directory readable only by an unpredictable uid. Root reads the plan
# through a read-only bind and writes nothing locally. The alternative is to
# give the planner a fixed system user and share a group; that is a tidier end
# state but means migrating the live data directory, so it is not worth doing
# while the trip is being actively planned.

let
  python = pkgs.python3.withPackages (ps: [ ps.openpyxl ]);
in {
  systemd.services.thailand-drive-export = {
    description = "Export the Thailand trip plan to Google Drive";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    path = [ pkgs.rclone ];
    environment = {
      PLAN_FILE = "/var/lib/thailand-planner/plan.json";
      # systemd hands the unit a private 0400 copy, so the config — which holds
      # a Drive refresh token — stays root-only on disk.
      RCLONE_CONF = "%d/rclone.conf";
      DRIVE_REMOTE = "gdrive:Thailand";
      DRIVE_SHEET_NAME = "Reisplan (automatisch)";
    };
    serviceConfig = {
      Type = "oneshot";
      # Skip cleanly rather than fail nightly on a machine where the one-time
      # rclone login has not been done yet.
      ExecCondition = "${pkgs.coreutils}/bin/test -f /var/lib/thailand-planner-secrets/rclone.conf";
      ExecStart = "${python}/bin/python3 ${./drive-export.py}";
      TimeoutStartSec = "10m";
      # Runs as the planner's own user: it only reads the plan, and this way it
      # needs no privilege beyond what the service that owns the data already has.
      User = "thailand-planner";
      Group = "thailand-planner";
      PrivateTmp = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      NoNewPrivileges = true;
      LoadCredential = "rclone.conf:/var/lib/thailand-planner-secrets/rclone.conf";
      ReadOnlyPaths = [ "/var/lib/thailand-planner" ];
    };
  };

  systemd.timers.thailand-drive-export = {
    description = "Nightly Thailand plan export to Google Drive";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*-*-* 03:30:00";
      RandomizedDelaySec = "20m";
      Persistent = true;
    };
  };
}
