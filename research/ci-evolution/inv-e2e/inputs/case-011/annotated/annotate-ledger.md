# Requirement-evidence ledger

There is one row per property in scope: every operator after `INVARIANT(S)`/`PROPERTY(IES)` in
`spec-original/*.cfg`. No cfg contains a commented-out property line, `Update.tla` does not exist, and
no property is an alias (`A == B`). Each block lives directly above its definition in
`out/spec-annotated/`.

| Property | Module | Checked in | Status | Evidence types | Intent (one line) |
|---|---|---|---|---|---|
| `TypeOK` | base.tla | base.cfg | model-internal | — | Every model variable and in-flight message stays inside its declared domain. |
| `MCTypeOK` | MC.tla | MC.cfg, MC-membership.cfg | model-internal | — | `TypeOK` holds and the bounded-checking fault counters stay within limits. |
| `TraceTypeOK` | Trace.tla | Trace.cfg | model-internal | — | `TypeOK` holds and the trace cursor stays within the recorded trace. |
| `TraceConsumed` | Trace.tla | Trace.cfg (PROPERTY) | model-internal | — | Every recorded trace event is eventually matched by a model step. |
| `NoForgedMessageEndpoints` | base.tla | all four cfgs | model-internal | — | Every in-flight message is from and to a node of the modelled server set. |
| `DurableVoteNotAhead` | base.tla | all four cfgs | requirement | comment, doc, impl | Vote I/O flushed to storage never runs ahead of the vote I/O the node has accepted. |
| `DurableLogNotAhead` | base.tla | all four cfgs | requirement | comment, doc, contract, impl | Log I/O flushed to storage never runs ahead of the log I/O the node has accepted. |
| `VoteRequestAfterDurable` | base.tla | base.cfg, MC.cfg, MC-membership.cfg | impl-abstraction | test, contract, impl | A node sends vote requests only for a vote already persisted in its own storage. |
| `GrantedResponseAfterDurable` | base.tla | base.cfg, MC.cfg, MC-membership.cfg | requirement | history, test, contract, impl | A granted vote response leaves a node only after the granted vote is persisted there. |
| `LeaderRoleHasCommittedSelfVote` | base.tla | all four cfgs | requirement | doc, comment, test, impl | A node in the Leader role holds a committed vote naming itself. |
| `CandidateRoleHasPendingSelfVote` | base.tla | all four cfgs | requirement | doc, comment, test, impl | A node in the Candidate role holds a not-yet-committed vote naming itself. |
| `CertifiedLeaderHasFrozenQuorum` | base.tla | all four cfgs | mixed (quorum-granted: requirement; frozen-config: impl-abstraction) | comment, doc, contract, test, impl | A self-elected leader's vote was granted by a quorum (a majority of every constituent config) of the membership captured at election start. |
| `MembershipAtMostOneOutstanding` | base.tla | all four cfgs | requirement | comment, doc, history, test, impl | Committed membership is never newer than effective, and at most one config beyond the committed one is outstanding. |

## Counts by status

| Status | Count | Properties |
|---|---|---|
| requirement | 6 | DurableVoteNotAhead, DurableLogNotAhead, GrantedResponseAfterDurable, LeaderRoleHasCommittedSelfVote, CandidateRoleHasPendingSelfVote, MembershipAtMostOneOutstanding |
| impl-abstraction | 1 | VoteRequestAfterDurable |
| mixed | 1 | CertifiedLeaderHasFrozenQuorum |
| unknown | 0 | — |
| model-internal | 5 | TypeOK, MCTypeOK, TraceTypeOK, TraceConsumed, NoForgedMessageEndpoints |
| **total** | **13** | |

## Confidence notes

- **DurableVoteNotAhead:** the requirement status rests on the IOProgress invariant (`flushed <= submitted <= accepted`),
  and the intent was narrowed to that reading. When `enable_leader_restore = false`, the source deliberately keeps
  the stored vote above the in-memory `RaftState.vote` (concerns.md C1). This was the least certain classification.
- **VoteRequestAfterDurable:** classified impl-abstraction, not unknown. The history (`36d2c115`, `88754e09`) records that
  command execution may be reordered and that `SaveVote` may become callback-based. The persistence rule it does record
  is about the self-grant, not about sending requests.
- **CertifiedLeaderHasFrozenQuorum:** classified mixed, not model-internal, even though it is stated over ghost variables.
  It expresses the election-quorum rule, which has strong evidence. The "frozen config" part has only impl support.
- **GrantedResponseAfterDurable:** no code comment states the rule. It rests on three commit messages, one engine test
  and the storage contract.
