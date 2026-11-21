# Concerns

These are things in the model that I think are wrong, plus evidence that contradicts a checked property.
I changed nothing in the model. The annotated copy only adds comments.
"Confirmed by TLC" means I ran a scratch copy of the original model in `out/tmp/` with an extra `.cfg` (listed in `check.md`). Those runs are not part of the model.

---

## C1. `ElectionSafety` checks a Raft rule that this system deliberately dropped (evidence contradicts the property)

- **Property:** `ElectionSafety` (base.tla). Two leaders in the same term must have the same `voteFor`, so a term has at most one leader.
- **Contradicting evidence:**
  - Commit a68a9a9 says (message): "Simplify election: in a `term`, it allows to elect more than one leader and the one with greatest `Vote`, i.e., `term, node_id` wins. Only the last established leader is valid. A node is able to grant more than one vote within one term. A greater `Vote` will always be granted."
  - The same commit deleted the earlier rule "Two committed votes have to be the same" (58f2491:openraft/src/vote/vote.rs:80) and the partial order on `Vote`.
  - `source/openraft/src/vote/leader_id.rs:7-11` says the per-term rule belongs to the raft spec, and that in openraft a leader "is actually identified by `(term, node_id)`".
  - In the code at base: `Vote` derives `PartialOrd, Ord` over `(term, node_id, committed)` (`vote/vote.rs:8-14`). `Engine::internal_handle_vote_req` grants any `vote >= self.state.vote` (`engine_impl.rs:814`). So a voter that granted `(1, n1)` will also grant `(1, n2)` when n2 > n1. Two nodes can then each win a quorum in term 1.
- **Model divergence:** `GrantVote` allows a same-term grant only when `voteFor[voter] = candidate` (base.tla `GrantVote`), which is the classic Raft rule. The model therefore cannot produce a behaviour the code allows by design. `ElectionSafety` passing in MC says nothing about the code.
- **Related:** `CommitCandidates`/`AckedAt` identify the leader's entries by term alone. The code identifies them by `leader_id = (term, node_id)` (`core/replication.rs:213`). These are only equivalent if a term has one leader.
- **Suggestion:** One option is to model the code's total-order vote comparison and check openraft's own safety statement. `guide/src/dynamic-membership.md:203` gives it: "It is impossible that there are two leaders that both can commit a log entry". In practice this is `CommittedLogAgreement` with leaders identified by (term, node_id). The other option is to keep `ElectionSafety` but label it a Raft-protocol property that openraft does not implement at this revision. I marked it `unknown` for this reason.

## C2. `OneOutstandingMembership` is violated after a crash. Confirmed by TLC, and `base.cfg` should hit it

- **Property:** `OneOutstandingMembership`. If `effectiveMembershipIndex[i] > committed[i]`, then `committedMembershipIndex[i] < effectiveMembershipIndex[i]`.
- **Problem:** `Crash(i)` sets `committed[i]` to `Nil` but keeps `committedMembershipIndex[i]` and `effectiveMembershipIndex[i]`. Once a membership entry has been committed (both indexes equal, and ≥ 0), a crash makes the premise true and the conclusion false.
- **TLC (scratch):** `MC.tla` with `MaxCrashes = 1, MaxMembershipChanges = 1, MaxClientAppends = 0, MaxTerm = 1, MaxIndex = 0`, checking only `OneOutstandingMembership`. TLC found a violation in 8 states (629 states generated):
  `StartElection(n1)` → `GrantVote(n1,n2)` → `ProposeMembership(n1,{{n1,n2}})` → `SendAppendEntries(n1,n2)` → `DeliverAppendEntries` → `HandleUpdateMatched` (commit 0; committed and effective membership index both 0) → `Crash(n1)` (`committed = -1`).
