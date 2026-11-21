#!/usr/bin/env python3
"""Filter only nested probe types selected for one validation scenario."""

import json
import pathlib
import sys


def main() -> int:
    source = pathlib.Path(sys.argv[1])
    target = pathlib.Path(sys.argv[2])
    event_filter = sys.argv[3] if len(sys.argv) > 3 else ""
    selected = []
    for raw_line in source.read_text(encoding="utf-8").splitlines():
        item = json.loads(raw_line)
        if not event_filter or item["event"]["name"] == event_filter:
            selected.append(item)
    if not selected:
        raise SystemExit(f"no events selected from {source}")
    with target.open("w", encoding="utf-8") as stream:
        for item in selected:
            stream.write(json.dumps(item, separators=(",", ":")) + "\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
