#!/usr/bin/env python3

# Shared SOLIDserver client wrapper for the advanced Python demo scripts.
# Centralizes connection setup, authentication, TLS verification, timeout handling, and API error checks.
# Uses the advanced SOLIDserverRest session and object model, while keeping a generic query fallback available.

from __future__ import annotations

import json
from typing import Any

from SOLIDserverRest import adv as sdsadv
from SOLIDserverRest.Exception import (
    SDSAuthError,
    SDSEmptyError,
    SDSError,
    SDSInitError,
    SDSRateLimitError,
)

from .config import DemoConfig


COUNT_METHODS = [
    ("IPAM", "Sites", "ip_site_count"),
    ("IPAM", "IPv4 subnets", "ip_subnet_count"),
    ("IPAM", "IPv4 addresses", "ip_address_count"),
    ("DNS", "DNS servers", "dns_server_count"),
    ("DNS", "DNS views", "dns_view_count"),
    ("DNS", "DNS zones", "dns_zone_count"),
]


class DemoClient:
    def __init__(self, config: DemoConfig) -> None:
        self.config = config
        # Advanced library entry point: SDS owns the authenticated session reused by object classes and raw queries.
        self.sds = sdsadv.SDS(ip_address=config.host, user=config.user, pwd=config.password)
        self.sds.set_check_cert(config.verify_tls)
        self.sds.set_timeout(config.timeout)

    def connect(self) -> None:
        self.sds.connect(method=self.config.auth_method, timeout=self.config.timeout)
        self.query("ip_site_count")

    @property
    def version(self) -> str:
        return self.sds.get_version()

    def query(self, method: str, params: dict[str, Any] | str = "") -> Any:
        # Fallback path for SOLIDserver service methods that do not need a full adv object wrapper.
        data = self.sds.query(method, params=params, timeout=self.config.timeout)
        self._raise_for_api_error(method, data)
        return data

    def count(self, method: str) -> int | str:
        return extract_total(self.query(method))

    def list_rows(self, method: str, limit: int = 5, where: str = "") -> list[dict[str, Any]]:
        params: dict[str, Any] = {"limit": limit, "offset": 0}
        if where:
            params["WHERE"] = where
        return normalize_rows(self.query(method, params))

    def get_space(self, name: str):
        # Advanced object model: resolve an IPAM space once, then pass it to Network objects.
        space = sdsadv.Space(sds=self.sds, name=name)
        space.refresh()
        return space

    def _raise_for_api_error(self, method: str, data: Any) -> None:
        if isinstance(data, dict) and data.get("connected") is False:
            raise RuntimeError(f"{method} returned connected=false: {data}")

        if isinstance(data, dict) and data.get("errmsg"):
            raise RuntimeError(f"{method} failed: {data['errmsg']}")

        if isinstance(data, list):
            for row in data:
                if isinstance(row, dict) and row.get("errmsg"):
                    raise RuntimeError(f"{method} failed: {row['errmsg']}")


def connect_client(config: DemoConfig) -> DemoClient:
    try:
        client = DemoClient(config)
        client.connect()
        return client
    except SDSAuthError as exc:
        raise RuntimeError(f"authentication failed: {exc}") from exc
    except (SDSEmptyError, SDSInitError, SDSRateLimitError, SDSError, RuntimeError) as exc:
        raise RuntimeError(f"could not reach SOLIDserver API: {exc}") from exc
    except json.JSONDecodeError as exc:
        raise RuntimeError(f"SOLIDserver returned invalid JSON: {exc}") from exc


def normalize_rows(data: Any) -> list[dict[str, Any]]:
    if isinstance(data, list):
        return [row for row in data if isinstance(row, dict)]

    if isinstance(data, dict):
        for key in ("data", "result", "rows", "items"):
            value = data.get(key)
            if isinstance(value, list):
                return [row for row in value if isinstance(row, dict)]
        return [data]

    return []


def extract_total(data: Any) -> int | str:
    rows = normalize_rows(data)
    if rows and "total" in rows[0]:
        return rows[0]["total"]
    if isinstance(data, dict) and "total" in data:
        return data["total"]
    return "?"
