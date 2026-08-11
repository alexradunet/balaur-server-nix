#!/usr/bin/env python3
"""Keep the Arr applications and qBittorrent categories in sync."""

from __future__ import annotations

import argparse
import gzip
import http.cookiejar
import json
import pathlib
import time
import urllib.error
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET

APPS = {
    "sonarr": (8989, "tvCategory", "sonarr"),
    "radarr": (7878, "movieCategory", "radarr"),
}
API_VERSIONS = ("v3", "v1")
CATEGORY_PATHS = {
    "radarr": "/srv/media/ssd0/downloads/complete/radarr",
    "sonarr": "/srv/media/ssd1/downloads/complete/sonarr",
}


def request_json(
    url: str,
    api_key: str,
    *,
    method: str = "GET",
    payload: object | None = None,
) -> object:
    data = None if payload is None else json.dumps(payload).encode()
    request = urllib.request.Request(
        url,
        data=data,
        method=method,
        headers={
            "Content-Type": "application/json",
            "X-Api-Key": api_key,
        },
    )
    with urllib.request.urlopen(request, timeout=5) as response:
        body = response.read()
    return None if not body else json.loads(body)


def set_qbittorrent_fields(
    client: dict, password: str, category_field: str, category: str
) -> None:
    desired = {
        "host": "127.0.0.1",
        "port": 8082,
        "useSsl": False,
        "username": "admin",
        "password": password,
        category_field: category,
    }
    available = {field.get("name") for field in client.get("fields", [])}
    missing = {"host", "port", "username", "password", category_field} - available
    if missing:
        raise RuntimeError(
            f"qBittorrent schema is missing fields: {', '.join(sorted(missing))}"
        )
    for field in client["fields"]:
        if field.get("name") in desired:
            field["value"] = desired[field["name"]]


def sync_app(
    app: str, port: int, category_field: str, category: str, password: str
) -> None:
    config = ET.parse(f"/srv/app-data/{app}/config.xml").getroot()
    api_key = config.findtext("ApiKey")
    if not api_key:
        raise RuntimeError(f"{app} has no API key")

    clients = None
    api_version = None
    for candidate in API_VERSIONS:
        base_url = f"http://127.0.0.1:{port}/api/{candidate}"
        try:
            clients = request_json(f"{base_url}/downloadclient", api_key)
            api_version = candidate
            break
        except urllib.error.HTTPError as error:
            if error.code != 404:
                raise

    if clients is None or api_version is None:
        raise RuntimeError(f"{app} exposes neither the v3 nor v1 download-client API")

    qbittorrent_clients = [
        client
        for client in clients
        if client.get("implementation", "").lower() == "qbittorrent"
    ]
    if not qbittorrent_clients:
        base_url = f"http://127.0.0.1:{port}/api/{api_version}"
        schemas = request_json(f"{base_url}/downloadclient/schema", api_key)
        client = next(
            (
                schema
                for schema in schemas
                if schema.get("implementation", "").lower() == "qbittorrent"
            ),
            None,
        )
        if client is None:
            raise RuntimeError(f"{app} exposes no qBittorrent download-client schema")
        client["name"] = "qBittorrent"
        client["enable"] = True
        set_qbittorrent_fields(client, password, category_field, category)
        request_json(
            f"{base_url}/downloadclient?forceSave=true",
            api_key,
            method="POST",
            payload=client,
        )
        print(f"Created {app} qBittorrent client")
        return

    for client in qbittorrent_clients:
        set_qbittorrent_fields(client, password, category_field, category)
        client_id = client["id"]
        url = (
            f"http://127.0.0.1:{port}/api/{api_version}/downloadclient/"
            f"{client_id}?forceSave=true"
        )
        request_json(url, api_key, method="PUT", payload=client)
        print(f"Synchronized {app} qBittorrent client {client_id}")


def qbittorrent_request(
    opener: urllib.request.OpenerDirector,
    endpoint: str,
    *,
    form: dict[str, str] | None = None,
) -> bytes:
    data = None if form is None else urllib.parse.urlencode(form).encode()
    request = urllib.request.Request(
        f"http://127.0.0.1:8082/api/v2/{endpoint}",
        data=data,
        # qBittorrent 5.1.4 crashes while parsing urllib's default
        # `Accept-Encoding: identity`; requesting gzip avoids that upstream bug.
        headers={
            "Accept-Encoding": "gzip",
            "Content-Type": "application/x-www-form-urlencoded",
        },
    )
    with opener.open(request, timeout=5) as response:
        body = response.read()
        if response.headers.get("Content-Encoding") == "gzip":
            body = gzip.decompress(body)
        return body


def sync_qbittorrent_categories(password: str, timeout: int) -> None:
    opener = urllib.request.build_opener(
        urllib.request.HTTPCookieProcessor(http.cookiejar.CookieJar())
    )
    deadline = time.monotonic() + timeout
    last_error: Exception | None = None

    while time.monotonic() < deadline:
        try:
            response = qbittorrent_request(
                opener,
                "auth/login",
                form={"username": "admin", "password": password},
            )
            if response.strip() != b"Ok.":
                raise RuntimeError("qBittorrent rejected the managed credential")
            break
        except (OSError, RuntimeError) as error:
            last_error = error
            time.sleep(2)
    else:
        raise RuntimeError(f"qBittorrent login did not become ready: {last_error}")

    categories = json.loads(qbittorrent_request(opener, "torrents/categories"))
    for category, save_path in CATEGORY_PATHS.items():
        current = categories.get(category)
        if current is None:
            endpoint = "torrents/createCategory"
        elif current.get("savePath", "").rstrip("/") == save_path:
            print(f"qBittorrent category {category} already uses {save_path}")
            continue
        else:
            endpoint = "torrents/editCategory"

        qbittorrent_request(
            opener,
            endpoint,
            form={"category": category, "savePath": save_path},
        )
        print(f"Set qBittorrent category {category} to {save_path}")


def sync_arr_clients(password: str, restart_marker: pathlib.Path, timeout: int) -> None:
    pending = dict(APPS)
    failures: dict[str, Exception] = {}
    deadline = time.monotonic() + timeout

    while pending and time.monotonic() < deadline:
        for app, (port, category_field, category) in list(pending.items()):
            try:
                sync_app(app, port, category_field, category, password)
            except (OSError, RuntimeError, ValueError, ET.ParseError) as error:
                failures[app] = error
            else:
                pending.pop(app)
                failures.pop(app, None)

        if pending:
            time.sleep(2)

    if pending:
        details = "; ".join(f"{app}: {failures[app]}" for app in pending)
        raise RuntimeError(f"failed to synchronize all Arr clients: {details}")

    # Only clear qBittorrent's shared proxy-IP ban after every stale client has
    # been fixed; otherwise one remaining client would immediately re-ban it.
    restart_marker.touch()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--password-file", type=pathlib.Path, required=True)
    parser.add_argument("--restart-marker", type=pathlib.Path)
    parser.add_argument("--sync-categories", action="store_true")
    parser.add_argument("--timeout", type=int, default=120)
    args = parser.parse_args()

    password = args.password_file.read_text().strip()
    if not password:
        raise RuntimeError("qBittorrent password file is empty")

    if args.sync_categories:
        sync_qbittorrent_categories(password, args.timeout)
    elif args.restart_marker is None:
        parser.error("--restart-marker is required when synchronizing Arr clients")
    else:
        sync_arr_clients(password, args.restart_marker, args.timeout)


if __name__ == "__main__":
    main()
