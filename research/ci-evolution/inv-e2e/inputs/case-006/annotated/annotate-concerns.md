# Concerns about the model (and about the evidence)

These items were found while annotating `spec-original/`. I did not change the model; the annotated copy in
`out/spec-annotated/` differs only by added `\*` comment lines. Line numbers refer to `spec-original/`
unless stated otherwise. Items marked **confirmed** were reproduced with TLC on a scratch copy in
`out/tmp/tlc/`. All other items come from reading the code and were not run.

---

## C1. `ReadDeliveryJustified` can fail on a correct forwarded read after the leader restarts (false alarm) — **confirmed**

* `HandleReadIndexResponse` (base.tla:481-501) computes the `acks` of a forwarded read **when the follower
  receives the response**, from the leader's *current* `pendingReads[m.from][m.ctx]`. `Restart`
  (base.tla:575-576) clears `pendingReads`. If the leader crashes and restarts between sending
  `MsgReadIndexResp` and the follower receiving it, the published read gets `acks = {}`, and
  `ReadDeliveryJustified` fails.
* In the code the read **was** justified: the leader sends `MsgReadIndexResp` only after
  `ackCount >= r.quorum()` (raft.go:919-931). The follower appends the `ReadState` without any further check
  (raft.go:1075-1080). So this violation comes from the observer, not from the code.
* Reproduction (scratch only, `out/tmp/tlc/`):
  * `Probe_forward_restart.cfg` on an unmodified copy of `MC.tla`. The invariant was
    `MCReadDeliveryJustified`. Budgets: MaxTerm=1, MaxLogLen=1, campaign 1, read 1, ready 5, crash 1, all
    others 0. TLC reported a violation at depth 20 (95,520 states generated). That trace uses `ClientReadIndex`
    with a non-local requester (see C2).
  * `ProbeMC.tla` is a copy of `MC.tla` whose only change is `MCClientReadIndex(i, c, i)`, so the
    requester is always local. With `Probe_forward_only.cfg` (ready 6) TLC again found a violation, at depth
    21. This time the read goes through the real forwarding path: s3 `ForwardReadIndex` → s1 enqueues and
    sends heartbeats → s2 acks → quorum → `MsgReadIndexResp` to s3 → s1 `Crash` → s1 `Restart` → s3
    `HandleReadIndexResponse` (acks `{}`) → s3 `ReadyPublish`. State diffs are in
    `out/tmp/tlc/probe2_state_diffs.txt`.
* The shipped bounded configs do not reach this: `MC.cfg` has `MaxReadyLimit = 3`, and the `*_s4_*` and
  `*_s5_*` configs have `MaxCrashLimit = 0`. `base.cfg` (`Spec`, no budgets) can reach it.
* Suggestion: record the justification when the leader releases the read, for example by carrying the ack
  set in the response or in a ghost variable written by `HandleHeartbeatResponse`. Do not reconstruct it at
  receipt.

## C2. `ClientReadIndex` lets a leader create a read owned by any server

* `Next`/`MCNext` quantify the requester over all servers (base.tla:606-607, MC.tla:128-129). A leader can
  therefore register a read whose owner is another node, without any `MsgReadIndex` from that node and
  even before that node knows a leader.
* In the code a local `ReadIndex` has `From` = None or self (node.go:502-503; raft.go:927). Reads for other
  nodes reach the leader only through a forwarded `MsgReadIndex` (raft.go:1068-1074).
* The parameter exists because `Trace.tla:84` replays leader-side read events with the forwarder as
  requester. In MC/Spec it over-approximates the code. The first TLC trace in C1 used this shortcut.

## C3. Read-only state is not reset on term or role changes

* Code: `reset()` runs from `becomeFollower`, `becomeCandidate` and `becomeLeader`. It replaces the
  whole read-only state, `r.readOnly = newReadOnly(...)` (raft.go:510), which discards every pending read
  and the queue.
* Model: `Campaign`, `HandleVoteRequest`, `BecomeLeader`, `HandleAppendEntries`, `HandleHeartbeat` and
  `CheckQuorum` all leave `readVars` unchanged. Only `Restart` clears them.
* Consequences, from reading the code (not run):
  * A read registered by a leader in term t (read index = its commit index then) stays in `readQueue`. If
    the same node becomes leader again in a later term, that read can be released on acks gathered in the
    later term. The code would have dropped it. Neither read invariant can tell the difference.
  * The stale-entry behaviour lasts longer in the model than in the code. In read_only.go, `advance`
    deletes `rs.req.Context` (read_only.go:103), but `addRequest` keys entries by `Entries[0].Data`
    (read_only.go:53). Forwarded and local `MsgReadIndex` carry the context only in `Entries`
    (node.go:503, rawnode.go:263), so released entries stay in `pendingReadIndex`. The model preserves this
    on purpose (comment at base.tla:466-467). In the code the stale entry survives only until the next
    `reset()`. In the model it survives until a restart, so a reused context is silently refused for the
    rest of the run. That shrinks the reachable read behaviours. This affects liveness only; no checked
    safety property depends on it.

