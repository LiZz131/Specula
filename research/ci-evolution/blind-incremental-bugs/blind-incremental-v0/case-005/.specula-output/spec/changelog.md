# Validation repair changelog

## Round 1: deterministic audit blockers

- Restored required standard-path semantic documentation and executable
  harness runners.
- Preserved original trace bytes and introduced a deterministic native-zxid
  projection for TLC JSON compatibility.
- Changed trace input from a fixed scenario path to runtime `JSON`, dynamic
  transaction derivation, and an end-of-trace temporal obligation.

## Round 2: trace/spec fidelity

- Modeled old marker scheduling between follower enqueue and log append.
- Modeled late epoch-support observations after a leader has completed
  discovery.
- Added event-specific field checks and explicit sync-application state.
- Refined startup restoration, sync choice/application, NEWLEADER eligibility,
  broadcast readiness, and proposal/commit guards from exact-old source.
- Scoped the pipeline invariant's SNAP exception to the exact deserialize-before-
  persistence recovery window visible in `Learner.syncWithLeader`.

## Round 3: closed verification

- Re-ran the neutral harness and retained its raw and normalized traces.
- Replayed every normalized trace before model checking.
- Replaced resource-limited canonical configurations with bounds that complete
  naturally under BFS and leave zero queued states.
- Preserved broader two-voter timeout runs as explicitly limited evidence.

## Round 4: validation back-edge handoff

- Added standard-path copies of the modeling brief and analysis report while
  retaining their compatible root-level predecessors.
- Required every trace replay to finish naturally with `TraceMatched`, exit
  zero, and leave zero states on queue before canonical base/MC checking.
- Added envelope/type consumption for all retained event fields, the
  instrumentation adjustment guide, a schema-v2 empty findings index, and a
  machine-readable suite/provenance manifest generator.

## Result

Converged in four repair rounds. No model-checking implementation finding was
established; broader open-frontier runs remain limited evidence only.
