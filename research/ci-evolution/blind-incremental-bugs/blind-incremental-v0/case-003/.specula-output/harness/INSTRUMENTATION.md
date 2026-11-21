# Harness instrumentation notes

The preserved patch adds an opt-in `internal/speculatrace` package, hooks the
exact-old block application and handshake/replay boundaries, and adds two
focused state-package scenarios. It changes no behavior when
`SPECULA_TRACE_FILE` is unset. See `../spec/instrumentation-spec.md` for the
field-level TLA+ mapping.

If trace validation exposes a timing mismatch, adjust the hook only after
classifying it against the immutable implementation:

1. retain post-action snapshots for all existing events;
2. retain complete parameter fingerprints rather than sampled subfields;
3. keep fixture setup out of recovery traces by resetting only after `Info` at
   the real `Handshake` entry;
4. do not emit `BlockStored` from the replayed `ApplyBlock`, because that block
   was durable before restart;
5. never turn a trace write error into a new production error path.

The current six traces required no instrumentation or specification repairs
during convergence.

