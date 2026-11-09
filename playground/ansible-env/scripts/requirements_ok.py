"""Fast local check for ordinary requirement entries; advanced pip syntax delegates to pip."""

import importlib.metadata
from pathlib import Path
import subprocess
import sys
from pip._vendor.packaging.requirements import Requirement

for filename in sys.argv[1:]:
    for line in Path(filename).read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        try:
            req = Requirement(line)
            if req.extras or req.url:
                sys.exit(1)
            if req.marker and not req.marker.evaluate():
                continue
            if importlib.metadata.version(req.name) not in req.specifier:
                sys.exit(1)
        except (ValueError, importlib.metadata.PackageNotFoundError):
            sys.exit(1)
sys.exit(
    subprocess.run(
        [sys.executable, "-m", "pip", "check"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    ).returncode
)
