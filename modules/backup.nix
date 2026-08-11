{ pkgs, ... }:

{
  systemd.services.balaur-backup = {
    description = "Encrypted Borg backup to USB";
    after = [ "local-fs.target" "systemd-tmpfiles-setup.service" ];
    unitConfig.ConditionPathExists = "/dev/disk/by-label/BALAUR_BACKUP";

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

        if ${pkgs.util-linux}/bin/mountpoint --quiet "$mountpoint"; then
          echo "$mountpoint is already mounted; refusing to manage another mount" >&2
          exit 1
        fi

        ${pkgs.util-linux}/bin/mount "$mountpoint"
        cleanup() {
          status=$?
          trap - EXIT
          ${pkgs.coreutils}/bin/sync
          if ! ${pkgs.util-linux}/bin/umount "$mountpoint"; then
            status=1
          fi
          exit "$status"
        }
        trap cleanup EXIT

        export BORG_BASE_DIR=/var/lib/balaur-backup
        export BORG_PASSCOMMAND="${pkgs.coreutils}/bin/cat $CREDENTIALS_DIRECTORY/passphrase"

        if [[ ! -d "$repository" ]]; then
          ${pkgs.borgbackup}/bin/borg init --encryption=repokey-blake2 "$repository"
        fi

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
          /var/lib/open-webui \
          /srv/secrets || backup_status=$?

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