## C4. No checked property captures read freshness (linearizability)

* `ReadDeliveryJustified` counts acknowledgements. It does not check that they were collected *after*
  the read was registered or in the same term as the read index. It also does not check that the read index
  covers every entry committed before the read was issued.
* That freshness rule is a stated requirement:
  * The guard added by f9382a4: raft.go:826-828, "Reject read only request when this leader has not
    committed any log entry at its term".
  * `TestReadOnlyForNewLeader` (raft_test.go:1859-1860).
* The model enforces the rule only as a guard, `eligible` in `ProcessReadIndex` (base.tla:367-368). If
  that guard were removed or weakened, no property in any cfg would fail.
* Suggestion: add a ghost-based check, for example: for every published read, `index` ≥ the highest
  `commitHistory` index committed before the read was requested.

## C5. `HandleHeartbeat` clamps the commit index where the code panics

* base.tla:345 uses `Min2(m.commit, LastIndex(i))`. The code calls `r.raftLog.commitTo(m.Commit)`
  (raft.go:1100), which panics when `m.Commit` is past the last index (log.go:190-191; test
  log_test.go:451, "commit out of range -> panic").
* The clamp hides exactly the condition that clause 2 of `CommitWithinLog` (commit ≤ log length) exists to
  catch. As modelled, a heartbeat can never violate that clause.
* Suggestion: do not clamp. Either let `CommitWithinLog` catch it, or add an explicit check that
  `m.commit <= LastIndex(i)` whenever a heartbeat is accepted.

## C6. `HandleAppendEntries` truncates without a conflict and lacks the stale-append branch

* base.tla:266-268 rebuilds the log as `SubSeq(logs[i], 1, m.index) \o <<new entry>>` whenever an
  entry is accepted. That drops any suffix after `m.index + 1` even when the existing entry already matches.
* The code truncates only at the first conflicting entry (log.go:76-92, `findConflict` log.go:116-127;
  `TestFollowerAppendEntries`). It also answers stale appends with `m.Index < committed` early, without
  touching the log (raft.go:1085-1088).
* Each `MsgApp` is sent once and nothing is retransmitted, so I found no reachable case in the current
  model where a matching suffix is dropped. If retransmission or duplication is added, a stale `MsgApp`
  could shorten a follower's log below its commit index. That would be a false alarm on `CommitWithinLog`
  and `CommittedPrefixAgreement`.

## C7. `ReadyAdvance` marks entries applied that were never delivered

* base.tla:529 sets `appliedIndex` to the **current** `commitIndex[i]`. The code applies only up to the
  commit carried by the last *published* HardState: `appliedTo(prevHardSt.Commit)` (node.go:375-376;
  rawnode.go:50-61).
* If `commitIndex` advanced between `ReadyPublish` and `ReadyAdvance`, the model counts entries as applied
  that were never handed to the application as `CommittedEntries`.
* The history describes this exact behaviour as a bug. 113ebb1 (message): "Node set the applied to
  committed right after it sends out Ready to application. This is not correct since the application has
  not actually applied the entries at that point."
* `CommitWithinLog` still holds, so nothing fails today. Any future property relating `appliedIndex` to
  delivered entries or to read serving (applied ≥ read index) would be affected.
* Suggestion: `appliedIndex' = durableCommit[i]`, the commit published by the last `ReadyPublish`.

## C8. `BecomeLeader` keeps stale `matchIndex` and `recentActive`

* Code: `reset()` gives every peer a fresh `Progress` (raft.go:502-508). Its `Match` is 0 (lastIndex for
  self) and `RecentActive` is false.
* Model: `BecomeLeader` (base.tla:219-220, 228-230) resets only `matchIndex[i][i]` and `nextIndex`. Other
  peers' `matchIndex` and all of `recentActive` carry over from the node's earlier leadership; `Restart`
  does not reset `matchIndex` either.
* Effects:
  * `CommitCandidate` can count a stale match from an earlier term.
  * `CheckQuorum` can pass on activity seen in an earlier term.
* With `MaxTerm = 2` I believe a stale match cannot commit a wrong entry: rewriting a former leader's log
  needs a leader in a later term, and becoming leader again then needs a third term. I did not verify this
  with TLC. It becomes relevant if `MaxTerm` is raised.

