# Harness instrumentation (rebased)

Synchronous, opt-in probes (`-Dspecular.trace.file`, `-Dspecular.trace.scenario`)
in `work-source/` only; the patch against the updated artifact is
`patches/instrumentation.patch` (`git diff` of `work-source`).

Rebase record against V0 (`/work/previous/.specular-output/harness/patches/instrumentation.patch`):

- applied cleanly except the `BroadcastReady` hunk, whose anchor `zk.startup()`
  was removed by the update; re-anchored after `zk.startServing()`;
- renamed `SpeculaTrace`→`SpecularTrace`, `specula.trace.*`→`specular.trace.*`;
- writer extended with `event.peer` (`emitWithPeer`);
- new update probes: `SyncProposalBuffered`, `SyncCommitBuffered`,
  `NewLeaderAck` (before the NEWLEADER ACK write), `NewLeaderAckCounted`,
  `NewLeaderAckRejected` (see `../instrumentation-spec.md` §4).

Rebuild/rerun: see `README.md`.
