{ lib, pkgs, ... }:

let
  home = "/srv/app-data/flexget";
  configFile = "${home}/flexget.yml";
  variablesFile = "${home}/variables.yml";
  webPasswordFile = "${home}/.webui-password";
  fileListSecret = "/srv/secrets/flexget-filelist.json";
  webSecret = "/srv/secrets/flexget-webui-password";

  prepareSecrets = pkgs.writeShellScript "flexget-prepare-secrets" ''
    set -euo pipefail
    umask 0077

    qbt_secret=/srv/secrets/qbittorrent-webui-password
    filelist_secret=${fileListSecret}
    web_secret=${webSecret}
    variables=${variablesFile}
    web_password=${webPasswordFile}

    # One-time in-place migration from Prowlarr. The resulting JSON remains a
    # host-local secret and lets Prowlarr be disabled immediately afterward.
    if [[ ! -s "$filelist_secret" ]]; then
      if [[ ! -r /srv/app-data/prowlarr/prowlarr.db ]]; then
        echo "Missing $filelist_secret and no Prowlarr database is available to migrate" >&2
        exit 1
      fi

      ${pkgs.python3}/bin/python - "$filelist_secret" <<'PY'
import json
import os
import sqlite3
import sys
import tempfile

output = sys.argv[1]
db = sqlite3.connect("/srv/app-data/prowlarr/prowlarr.db")
row = db.execute(
    "SELECT Settings FROM Indexers "
    "WHERE Implementation = 'FileList' AND Enable = 1 LIMIT 1"
).fetchone()
if row is None:
    raise SystemExit("Prowlarr has no enabled FileList indexer to migrate")
settings = json.loads(row[0])
secret = {
    "username": settings["username"],
    "passkey": settings["passkey"],
}
descriptor, temporary = tempfile.mkstemp(
    prefix=".flexget-filelist.", dir=os.path.dirname(output)
)
try:
    with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
        json.dump(secret, handle)
        handle.write("\n")
    os.chmod(temporary, 0o600)
    os.replace(temporary, output)
except BaseException:
    os.unlink(temporary)
    raise
PY
    fi

    [[ -s "$qbt_secret" ]] || {
      echo "qBittorrent did not create $qbt_secret" >&2
      exit 1
    }
    if [[ ! -s "$web_secret" ]]; then
      ${pkgs.openssl}/bin/openssl rand -base64 24 \
        | ${pkgs.coreutils}/bin/tr -d '\n' > "$web_secret"
    fi

    # JSON is valid YAML. Generate FlexGet's variables file at runtime so no
    # tracker or qBittorrent credentials are copied into the Nix store.
    ${pkgs.python3}/bin/python - \
      "$qbt_secret" "$filelist_secret" "$variables" "$web_secret" "$web_password" <<'PY'
import grp
import json
import os
import pwd
import sys
import tempfile

qbt_path, filelist_path, output, web_secret, web_output = sys.argv[1:]
flexget_uid = pwd.getpwnam("flexget").pw_uid
media_gid = grp.getgrnam("media").gr_gid
with open(qbt_path, encoding="utf-8") as handle:
    qbt_password = handle.read().strip()
if not qbt_password:
    raise SystemExit(f"Invalid empty qBittorrent password in {qbt_path}")
with open(filelist_path, encoding="utf-8") as handle:
    filelist = json.load(handle)
if not all(
    isinstance(filelist.get(key), str) and filelist[key]
    for key in ("username", "passkey")
):
    raise SystemExit(
        f"Invalid {filelist_path}; remove it to remigrate credentials from Prowlarr"
    )
variables = {
    "qbittorrent": {"password": qbt_password},
    "filelist": {
        "username": filelist["username"],
        "passkey": filelist["passkey"],
    },
}
descriptor, temporary = tempfile.mkstemp(
    prefix=".variables.", dir=os.path.dirname(output)
)
try:
    os.fchmod(descriptor, 0o600)
    os.fchown(descriptor, flexget_uid, media_gid)
    with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
        json.dump(variables, handle)
        handle.write("\n")
    os.replace(temporary, output)
except BaseException:
    os.unlink(temporary)
    raise

# Transfer the Web UI password through a short-lived, safely-created file. The
# following unprivileged ExecStartPre consumes and deletes it.
descriptor, temporary = tempfile.mkstemp(
    prefix=".webui-password.", dir=os.path.dirname(web_output)
)
try:
    os.fchmod(descriptor, 0o600)
    os.fchown(descriptor, flexget_uid, media_gid)
    with open(web_secret, "rb") as source, os.fdopen(descriptor, "wb") as target:
        target.write(source.read())
    os.replace(temporary, web_output)
except BaseException:
    os.unlink(temporary)
    raise