## C9. Other over-approximations in the read path (minor)

* `HandleReadIndexResponse` has no term or role check (base.tla:492-495). In the code, lower-term
  messages are dropped in `Step` (raft.go:713-734), and only `stepFollower` handles `MsgReadIndexResp`
  (raft.go:1075-1080).
* When the leader is not yet eligible, `HandleReadIndexRequest` is simply disabled. The `MsgReadIndex`
  stays in the network and can be served later. The code drops it (raft.go:826-829).
* A non-leader that receives `MsgReadIndex` does not forward it (code: raft.go:1068-1074).
* The lease-based option (raft.go:838-847) is not modelled. By design it delivers reads without acks
  (raft.go:50-55), so `ReadDeliveryJustified` is meant for `ReadOnlySafe` only. The annotation's intent
  says so.

## C10. No log repair, which limits coverage of the log properties

* On reject, `HandleAppendResponse` only lowers `nextIndex` and sends nothing (base.tla:316-317). The code
  calls `sendAppend` (raft.go:866-875).
* `HandleHeartbeatResponse` never sends appends. The code does when `pr.Match < lastIndex`
  (raft.go:911-913).
* After a `LoseMessage` of an `MsgApp`, that follower can never catch up. Catch-up, conflict truncation
  after a leader change, and similar states are therefore mostly unreachable. That weakens what
  `LogMatching`, `CommittedPrefixAgreement` and `LeaderCompleteness` actually exercise.
* Also not modelled: the vote-side step-downs, i.e. a higher-term `MsgVoteResp` and a majority of denials
  (raft.go:684-711, 1022-1023), plus the checkQuorum vote lease (raft.go:688-695) and PreVote. These
  over-approximate and are acceptable for safety.

## C11. `VIEW MCView` drops the budget counters, so bounded runs are incomplete

* `MCView == vars` (MC.tla:156) leaves out `faultCounters`. TLC treats two states with equal views as the
  same state.
* If a state is first reached having spent more budget, then reaching it again with budget left is
  discarded. Successors that need the remaining budget are never explored.
* So "no violation" from the bounded `MC*`/`Reach*` runs depends on search order and is weaker than it
  looks. Suggestion: `MCView == <<vars, faultCounters>>`, or drop the VIEW.

## C12. The trace configs cannot run here, and the trace adapter skips several events

* `Trace.cfg` and `Trace_quorum_loss.cfg` use `TraceFile = "/work/prior/.specula-output/traces/..."`.
  `/work/prior` does not exist, so `ASSUME Len(TraceLog) > 0` cannot be evaluated here.
* `ConsumeCurrent` (Trace.tla:65-92) has no case for `ForwardReadIndex`, `HandleReadIndexRequest`,
  `HandleReadIndexResponse`, `Crash`, `Restart` or `LoseMessage`. Those fall to `OTHER -> FALSE`.
* So `TraceMatched` cannot validate the forwarded-read or crash paths, which is where C1 and C3 live.

## C13. Config and comment inconsistencies, and redundant checks (minor)

* `MC.cfg` says "Scenario reachability invariants are enabled in MC_hunt_*.cfg". In fact no
  `MC_hunt_*.cfg` lists a `Hunt*` invariant; the canaries are in `Reach_*.cfg`.
* Some `Reach_*.cfg` files also leave out some safety invariants: s1 omits the message and read invariants,
  s3 omits the log and read invariants.
* `MessagesWellFormed` repeats what `TypeOK` already enforces for `messages` (base.tla:643-652).
* The ctx/justificationCtx clauses of `ReadyNoInvention` repeat the typing of `publishedReads` in `TypeOK`
  (base.tla:661-664).

## Evidence observations (no property contradicted)

* E1. doc.go:249-252 describes vote granting in terms of "sender's last term is greater than MsgVote's
  term" and "last committed index". That does not match the implemented rule (raft.go:762, log.go:267-269)
  or `TestVoter`. I did not count it as evidence for `LeaderCompleteness`.
* E2. History e769766 removed the invariant "committed < unstable". Its message says a follower may see
  "commit > unstable" and calls that normal. This concerns locally *stable* entries, not the persisted
  HardState against the persisted log. It does not contradict the persisted clause of `CommitWithinLog`,
  because a Ready's HardState and Entries are persisted together (README.md:114).
* E3. The Raft paper and thesis are cited (README.md:5-6, README.md:191, raft_paper_test.go:15-17,
  f1dae53) but their text is not in `/work`. So no `protocol` evidence line could be quoted exactly. The
  core Raft properties rely on the paper-derived tests instead.
