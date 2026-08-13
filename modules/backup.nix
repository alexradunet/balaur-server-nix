{ pkgs, ... }:

{
  systemd.services.balaur-backup = {
    description = "Encrypted Borg backup to USB";
    after = [ "local-fs.target" "systemd-tmpfiles-setup.service" ];
    unitConfig = {
      ConditionPathExists = "/dev/disk/by-label/BALAUR_BACKUP";
      RequiresMountsFor = [
        "/srv/app-data"
        "/srv/personal"
      ];
    };

    serviceConfig = {
      Type = "oneshot";
      StateDirectory = "balaur-backup";
      StateDirectoryMode = "0700";
      LoadCredential = "passphrase:/var/lib/balaur-backup/passphrase";
      UMask = "0077";
      Nice = 10;
      IOSchedulingClass = "idle";
      ExecStart = pkgs.writeShellScript "balaur-backup" ''
        set -euo pipefail

        mountpoint=/mnt/balaur-backup
        repository="$mountpoint/borg"
        systemctl=${pkgs.systemd}/bin/systemctl
        stopped_units=()

        resume_writers() {
          local resume_status=0
          local index
          for ((index=''${#stopped_units[@]} - 1; index >= 0; index--)); do
            if ! "$systemctl" start "''${stopped_units[$index]}"; then
              resume_status=1
            fi
          done
          if (( resume_status == 0 )); then
            stopped_units=()
          fi
          return "$resume_status"
        }

        cleanup() {
          status=$?
          trap - EXIT
          if ! resume_writers; then
            status=1
          fi
          ${pkgs.coreutils}/bin/sync
          if ${pkgs.util-linux}/bin/mountpoint --quiet "$mountpoint" \
            && ! ${pkgs.util-linux}/bin/umount "$mountpoint"; then
            status=1
          fi
          exit "$status"
        }

        stop_if_active() {
          local unit=$1
          if "$systemctl" is-active --quiet "$unit"; then
            "$systemctl" stop "$unit"
            stopped_units+=("$unit")
          fi
        }

        if ${pkgs.util-linux}/bin/mountpoint --quiet "$mountpoint"; then
          echo "$mountpoint is already mounted; refusing to manage another mount" >&2
          exit 1
        fi

        ${pkgs.util-linux}/bin/mount "$mountpoint"
        trap cleanup EXIT

        export BORG_BASE_DIR=/var/lib/balaur-backup
        export BORG_PASSCOMMAND="${pkgs.coreutils}/bin/cat $CREDENTIALS_DIRECTORY/passphrase"

        if [[ ! -d "$repository" ]]; then
          ${pkgs.borgbackup}/bin/borg init --encryption=repokey-blake2 "$repository"
        fi

        # Quiesce Trilium's SQLite database and restore the service on every
        # exit path. Trilium's own periodic database backups remain enabled too.
        stop_if_active trilium-server.service

        backup_status=0
        ${pkgs.borgbackup}/bin/borg create \
          --compression zstd,3 \
          --exclude-caches \
          --exclude /home/alex/.cache \
          --exclude /srv/app-data/fastflowlm/models \
          --stats \
          "$repository::{hostname}-{now:%Y-%m-%dT%H:%M:%S}" \
          /home/alex \
          /srv/app-data \
          /srv/personal \
          /var/lib/hass \
          /srv/secrets || backup_status=$?

        # Resume user-facing writers before slower retention maintenance.
        if ! resume_writers; then
          exit 1
        fi

        # Borg uses status 1 for warnings such as a file changing during backup.
        if (( backup_status > 1 )); then
          exit "$backup_status"
        fi

        ${pkgs.borgbackup}/bin/borg prune \
          --glob-archives 'balaur-*' \
          --keep-daily 7 \
          --keep-weekly 4 \
          --keep-monthly 6 \
          --list \
          "$repository"

        ${pkgs.borgbackup}/bin/borg compact "$repository"
        exit "$backup_status"
      '';
    };
  };

  systemd.timers.balaur-backup = {
    description = "Daily encrypted Borg backup to USB";
    wantedBy = [ "timers.target" ];

    timerConfig = {
      OnCalendar = "daily";
      Persistent = true;
      RandomizedDelaySec = "1h";
    };
  };
}
