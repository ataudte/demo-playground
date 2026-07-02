#!/usr/bin/env python3

# Shared configuration helper for the SOLIDserver advanced Python demo scripts.
# Loads all demo values from a local .env file or exported environment variables.
# Keeps credentials, IPAM context, demo naming, and output artifact names in one place.
# Required settings fail fast with a clear error instead of silently using hidden defaults.

from __future__ import annotations

import argparse
import os
from dataclasses import dataclass
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
OUTPUT_DIR = REPO_ROOT / "output"


def load_dotenv(path: Path | None = None) -> None:
    dotenv_path = path or REPO_ROOT / ".env"

    if not dotenv_path.exists():
        return

    for raw_line in dotenv_path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()

        if not line or line.startswith("#") or "=" not in line:
            continue

        key, value = line.split("=", 1)
        key = key.strip()
        value = value.strip().strip('"').strip("'")

        os.environ.setdefault(key, value)


def env_required(name: str) -> str:
    value = os.getenv(name, "").strip()

    if not value:
        raise RuntimeError(f"missing required setting {name}; set it in .env or export it in your shell")

    return value


def env_bool(name: str) -> bool:
    value = env_required(name)
    return value.lower() in {"1", "true", "yes", "y", "on"}


def env_int(name: str) -> int:
    return int(env_required(name))


@dataclass(frozen=True)
class DemoConfig:
    host: str
    user: str
    password: str
    verify_tls: bool
    auth_method: str
    timeout: int
    default_space: str
    demo_prefix: int
    demo_subnet_name: str
    demo_hostname: str
    output_01_ipam_context: str
    output_02_subnet_allocation: str
    output_03_dns_record: str
    output_dir: Path = OUTPUT_DIR


def get_config() -> DemoConfig:
    load_dotenv()

    return DemoConfig(
        host=env_required("SDS_HOST"),
        user=env_required("SDS_USER"),
        password=env_required("SDS_PASSWORD"),
        verify_tls=env_bool("SDS_VERIFY_TLS"),
        auth_method=env_required("SDS_AUTH_METHOD"),
        timeout=env_int("SDS_TIMEOUT"),
        default_space=env_required("SDS_DEFAULT_SPACE"),
        demo_prefix=env_int("SDS_DEMO_PREFIX"),
        demo_subnet_name=env_required("SDS_DEMO_SUBNET_NAME"),
        demo_hostname=env_required("SDS_DEMO_HOSTNAME"),
        output_01_ipam_context=env_required("SDS_OUTPUT_01_IPAM_CONTEXT"),
        output_02_subnet_allocation=env_required("SDS_OUTPUT_02_SUBNET_ALLOCATION"),
        output_03_dns_record=env_required("SDS_OUTPUT_03_DNS_RECORD"),
    )


def add_common_args(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--apply", action="store_true", help="create or update objects in SOLIDserver")
    parser.add_argument("--limit", type=int, default=5, help="maximum number of rows to print")


def ensure_output_dir() -> Path:
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    return OUTPUT_DIR
