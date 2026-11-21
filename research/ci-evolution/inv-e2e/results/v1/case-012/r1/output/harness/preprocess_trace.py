#!/usr/bin/env python3
"""Keep pure helper probes and OUTERMOST Engine transitions only.

Engine events carry the nesting depth at which they were captured (see
specula_trace.rs).  A nested Engine call (e.g. update_progress inside
leader_append_entries) is already contained in the outer event's pre/post
snapshots, so replaying it separately would apply it twice.  An optional
comma-separated allowlist further restricts event names for one scenario.
Events are never synthesized or edited.
"""

import json
import pathlib
import sys

ENGINE = {"Elect", "HandleVoteResp", "LeaderAppend", "FollowerCommit", "UpdateCommittedMembership",
          "UpdateProgress", "UpdateEffectiveMembership"}


def main() -> int:
    source = pathlib.Path(sys.argv[1])
    target = pathlib.Path(sys.argv[2])
    allow = set(filter(None, (sys.argv[3] if len(sys.argv) > 3 else "").split(",")))
    selected = []
    dropped_nested = 0
    for raw_line in source.read_text(encoding="utf-8").splitlines():
        item = json.loads(raw_line)
        ev = item["event"]
        if ev["name"] in ENGINE and ev.get("depth", 0) != 0:
            dropped_nested += 1
            continue
        if allow and ev["name"] not in allow:
            continue
        selected.append(item)
    if not selected:
        raise SystemExit(f"no events selected from {source}")
    with target.open("w", encoding="utf-8") as stream:
        for item in selected:
            stream.write(json.dumps(item, separators=(",", ":")) + "\n")
    print(f"{target.name}: kept={len(selected)} nested_engine_dropped={dropped_nested}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
