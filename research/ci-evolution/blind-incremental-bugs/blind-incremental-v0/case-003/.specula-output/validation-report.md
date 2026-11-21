# Exact-old Specula V0 validation report

## Outcome

The suite converged trace-first without a mismatch or an invariant finding.
Six real implementation traces were consumed completely by `Trace.tla`. The
bounded main TLC model and all three scenario configurations completed without
violating their code-derived properties. The honest overall status is
`COMPLETED_WITH_LIMITED_COVERAGE`.

## Trace validation

| Trace | Events | Covered path | TLC result |
|---|---:|---|---|
| `apply_valid.ndjson` | 7 | saved block through accepted update, app commit, state save | matched |
| `apply_rejected.ndjson` | 5 | saved response through invalid update rejection | matched |
| `replay_app_only.ndjson` | 6 | app height 2 catches up to saved state/store height 6 | matched |
| `replay_real.ndjson` | 9 | `B=S+1`, `A=S`, final block through real app | matched |
| `replay_mock.ndjson` | 9 | `B=S+1`, `A=B`, final block through saved-response mock app | matched |
| `replay_none.ndjson` | 2 | already synchronized handshake | matched |

Each TLC trace run ended with “Model checking completed. No error has been
found.” and a graph depth exactly one greater than the event count because the
model includes the reconstructed pre-event initial state and terminal stutter.

## Model checking

| Run | Distinct states | Diameter/depth | Result |
|---|---:|---:|---|
| base bounded BFS | 5,344 | 33 | no invariant violation |
| main bounded BFS | 5,126 | 33 | no invariant violation |
| parameter scenario BFS | 183 | 18 | no invariant violation |
| parameter scenario simulation | 80,000,001 checked | depth 100 | no invariant violation |
| durability scenario BFS | 1,719 | 27 | no invariant violation |
| recovery scenario BFS | 3,892 | 33 | no invariant violation |

Non-vacuity configurations preserved expected counterexample witnesses for all
seven coverage markers. Their TLC exit code 12 is the expected result of the
deliberately false `NeverReached*` invariant.

## Build and regression checks

`go mod download` completed under a ten-minute outer timeout. The manifest's
three focused exact-old test groups passed on the instrumented writable copy,
as did both added apply-trace tests and the four selected replay harness cases.
No trace or build command ran without an outer timeout.

The original `go mod download` command produced no stdout/stderr; its empty log
is retained and `spec/output/build-status.log` records the command and exit.

## Limits

The main BFS uses height 2, at most two saved blocks, two crashes, one app
rollback, and three symbolic complete parameter identities. Runtime traces use
one in-memory storage/test environment and selected deterministic branches.
I/O fault injection, store corruption, pruning failures, arbitrary app-hash
behavior, validator changes, peer consensus, and Byzantine behavior are not
claimed covered. See `spec/brief-coverage.md` for the full boundary.
