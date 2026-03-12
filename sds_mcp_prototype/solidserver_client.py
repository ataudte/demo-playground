#!/usr/bin/env python3
import base64
import json
import os
import ssl
import urllib.error
import urllib.parse
import urllib.request


SOLIDSERVER_URL = os.environ["SOLIDSERVER_URL"].rstrip("/")
SOLIDSERVER_USER = os.environ["SOLIDSERVER_USER"]
SOLIDSERVER_PASSWORD = os.environ["SOLIDSERVER_PASSWORD"]
INSECURE_TLS = os.environ.get("SOLIDSERVER_INSECURE_TLS", "true").lower() == "true"

SSL_CONTEXT = None
if INSECURE_TLS:
    SSL_CONTEXT = ssl._create_unverified_context()


def log(msg: str) -> None:
    import sys
    sys.stderr.write(msg + "\n")
    sys.stderr.flush()


def b64(s: str) -> str:
    return base64.b64encode(s.encode("utf-8")).decode("ascii")


def build_headers():
    return {
        "x-ipm-username": b64(SOLIDSERVER_USER),
        "x-ipm-password": b64(SOLIDSERVER_PASSWORD),
        "Accept": "application/json",
    }


def escape_like(value: str) -> str:
    return value.replace("\\", "\\\\").replace("'", "\\'")


def call_service(service: str, params=None):
    params = params or {}
    query = urllib.parse.urlencode(
        {k: v for k, v in params.items() if v is not None and v != ""},
        doseq=True,
    )
    url = f"{SOLIDSERVER_URL}/rest/{service}"
    if query:
        url = f"{url}?{query}"

    req = urllib.request.Request(url=url, method="GET", headers=build_headers())

    try:
        with urllib.request.urlopen(req, context=SSL_CONTEXT, timeout=30) as resp:
            raw = resp.read().decode("utf-8")
    except urllib.error.HTTPError as exc:
        body = exc.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"HTTP {exc.code} from SOLIDserver: {body}") from exc
    except urllib.error.URLError as exc:
        msg = str(exc.reason)
        if "CERTIFICATE_VERIFY_FAILED" in msg or "self-signed certificate" in msg:
            raise RuntimeError(
                "TLS certificate verification failed."
            ) from exc
        raise RuntimeError(f"Connection to SOLIDserver failed: {msg}") from exc

    try:
        return json.loads(raw)
    except json.JSONDecodeError:
        return {"raw": raw}


def first_list_item(data):
    if isinstance(data, list) and data:
        return data[0]
    return None


def summarize_ip_record(record):
    if not isinstance(record, dict):
        return None

    summary = {
        "ip": record.get("hostaddr"),
        "fqdn": record.get("name"),
        "site": record.get("site_name"),
        "subnet": None,
        "subnet_name": record.get("subnet_name"),
        "mac": record.get("mac_addr"),
        "class": record.get("ip_class_name"),
    }

    start_ip = record.get("subnet_start_hostaddr")
    prefix = record.get("subnet_prefix")
    if start_ip and prefix:
        summary["subnet"] = f"{start_ip}/{prefix}"

    params = record.get("ip_class_parameters", "")
    if isinstance(params, str):
        parsed = urllib.parse.parse_qs(params, keep_blank_values=True)
        if parsed.get("shortname"):
            summary["shortname"] = parsed["shortname"][0]
        if parsed.get("hostname"):
            summary["hostname"] = parsed["hostname"][0]
        if parsed.get("demo_ip_type"):
            summary["ip_type"] = parsed["demo_ip_type"][0]

    return {k: v for k, v in summary.items() if v not in (None, "", "#")}


def summarize_subnet_record(record):
    if not isinstance(record, dict):
        return None

    summary = {
        "site": record.get("site_name"),
        "subnet_name": record.get("subnet_name"),
        "subnet": None,
        "class": record.get("subnet_class_name") or record.get("ip_class_name"),
    }

    subnet_addr = record.get("subnet_addr") or record.get("subnet_start_hostaddr")
    prefix = record.get("subnet_prefix")
    if subnet_addr and prefix and "." in str(subnet_addr):
        summary["subnet"] = f"{subnet_addr}/{prefix}"

    if record.get("subnet_netmask"):
        summary["netmask"] = record.get("subnet_netmask")
    if record.get("subnet_size"):
        summary["size"] = record.get("subnet_size")

    return {k: v for k, v in summary.items() if v not in (None, "", "#")}


def summarize_dns_record(record):
    if not isinstance(record, dict):
        return None

    summary = {
        "fqdn": record.get("rr_full_name"),
        "type": record.get("rr_type"),
        "value": record.get("value1") or record.get("rr_all_value"),
        "zone": record.get("dnszone_name"),
        "dns_server": record.get("dns_name"),
        "site": record.get("dnszone_site_name"),
    }
    return {k: v for k, v in summary.items() if v not in (None, "", "#")}

def summarize_dhcp_record(record):
    if not isinstance(record, dict):
        return None

    summary = {
        "ip": (
            record.get("dhcphost_addr")
            or record.get("ip_address")
            or record.get("ip_addr")
            or record.get("hostaddr")
        ),
        "mac": (
            record.get("dhcphost_mac_addr")
            or record.get("mac_addr")
            or record.get("mac")
        ),
        "name": (
            record.get("dhcphost_name")
            or record.get("db_hostname")
            or record.get("name")
        ),
        "scope": (
            record.get("dhcpscope_name")
            or record.get("scope_name")
        ),
        "server": (
            record.get("dhcp_name")
            or record.get("dhcpsrv_name")
        ),
        "site": (
            record.get("site_name")
            or record.get("dhcpscope_site_id")
        ),
        "state": record.get("dhcphost_state"),
    }

    return {k: v for k, v in summary.items() if v not in (None, "", "#", "0")}


def extract_ip_from_dns_record(record):
    if not isinstance(record, dict):
        return None
    for key in ("value1", "rr_all_value", "hostaddr"):
        value = record.get(key)
        if value and isinstance(value, str) and "." in value:
            return value
    return None