- **Which configs:** `base.cfg` uses `Next` (which contains `Crash`) and lists `OneOutstandingMembership`, so it should report this. `MC_hunt_s2_membership.cfg` has `MaxCrashes = 0` and cannot reach it. `MC.cfg` has it commented out.
- **The code reaches the same state on restart.** `RaftCore::do_main` sets `committed = None` (`core/raft_core.rs:193-195`). `StorageHelper::get_membership` sets both `committed` and `effective` to the state-machine membership when the log has no later membership entry (`storage/helper.rs:118-127`). So, stated over the volatile commit index, this formula is not an invariant of the code either.
- **Evidence side:** The sources say "committed" in the cluster sense ("must have been committed"). `raft_state.rs:49` says the commit index "is volatile and will not be persisted".
- **Suggestion:** Option 1: restate it against a durable notion. The model has no `last_applied`. Adding one, or taking the max of `committed` and the applied index, would match `helper.rs`. Option 2: restrict it to nodes that have not crashed since they last committed. Option 3: add a separate check that a membership recorded as committed was committed by some quorum (for example via the witness).

## C3. `CommitWitnessSound` reports a false violation when a node leads again in a later term. Confirmed by TLC; the shipped configs cannot reach it

- **Problem:** Only `Crash` resets the `witness*` records. `matchedIndex`/`matchedTerm` rows survive term changes. When the same node becomes leader again and appends, `LeaderAppendEntries` sets `matchedTerm[i][i]` to the new term. The witness still names `i` with the old `witnessTerm`, so the last conjunct (`matchedTerm[i][j] = witnessTerm[i]`) fails. Yet the committed entry is still present and agreed.
- **TLC (scratch):** `MC.tla` with `MaxTerm = 3, MaxIndex = 1, MaxElectionActions = 3, MaxClientAppends = 2`, everything else 0, checking only `CommitWitnessSound`. TLC found a violation in 12 states (195,175 states generated). n1 leads term 1 and commits index 0 with witness `{n1,n2}`/term 1. n2 starts term 2 and n1 grants it. n1 starts term 3 and wins. `ClientAppend(n1)` sets `matchedTerm[n1][n1] = 3` while `witnessTerm[n1] = 1`.
- **Which configs:** It is checked only in `base.cfg` (MaxTerm 2), `MC_hunt_s1_progress.cfg` and `MC_hunt_s2_membership.cfg` (MaxTerm 1). With MaxTerm ≤ 2, a node cannot lead twice without crashing, so these configs do not reach it. Raising MaxTerm will.
- **Code side:** A new leadership starts fresh replication state (`core/replication.rs:45-50` uses `matched: None`; `LeaderState::run` re-spawns the streams). Matched positions from an earlier leadership are not kept in the code.
- **Suggestion:** Reset (or re-scope) the witness when a node becomes leader or changes term. Alternatively, check only the clauses that do not depend on the current `matchedTerm` row once the node is no longer the leader that committed.

## C4. `DeliverAppendEntries` keeps a conflicting suffix beyond `m.last`

- `CopyLeaderLog(m)` overwrites indexes `≤ m.last` with the sender's terms and keeps the receiver's entries after `m.last`. `lastLog' = IMax(lastLog, m.last)`.
- The code deletes everything from the first conflicting entry before appending (`engine_impl.rs:328-336`: `truncate_logs(entries[since]...)`). `guide/src/replication.md:18-19` requires it: "the follower must delete all entries since this one before storing the input one".
- **Effect in the model:** If a longer follower log conflicts at some index ≤ `m.last`, its tail (> `m.last`) survives behind entries of a newer term. The follower's last entry then has an older term than entries before it. That changes `LogUpToDate` (elections) and what later acks claim. This needs `MaxIndex ≥ 1`, so only `base.cfg` and `MC_scale.cfg` are affected. It can mask or invent behaviour for `CommittedLogAgreement` and `ElectionSafety`.

## C5. Append messages carry no entries; delivery reads the sender's state at delivery time

