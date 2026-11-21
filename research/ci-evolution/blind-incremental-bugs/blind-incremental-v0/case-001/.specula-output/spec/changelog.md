# Validation and model-checking changelog

## Round 0: baseline and instrumentation build

- The pristine exact-old library completed 307 unit tests.
- The first instrumentation compile exposed probe-only type/visibility mismatches.
- Classification: instrumentation cause.
- Resolution: use public-in-crate Engine accessors, explicit Raft vote traits, and string-to-numeric conversion for the exact numeric test config.
- The selected instrumented tests then compiled and passed.

## Round 1: initial trace-first replay

- Collected nonempty initialization, election, leader-establishment, append-replication, and IO-lifecycle NDJSON files from existing exact-old unit tests.
- Each recognized event was mapped to one logged action with complete post-state comparison.
- All trace files were consumed through end-of-file and `TraceMatched` succeeded.
- No property was weakened and no silent catch-all action was introduced.

## Round 2: initial ordinary MC configuration

- A symmetry declaration was attempted with integer node constants.
- TLC rejected it because `Permutations` symmetry sets require model values.
- Classification: configuration cause, before state exploration.
- Resolution: removed the inapplicable symmetry assignment; node count remained explicitly bounded.
- The error log is preserved as `output/model-check-symmetry-config-error.log`.

## Round 3: wide bounded exploration

- A three-node, two-term, length-three model exercised initialization, election, message send/delivery, leader establishment, append, IO progress, commit, crash/restart, and message loss.
- It generated 29,797,931 states and found 6,164,293 distinct states by the last progress report.
- The five-minute outer timeout stopped the run with 3,202,571 states still queued.
- Classification: environment/state-space bound; TLC had reported no invariant violation before termination.
- The incomplete log is preserved as `output/model-check-wide-timeout.log` and is not presented as a pass.

## Round 4: reachability fidelity review

- Coverage review showed that the initial abstraction omitted RaftCore's successful local VoteResponse, which is queued after a pending SaveVote completes (`raft_core.rs:1864-1887`).
- Classification: specification cause.
- Resolution: added `DeliverLocalVoteResponse`, guarded by candidate state and the flushed vote identity, and wired it into base and MC next-state relations.
- This correction restored source-backed self-grant and leadership reachability without changing any invariant.
- The completed bounds were also raised to `MaxTerm = 2` and `MaxLog = 3` so additional election and leader client-append actions were non-vacuous.

## Round 5: final trace-first and ordinary MC

- Regenerated all five traces through the runnable harness.
- Revalidated traces before running ordinary model checking.
- All seven trace events matched complete post-state and were consumed.
- Final MC completed the bounded graph with all next-action branches nonzero.
- TLC generated 1,111,399 states, found 253,262 distinct states, left zero queued, reached depth 27, and reported no invariant error.
- Outcome: trace validation passed for the collected traces; model checking is `LIMITED_COVERAGE` because all state/environment bounds remain finite.
