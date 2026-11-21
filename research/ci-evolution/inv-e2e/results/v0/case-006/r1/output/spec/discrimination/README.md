# Trace discrimination checks (non-vacuity of compared read-lifecycle fields)

Commands (from each subdirectory, states under /dev/shm/specula-e2e-case-006/disc, removed after each run):

    java -cp /work/lib/tla2tools.jar:/work/lib/CommunityModules-deps.jar tlc2.TLC -workers 1 \
         -metadir /dev/shm/specula-e2e-case-006/disc -config <trace>.cfg Trace.tla

| Model / adapter | Trace | Result | Meaning |
|---|---|---|---|
| V0 base + V0 Trace (`v0model/`) | fresh `quorum_read` | TraceCanProgress violated at traceLine 26 | first releasing HandleHeartbeatResponse: updated code reports pendingCount 0, V0 keeps the stale entry |
| V0 | fresh `read_reuse` | violated at 26 | same release point |
| V0 | fresh `delayed_ack` | violated at 26 | same release point |
| V0 | fresh `forwarded_read` | violated at 23 | V0 adapter has no ForwardReadIndex event (schema gap; not semantic evidence) |
| V0 | fresh `quorum_loss` | passes | no read path; unaffected by the update |
| V1 base + V0 Trace adapter (`v1model-v0adapter/`) | archived V0 `quorum_read` | violated at 26 | exact-old trace keeps pendingCount 1 after release; the V1 model deletes it -> archived trace superseded |
| V1 base + V0 adapter | archived V0 `quorum_loss` | passes | read-free behavior unchanged |

Logs: `<dir>/<trace>.log`.
| V0 | fresh `step_down_reads` | violated at traceLine 27 (CheckQuorum step-down) | repair boundary: code resets readOnly (raft.go:794,510); V0 kept the pending read |
| V0 | fresh `higher_term_reads` | violated at traceLine 25 (HandleVoteRequest, higher term) | repair boundary: code resets readOnly (raft.go:710,510); V0 kept the pending read |
