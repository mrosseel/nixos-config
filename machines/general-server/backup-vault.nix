{ pkgs, lib, ... }:
# ── Backup vault ─────────────────────────────────────────────────────
# Why the vault exists:
# Two remote machines send their database backups to this server over SFTP.
# Each sender writes into its own chroot. The sender can delete and change
# every file in that chroot. An attacker who controls a sender can thus
# destroy the backups of that sender. The filesystem is ext4. It has no
# snapshots.
#
# A root timer copies each chroot every day into /var/lib/backup-vault.
# This directory is outside every chroot. Only root can read or write it.
# The timer makes real copies. It does not make hard links to files in the
# chroot. A deletion or a truncation in the chroot does not change a file
# that is already in the vault.
#
# Layout, for each sender:
# - <name>/snapshots/<file>.db: one copy of each snapshot. The vault keeps
#   the first copy of a name. It never replaces it. It deletes a copy 180
#   days after the copy was made. The senders keep their files 180 days.
# - <name>/litestream/<YYYY-MM-DD>/: a dated copy of the litestream tree.
#   The vault keeps the 30 newest dated copies. A file that is the same as
#   in the previous dated copy is a hard link to that copy. These links
#   stay inside the vault.
#
# The chroot is read by the backup account, not by root. A symbolic link
# in the chroot thus cannot make root read a file outside the chroot.
let
  vaultRoot = "/var/lib/backup-vault";
  snapshotDays = 180;
  litestreamCopies = 30;

  senders = {
    hexalon = { user = "hexalon-backup"; chroot = "/var/lib/hexalon-backups"; };
    warpspeed = { user = "warpspeed-backup"; chroot = "/var/lib/warpspeed-backups"; };
  };

  vaultScript = name: s: pkgs.writeShellApplication {
    name = "backup-vault-${name}";
    runtimeInputs = with pkgs; [ coreutils findutils diffutils gnutar gnugrep rsync util-linux ];
    text = ''
      vault=${vaultRoot}/${name}
      day=$(date +%F)
      umask 077

      install -d -m 0700 ${vaultRoot} "$vault" "$vault/snapshots" "$vault/litestream"
      find ${vaultRoot} -maxdepth 1 -name '.staging-${name}.*' -exec rm -rf {} +
      staging=$(mktemp -d ${vaultRoot}/.staging-${name}.XXXXXX)
      trap 'rm -rf "$staging"' EXIT

      # The backup account reads its chroot. Root only writes the copy.
      setpriv --reuid=${s.user} --regid=${s.user} --clear-groups \
        tar -C ${s.chroot} --ignore-failed-read -cf - snapshots litestream \
        | tar -C "$staging" --no-same-owner --no-same-permissions -xf -

      # Keep only regular files and directories.
      find "$staging" -mindepth 1 ! -type f ! -type d -delete

      # Snapshots: copy a new name once. Never replace a name in the vault.
      if [ -d "$staging/snapshots" ]; then
        find "$staging/snapshots" -maxdepth 1 -type f -name '*.db' -size +0 -mmin +30 -printf '%f\n' \
          | while IFS= read -r f; do
              if [ ! -e "$vault/snapshots/$f" ]; then
                mv "$staging/snapshots/$f" "$vault/snapshots/$f"
                touch "$vault/snapshots/$f"
                echo "snapshot kept: $f"
              elif ! cmp -s "$staging/snapshots/$f" "$vault/snapshots/$f"; then
                echo "warning: $f changed in the chroot, the vault keeps the first copy"
              fi
            done
      fi

      # Litestream: a dated copy, with hard links to the previous dated copy.
      prev=$(find "$vault/litestream" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' \
        | grep -E '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' | grep -vx "$day" | sort | tail -n 1 || true)
      dest="$vault/litestream/$day"
      rm -rf "$dest.part"
      mkdir -p "$staging/litestream"
      rsync -rt --no-links --chmod=D0700,F0600 \
        ''${prev:+--link-dest="$vault/litestream/$prev"} \
        "$staging/litestream/" "$dest.part/"
      rm -rf "$dest"
      mv "$dest.part" "$dest"
      echo "litestream copy: $dest ($(du -sh "$dest" | cut -f1))"

      # Retention. This runs only after a good copy.
      find "$vault/litestream" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' \
        | grep -E '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' | sort | head -n -${toString litestreamCopies} \
        | while IFS= read -r old; do
            rm -rf "''${vault:?}/litestream/$old"
            echo "litestream copy deleted: $old"
          done
      find "$vault/snapshots" -maxdepth 1 -type f -mtime +${toString snapshotDays} -print -delete
    '';
  };
in
{
  systemd.tmpfiles.rules = [
    "d ${vaultRoot} 0700 root root - -"
  ];

  systemd.services = lib.mapAttrs' (name: s: lib.nameValuePair "backup-vault-${name}" {
    description = "Copy the ${name} backup chroot into the root-only vault";
    after = [ "local-fs.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = lib.getExe (vaultScript name s);
      Nice = 10;
      IOSchedulingClass = "idle";
      ProtectSystem = "strict";
      ReadWritePaths = [ vaultRoot ];
      ProtectHome = true;
      PrivateTmp = true;
      PrivateNetwork = true;
      NoNewPrivileges = true;
    };
  }) senders;

  systemd.timers = lib.mapAttrs' (name: s: lib.nameValuePair "backup-vault-${name}" {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      # The senders write their snapshot between 03:30 and 04:10.
      OnCalendar = "*-*-* 06:15:00";
      RandomizedDelaySec = "15min";
      Persistent = true;
    };
  }) senders;
}
