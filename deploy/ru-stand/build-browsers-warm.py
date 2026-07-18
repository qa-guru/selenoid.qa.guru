#!/usr/bin/env python
"""Build warm/min browsers.json for RU stand from SSOT."""

from __future__ import annotations

import json
from pathlib import Path

REPO = Path(__file__).resolve().parents[5]
SSOT = REPO / "projects" / "selenoid-home" / "dev" / "browsers.json"
OUT = Path(__file__).resolve().parent / "browsers-ru-warm.json"


def warm_min_only(section: dict) -> dict:
    versions = {
        k: v
        for k, v in section.get("versions", {}).items()
        if k.endswith("-min") or ".0-min" in k
    }
    if not versions:
        versions = dict(list(section.get("versions", {}).items())[:2])
    default = section.get("default")
    for candidate in (f"{default}-min", f"{default}.0-min", default):
        if candidate in section.get("versions", {}):
            default = candidate
            break
    return {"default": default or next(iter(versions)), "versions": versions}


def main() -> None:
    src = json.loads(SSOT.read_text())
    out = {}
    for browser in ("chrome", "firefox"):
        if browser in src:
            out[browser] = warm_min_only(src[browser])
    OUT.write_text(json.dumps(out, indent=2, ensure_ascii=False) + "\n")
    print(f"Wrote {OUT} ({len(out)} browsers)")


if __name__ == "__main__":
    main()
