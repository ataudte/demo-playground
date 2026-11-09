import argparse
import importlib.metadata
import json
import platform
import sys

parser = argparse.ArgumentParser()
parser.add_argument("--python-only", action="store_true")
parser.add_argument("--quiet", action="store_true")
args = parser.parse_args()
if not ((3, 12) <= sys.version_info[:2] <= (3, 14)):
    raise SystemExit(
        "This Ansible version requires an existing Python 3.12–3.14. Set ANSIBLE_ENV_PYTHON to a compatible interpreter."
    )
if not args.python_only:
    try:
        version = importlib.metadata.version("ansible-core")
    except importlib.metadata.PackageNotFoundError:
        raise SystemExit("Ansible is missing; run ansible-env setup.") from None
    if version != "2.20.11":
        raise SystemExit("The selected requirements must retain ansible-core 2.20.11.")
    if not args.quiet:
        print(
            json.dumps(
                {
                    "python": platform.python_version(),
                    "platform": platform.system(),
                    "architecture": platform.machine(),
                    "ansible_core": version,
                    "environment": sys.prefix,
                },
                indent=2,
            )
        )
