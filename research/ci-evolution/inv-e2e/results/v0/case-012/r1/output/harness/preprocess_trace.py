#!/usr/bin/env python3
"""Select and segment raw probe events for one validation scenario.

Rebased from the V0 prior name filter:
* keep only outermost (depth 0) probes - the update makes Engine helpers call
  each other (leader_append_entries -> update_progress -> VecProgress::update
  -> is_quorum), so nested probes are removed by recorded depth;
* optionally restrict to a comma-separated set of event names;
* split at fixture boundaries: a stateful event whose captured `pre` differs
  from the previous stateful event's `post` starts a new segment (unit tests
  that build several independent engines in one test). Each segment is written
  as <name>-seg<k>.ndjson; a single segment is written as <name>.ndjson.
Fields are never synthesized or edited.
"""

import json
import pathlib
import sys


def main() -> int:
    source = pathlib.Path(sys.argv[1])
    target = pathlib.Path(sys.argv[2])
    names = set(filter(None, (sys.argv[3] if len(sys.argv) > 3 else "").split(",")))
    segments = [[]]
    last_post = None
    for raw_line in source.read_text(encoding="utf-8").splitlines():
        item = json.loads(raw_line)
        if item.get("depth", 0) != 0:
            continue
        event = item["event"]
        if names and event["name"] not in names:
            continue
        if "pre" in event and "post" in event:
            if last_post is not None and event["pre"] != last_post and segments[-1]:
                segments.append([])
            last_post = event["post"]
        segments[-1].append(item)
    segments = [s for s in segments if s]
    if not segments:
        raise SystemExit(f"no events selected from {source}")
    outputs = [target] if len(segments) == 1 else [
        target.with_name(f"{target.stem}-seg{k}.ndjson") for k in range(1, len(segments) + 1)
    ]
    for out, seg in zip(outputs, segments):
        with out.open("w", encoding="utf-8") as stream:
            for item in seg:
                stream.write(json.dumps(item, separators=(",", ":")) + "\n")
        print(out.name, len(seg))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
