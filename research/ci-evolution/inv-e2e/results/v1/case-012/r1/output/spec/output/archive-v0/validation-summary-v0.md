# Exact-old V0 validation summary

## Result

All nine fresh implementation trace families match `TraceSpec`; all five final bounded safety runs (main plus four scenarios) completed with no invariant violation and empty queues. Because trace collection uses selected exact-old unit environments and model checking uses finite bounds, the suite result is **LIMITED_COVERAGE**, not proof.

No implementation-caused mismatch (Case C) was found. Intermediate failures were classified as trace-spec or model-spec mechanics and corrected without weakening a code-faithful property.

## Trace validation

The runnable harness regenerated 44 nonempty NDJSON events from `/work/work-source`:

| Trace | Events | Final TLC result |
|---|---:|---|
| election | 1 | matched; 2 distinct states |
| leader append | 1 | matched; 2 distinct states |
| leader membership append | 1 | matched; 2 distinct states |
| follower commit | 1 | matched; 2 distinct states |
| membership update | 1 | matched; 2 distinct states |
| progress | 8 | matched; 9 distinct states |
| quorum | 12 | matched; 13 distinct states |
| greatest majority | 11 | matched; 12 distinct states |
| replication lag | 8 | matched; 9 distinct states |

Final evidence is in `output/trace-*-final.log`. Every final run has exit status 0, reaches `l > Len(TraceLog)`, and reports no error. Trace.cfg also checks `TypeOK` and `MembershipOrder`; the isolated follower-commit fixture limitation is documented in `instrumentation-spec.md`.

## Model checking

| Run | Distinct states | Queue at finish | Result |
|---|---:|---:|---|
| `MC.cfg` | 12,831 | 0 | no error |
| scenario 1 progress/loss | 30,034 | 0 | no error |
| scenario 2 membership | 80,705 | 0 | no error |
| scenario 3 follower commit | 12,831 | 0 | no error |
| scenario 4 elections/crash | 30,606 | 0 | no error |

The main enables TypeOK, ElectionSafety, ActiveLeaderHasCommittedVote, CommitWithinLocalLog, CommittedLogAgreement, and MembershipOrder. Focused configurations additionally check CommitWitnessSound and OneOutstandingMembership. Action coverage is positive for election/grant, client append, semantic send/delivery/ack handling, membership proposal, message loss, and crash/recovery across the focused runs.

Three expected-failure reachability models establish non-vacuity: a leader, a commit witness, and an outstanding effective membership are each reached. Their logs are `output/mc-reach-{leader,commit,membership}-final.log`; the named `NotReach*` invariant violations are expected reachability witnesses, not safety findings.

The broad `MC_scale.cfg` run is intentionally reported separately. It reached 10,347,332 distinct states in 600 seconds without a reported invariant violation but timed out with 6,580,486 states queued. It is not treated as exhaustive or green.

## Coverage limitations

- Three model servers and small term/index/action budgets.
- Short exact-old unit scenarios, not a full storage/network cluster.
- Snapshot transfer, purge layout, timer precision, framing, and payload meaning remain outside the binding scope.
- Conflict rejection and negative-ack discard do not have positive action coverage in the converged tight models.

Accordingly, trace validation and model checking are both honest `LIMITED_COVERAGE` results.
