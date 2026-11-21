# V0 model scope: case-012

## Authority

The only source authority is `/work/old-tree`. Do not inspect history, network
material, another revision, subject metadata, or grading inputs. Generate a
neutral reference for the old commit path without anticipating later code.

## Category and boundary

This is a Category A Raft implementation. Model leader log replication,
per-node acknowledged progress, membership-dependent quorum calculation,
commit advancement, follower commit handling, and the relevant Engine and
RaftCore boundaries present in the exact-old tree.

## State and actions to derive

Use small node, term, and log domains. Derive role and vote, local logs and
commit position, per-node progress values, effective membership, quorum state,
protocol messages, and crash state where the old code requires it. Actions
cover client append, replication send/response, progress update, commit
calculation, follower commit, membership evolution, and ordinary elections.

## Abstraction discipline

Start from externally meaningful per-node progress and quorum behavior. Inspect
the complete exact-old call chain before deciding whether an internal data
structure must be represented for faithful trace validation. Do not introduce a
faulty update, reorder operation, or expected failure into V0.

## Neutral trace baseline

Use exact-old unit tests for progress, quorum, leader append, follower commit,
membership state, and replication state. Add only enough neutral instrumentation
to connect inputs, per-node progress updates, and resulting commit state.

## Exclusions

Exclude metrics, allocation, collection memory layout, network framing,
serialization, precise timing, and application payload meaning. Do not state a
future source delta, expected model edit, or expected property outcome.

## V0 completion rule

Require parser-clean specs, terminating bounded checking, and complete
validation of fresh exact-old traces. Remove bug reports, reproductions,
target-specific campaigns, expected outcomes, and historical annotations before
freezing the prior.

