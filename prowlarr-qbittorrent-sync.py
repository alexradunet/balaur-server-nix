#!/usr/bin/env python3
"""Connect Prowlarr manual searches to qBittorrent's temporary-media category."""

from __future__ import annotations

import argparse
import gzip
import http.cookiejar
import json
import pathlib
import time
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET

PROWLARR_URL = "http://127.0.0.1:9696/api/v1"
QBITTORRENT_URL = "http://127.0.0.1:8082/api/v2"
CATEGORY = "manual"
CATEGORY_PATH = "/srv/media/ssd0/downloads/complete"


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


def set_qbittorrent_fields(client: dict, password: str) -> None:
    desired = {
        "host": "127.0.0.1",
        "port": 8082,
        "useSsl": False,
        "username": "admin",
        "password": password,
        "category": CATEGORY,
    }
    available = {field.get("name") for field in client.get("fields", [])}
    missing = set(desired) - available
    if missing:
        raise RuntimeError(
            f"Prowlarr qBittorrent schema is missing fields: {', '.join(sorted(missing))}"
        )
    for field in client["fields"]:
        if field.get("name") in desired:
            field["value"] = desired[field["name"]]


def sync_prowlarr_client(
    password: str, prowlarr_config: pathlib.Path, timeout: int
) -> None:
    config = ET.parse(prowlarr_config).getroot()
    api_key = config.findtext("ApiKey")
    if not api_key:
        raise RuntimeError("Prowlarr has no API key")

    deadline = time.monotonic() + timeout
    last_error: Exception | None = None
    while time.monotonic() < deadline:
        try:
            clients = request_json(f"{PROWLARR_URL}/downloadclient", api_key)
            break
        except (OSError, ValueError) as error:
            last_error = error
            time.sleep(2)
    else:
        raise RuntimeError(f"Prowlarr did not become ready: {last_error}")

    qbittorrent_clients = [
        client
        for client in clients
        if client.get("implementation", "").lower() == "qbittorrent"
    ]
    if not qbittorrent_clients:
        schemas = request_json(f"{PROWLARR_URL}/downloadclient/schema", api_key)
        client = next(
            (
                schema
                for schema in schemas
                if schema.get("implementation", "").lower() == "qbittorrent"
            ),
            None,
        )
        if client is None:
            raise RuntimeError("Prowlarr exposes no qBittorrent download-client schema")
        client["name"] = "qBittorrent"
        client["enable"] = True
        set_qbittorrent_fields(client, password)
        request_json(
            f"{PROWLARR_URL}/downloadclient?forceSave=true",
            api_key,
            method="POST",
            payload=client,
        )
        print("Created Prowlarr qBittorrent client")
        return

    for client in qbittorrent_clients:
        client["enable"] = True
        set_qbittorrent_fields(client, password)
        client_id = client["id"]
        request_json(
            f"{PROWLARR_URL}/downloadclient/{client_id}?forceSave=true",
            api_key,
            method="PUT",
            payload=client,
        )
        print(f"Synchronized Prowlarr qBittorrent client {client_id}")


def qbittorrent_request(
    opener: urllib.request.OpenerDirector,
    endpoint: str,
    *,
    form: dict[str, str] | None = None,
) -> bytes:
    data = None if form is None else urllib.parse.urlencode(form).encode()
    request = urllib.request.Request(
        f"{QBITTORRENT_URL}/{endpoint}",
        data=data,
        # qBittorrent 5.1.4 crashes while parsing urllib's default
        # `Accept-Encoding: identity`; requesting gzip also works on 5.2.
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


def sync_qbittorrent_category(password: str, timeout: int) -> None:
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
            if response.strip() not in (b"", b"Ok."):
                raise RuntimeError("qBittorrent rejected the managed credential")
            break
        except (OSError, RuntimeError) as error:
            last_error = error
            time.sleep(2)
    else:
        raise RuntimeError(f"qBittorrent login did not become ready: {last_error}")

    categories = json.loads(qbittorrent_request(opener, "torrents/categories"))
    current = categories.get(CATEGORY)
    if current is None:
        endpoint = "torrents/createCategory"
    elif current.get("savePath", "").rstrip("/") == CATEGORY_PATH:
        print(f"qBittorrent category {CATEGORY} already uses {CATEGORY_PATH}")
        return
    else:
        endpoint = "torrents/editCategory"

    qbittorrent_request(
        opener,
        endpoint,
        form={"category": CATEGORY, "savePath": CATEGORY_PATH},
    )
    print(f"Set qBittorrent category {CATEGORY} to {CATEGORY_PATH}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--password-file", type=pathlib.Path, required=True)
    parser.add_argument("--prowlarr-config", type=pathlib.Path)
    parser.add_argument("--sync-category", action="store_true")
    parser.add_argument("--timeout", type=int, default=120)
    args = parser.parse_args()

    password = args.password_file.read_text().strip()
    if not password:
        raise RuntimeError("qBittorrent password file is empty")

    if args.sync_category:
        sync_qbittorrent_category(password, args.timeout)
    elif args.prowlarr_config is None:
        parser.error("--prowlarr-config is required when synchronizing Prowlarr")
    else:
        sync_prowlarr_client(password, args.prowlarr_config, args.timeout)


if __name__ == "__main__":
    main()
