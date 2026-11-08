#!/usr/bin/env python3
"""Download only public, pinned catalog/license sources. Never uploads anything."""

import hashlib
import json
from pathlib import Path
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
COMMIT = "c7f7f883fe678cc7680169a50ccd7dcc49b060ce"
BASE = f"https://raw.githubusercontent.com/astronexus/HYG-Database/{COMMIT}"
SOURCES = {
    "hygdata_v41.csv": f"{BASE}/hyg/CURRENT/hygdata_v41.csv",
    "HYG-LICENSE.md": f"{BASE}/hyg/CURRENT/LICENSE",
    "HYG-README.md": f"{BASE}/hyg/README.md",
    "CC-BY-SA-4.0.txt": "https://creativecommons.org/licenses/by-sa/4.0/legalcode.txt",
}


def main():
    original = ROOT / "original"
    original.mkdir(parents=True, exist_ok=True)
    for name, url in SOURCES.items():
        target = original / name
        if target.exists():
            raise SystemExit(f"Refusing to replace source: {target}")
        request = urllib.request.Request(url, headers={"User-Agent": "WeatherMenu-local-catalog/1.0"})
        with urllib.request.urlopen(request, timeout=90) as response:
            data = response.read()
        with target.open("xb") as output:
            output.write(data)
        print(json.dumps({"file": name, "url": url, "bytes": len(data),
                          "sha256": hashlib.sha256(data).hexdigest()}), flush=True)


if __name__ == "__main__":
    main()
