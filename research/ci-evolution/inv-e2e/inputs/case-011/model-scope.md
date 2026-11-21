# V0 model scope: case-011

## Authority

Use only `/work/old-tree`. The V0 generator must not inspect source history,
network material, another revision, subject metadata, or grading inputs. The
suite describes the old election protocol and does not anticipate a later
feature.

## Category and boundary

This is a Category A crash-fault-tolerant Raft implementation. Model the
exact-old election path, vote ordering and persistence abstraction, role
transitions, log-recency checks, effective membership and joint quorum,
protocol messages, and relevant crash/restart behavior.

## State and actions to derive

Use small domains for nodes, terms, and log positions. Derive local vote and
role, candidate state, per-node effective configuration, last-log information,
in-flight vote and replication messages, and crash state. Actions cover the
election phases, request and response handling, leader establishment, ordinary
membership evolution, AppendEntries contact, and restart as present in old
source.

## Network and progress assumptions

Messages may be delayed or reordered without Byzantine forgery. Do not claim
eventual progress unless an explicit fairness assumption is stated and grounded
in the exact-old scheduler or retry behavior. Keep safety checking usable even
when no fairness is selected.

## Neutral trace baseline

Use old tests for election comparison, leadership seizure, membership change,
election under the current configuration, and follower restart. Instrument
generic vote, role, log, membership, and message boundaries; do not add a
protocol phase or a tailored failure schedule.

## Exclusions

Exclude metrics, precise timeout duration, transport framing, serialization,
application payload contents, and every message or phase absent from the old
tree. Do not state a future update decision or expected property outcome.

## V0 completion rule

Require parser-clean specifications, a terminating bounded reference run, and
fully consumed fresh exact-old traces. Remove findings, reproductions,
target-specific campaigns, expected outcomes, and historical annotations before
freezing.

