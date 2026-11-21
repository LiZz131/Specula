# V0 model scope: case-007

## Authority and track

Use only `/work/old-tree`. This is a quantitative secondary case and is not
eligible for the primary qualitative discovery denominator. Do not inspect
history, network sources, another revision, subject metadata, or grading inputs.

## Category and boundary

This is a Category A Raft replication subsystem. Model the exact-old
per-follower replication task, AppendEntries request and response flow,
replication progress, retry-policy state, snapshot handoff at the replication
boundary, and RaftCore notifications. Keep the reference Raft safety view
separate from any cost or delay overlay.

## State and actions to derive

Derive session identity, local and remote log progress, pending replication
work, RPC outcome, task lifecycle, and old retry-policy state. Qualitative
actions cover receiving work, creating and sending a request, receiving a
response or transport result, updating progress, retrying, and task closure.

## Quantitative secondary view

If the exact-old implementation supports an auditable discrete abstraction,
record logical attempts, retry steps, or delay classes in a separate view. Do
not invent a wall-clock guarantee or select a threshold using another revision.
Freeze the observation and threshold contract before any update input is made
available.

## Neutral trace baseline

Use the exact-old stream, partial-success, retry, rejoin, and isolated-learner
tests listed in the JSON manifest. Instrument generic lifecycle and progress
events. Do not construct a special post-failure recovery schedule.

## Exclusions

Exclude transport framing, serialization, scheduler implementation details,
allocation, and application payload contents. A qualitative run cannot turn a
finite recurring delay into a protocol deadlock merely by assertion.

## V0 completion rule

Require parser-clean specifications, terminating bounded checks, and fully
consumed fresh exact-old traces. Keep quantitative claims secondary and remove
findings, reproductions, targeted campaigns, expected outcomes, and historical
annotations before freezing.

