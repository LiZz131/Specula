# V0 model scope: case-004

## Authority

Use only `/work/old-tree`. Do not inspect source history, network material,
another revision, subject metadata, or grading inputs. The result is a neutral
description of the old implementation, not a prediction about a later update.

## Category and boundary

This is a Category A crash-fault-tolerant Raft implementation. Model elections,
committed vote state, AppendEntries-style replication, leader and follower
progress, effective membership, learner/voter transitions, joint quorum, and
the Engine-to-RaftCore boundary present in the old tree.

## State and actions to derive

Use small node and log domains. Derive vote ordering, node role, local log and
commit position, per-peer match progress, per-node effective membership,
candidate vote collection, in-flight protocol messages, and crash state from
the old source. Actions should cover election, vote request/response,
leader establishment, append/response, commit advancement, membership
proposal/commit, and crash/restart where supported.

## Atomicity and network

Engine calls are atomic only at their synchronous state-update boundary.
Command execution, persistence, RPC delivery, and responses remain separate
when the old architecture permits interleaving. Model delay and reorder without
forged or Byzantine messages. Do not invent an operation absent from the old
tree.

## Neutral trace baseline

Use existing old-version tests for ordinary elections, adding a learner,
changing membership, electing under the current configuration, and partial
replication success. Instrument state transitions and message boundaries, not a
special failure schedule.

## Exclusions

Exclude metrics formatting, precise time, serialization, transport framing,
application payload semantics, and operations not exposed by the old source.
No future API, candidate behavior, or expected property outcome belongs in V0.

## V0 completion rule

Require parser-clean specifications, terminating bounded reference checking,
and complete validation of fresh exact-old traces. Remove findings, bug reports,
reproductions, target-specific campaigns, and historical annotations before
freezing the prior.