- The message has only `prev`, `last`, `lastTerm` and `leaderCommit`. Several things are read from the sender's current state when the message is delivered, not as they were when it was sent:
  - `DeliverAppendEntries`/`RejectAppendConflict` compare `logTerm[m.to][m.prev]` with `logTerm[m.from][m.prev]`;
  - `CopyLeaderLog` copies `logTerm[m.from]`;
  - the effective membership (index, config, term) is copied from `m.from`.
- In the code, `AppendEntriesRequest` carries `prev_log_id` and the entries themselves (`raft.rs:820-833`).
- A stale message delivered after the sender stepped down and had its log overwritten would install entries the sender never sent. Its ack would report the `lastTerm` from send time.
- **Membership detail:** `copyMembership` copies only the sender's effective membership, and only if its index ≤ `m.last`. The code scans the received entries for the last two membership entries (`Engine::follower_update_membership` / `last_two_memberships`, `engine_impl.rs:627-702`). When the sender's effective entry is beyond `m.last` but the copied range holds a newer membership entry than the follower's, the model keeps the follower's old effective config.

## C6. `RejectAppendConflict` truncates the log but does not revert the effective membership

- The model sets `lastLog' = m.prev - 1` and clears `logTerm` from `m.prev` on. It leaves `effectiveConfig`, `effectiveMembershipIndex` and `effectiveMembershipTerm` unchanged.
- The code's `Engine::truncate_logs` reverts the effective membership to the committed one when the deleted range contains it (`engine_impl.rs:429-471`). `guide/src/effective-membership.md:7-11` and `:27-29` require this.
- **Effect in the model:** `effectiveMembershipIndex[i]` can point to a deleted entry, beyond `lastLog[i]`. Roles, election quorums and commit quorums keep using a config that is no longer in the log. `MembershipOrder` and `OneOutstandingMembership` still hold, but the transitions that could break them in the code are not exercised.

## C7. Membership proposals are a superset of what `next_safe` produces

- `MCAllowedConfigs` claims to be "Derived from next_safe". But `ProposeMembership(i, cfg)` accepts any `cfg ∈ AllowedConfigs`, whatever the current config is. That includes going straight from `{MCServer}` to the uniform `{MCServer \ {s}}`.
- `Membership::next_safe` returns the joint `c1c2` for `c1 → c2` (`membership/membership.rs:309-316`). `dynamic-membership.md:152-154` requires the new membership to contain a config of the last committed one.
- With three nodes these extra transitions still satisfy quorum intersection, so they probably do not create false alarms. The explored behaviours are still not the code's.

## C8. Smaller observations

- `ActiveLeaderHasCommittedVote` holds by construction in the model: `role` becomes `"leader"` only in the same step that sets `voteCommitted` to `won`, and nothing clears `voteCommitted` while the role stays leader. It mostly guards against future model edits.
- The main configs use `MaxIndex = 0`: a single log index. So `CommittedLogAgreement`, `CommitWithinLocalLog` and `CommitWitnessSound` are exercised on one-entry logs, except in `base.cfg` and in `MC_scale.cfg`, which the cfg itself calls timeout-bounded / LIMITED_COVERAGE.
- `ProgressUpdateValue` (trace-only) always sets `matchedTerm` to `currentTerm[i]`, whatever term the matched entry has. `TraceGreatestMajority` validates `greatest_majority_value` without any term filter. Neither checks the term filter in `get_match_log_ids` (`core/replication.rs:209-216`).
- `CommitWitnessSound`, clause commit-not-below-witness: the only statement that the leader's commit never decreases is the async-raft doc line `1451f96:async-raft/src/core/replication.rs:285`, deleted in 0135e3b. At base it survives only as `std::cmp::max(...)` in `calc_commit_log_id` (`core/replication.rs:189-190`), which is marked "TODO(xp): remove this line". If someone removes that line, nothing outside the code keeps the rule.