PY

    ${pkgs.coreutils}/bin/chown root:root "$filelist_secret" "$web_secret"
    ${pkgs.coreutils}/bin/chmod 0600 "$filelist_secret" "$web_secret"
  '';

  setWebPassword = pkgs.writeShellScript "flexget-set-web-password" ''
    set -euo pipefail
    password_file=${webPasswordFile}
    trap '${pkgs.coreutils}/bin/rm -f "$password_file"' EXIT
    password="$(<"$password_file")"
    [[ -n "$password" ]]
    ${pkgs.flexget}/bin/flexget -c ${configFile} web passwd "$password"
  '';
in
{
  users.users.flexget = {
    isSystemUser = true;
    group = "media";
    home = home;
  };

  services.flexget = {
    enable = true;
    user = "flexget";
    homeDir = home;
    interval = "15m";
    systemScheduler = true;

    # Search FileList directly and hand accepted releases to qBittorrent. A
    # completed torrent is already in Jellyfin's recursive library, avoiding a
    # second importer, duplicate file, and cross-service permission workflow.
    config = ''
      variables: variables.yml

      web_server:
        bind: 0.0.0.0
        port: 5050
        web_ui: yes

      templates:
        filelist_search:
          sort_by:
            - field: torrent_seeds
              reverse: yes

        qbittorrent_output:
          qbittorrent:
            host: 127.0.0.1
            port: 8082
            username: admin
            password: '{? qbittorrent.password ?}'

        movies:
          template:
            - filelist_search
            - qbittorrent_output
          quality: 2160p
          discover:
            interval: 15 minutes
            what:
              - movie_list:
                  list_name: movies
                  strip_year: no
            from:
              - filelist_api:
                  username: '{? filelist.username ?}'
                  passkey: '{? filelist.passkey ?}'
                  category:
                    - Filme 4K
                    - Filme 4K Blu-Ray
          imdb_lookup: yes
          # Results are sorted by seed count; accept only the first matching
          # release and remove the fulfilled request from the persistent list.
          list_match:
            from:
              - movie_list: movies
          qbittorrent:
            path: /srv/media/ssd0/library/movies
            incomplete_path: /srv/media/ssd0/downloads/incomplete
            label: movies

        tv:
          template:
            - filelist_search
            - qbittorrent_output
          series:
            settings:
              shows:
                quality: 2160p
                identified_by: ep
            shows:
              # Shrinking is the only continuing series in the old Sonarr DB;
              # season three is complete through S03E11.
              - Shrinking:
                  begin: S04E01
          discover:
            interval: 15 minutes
            what:
              - next_series_episodes: yes
            from:
              - filelist_api:
                  username: '{? filelist.username ?}'
                  passkey: '{? filelist.passkey ?}'
                  category:
                    - Seriale 4K
          qbittorrent:
            path: /srv/media/ssd1/library/tv
            incomplete_path: /srv/media/ssd1/downloads/incomplete
            label: tv

      tasks:
        movies:
          template: movies
        tv:
          template: tv
    '';
  };

  systemd.services.flexget = {
    requires = [ "qbt-webui-proxy.service" ];
    after = [ "qbt-webui-proxy.service" ];
    unitConfig.RequiresMountsFor = [
      "/srv/app-data"
      "/srv/media/ssd0"
      "/srv/media/ssd1"
    ];
    serviceConfig = {
      UMask = "0007";
      CapabilityBoundingSet = "";
      ExecStartPre = lib.mkAfter [
        "+${prepareSecrets}"
        setWebPassword
      ];
      NoNewPrivileges = true;
      PrivateDevices = true;
      ProtectHome = true;
      ProtectSystem = "strict";
      ReadWritePaths = [
        home
        "/srv/secrets"
      ];
      RestrictAddressFamilies = [
        "AF_INET"
        "AF_INET6"
        "AF_UNIX"
      ];
      RestrictNamespaces = true;
    };
  };

  systemd.services.flexget-runner = {
    requires = [
      "flexget.service"
      "qbt-webui-proxy.service"
    ];
    after = [ "qbt-webui-proxy.service" ];
    unitConfig.RequiresMountsFor = [
      "/srv/app-data"
      "/srv/media/ssd0"
      "/srv/media/ssd1"
    ];
    serviceConfig = {
      UMask = "0007";
      CapabilityBoundingSet = "";
      NoNewPrivileges = true;
      PrivateDevices = true;
      ProtectHome = true;
      ProtectSystem = "strict";
      ReadWritePaths = [ home ];
      RestrictAddressFamilies = [
        "AF_INET"
        "AF_INET6"
        "AF_UNIX"
      ];
      RestrictNamespaces = true;
    };
  };
}
