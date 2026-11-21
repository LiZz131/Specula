#!/usr/bin/env python3
"""Select the top-level (depth 0) events of one validation scenario.

V1: Engine actions now call other traced Engine actions, so every event carries
`depth` (number of enclosing traced Engine actions). Only depth-0 events are
kept; an optional comma-separated name filter can further restrict them.
Events are copied verbatim; no field is synthesized or edited.
"""

import json
import pathlib
import sys


def main() -> int:
    source = pathlib.Path(sys.argv[1])
    target = pathlib.Path(sys.argv[2])
    names = set(filter(None, (sys.argv[3] if len(sys.argv) > 3 else "").split(",")))
    selected = []
    for raw_line in source.read_text(encoding="utf-8").splitlines():
        item = json.loads(raw_line)
        event = item["event"]
        if event.get("depth", 0) != 0:
            continue
        if names and event["name"] not in names:
            continue
        selected.append(item)
    if not selected:
        raise SystemExit(f"no events selected from {source}")
    with target.open("w", encoding="utf-8") as stream:
        for item in selected:
            stream.write(json.dumps(item, separators=(",", ":")) + "\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
