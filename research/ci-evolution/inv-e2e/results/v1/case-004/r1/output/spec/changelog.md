# Changelog: incremental run V0 -> update d7176ef9 (RaftMsg::TransferLeader)

## Round 0 - Generation (Chapter 1-5)
- [disposition] MODEL_CHANGE_REQUIRED: TransferLeader calls Engine::elect without the is_voter guard (analysis-report.md "Incremental update analysis").
- [source-update] base!Elect extracted from V0 StartElection with membership-dependent post-state (voter / present learner keeps candidate, absent node drops candidate+leader); StartElection == IsVoter /\ Elect; new base!HandleTransferLeader (elect / lease-only / ignored branches).
- [repair R1] ReceiveVoteRequest freshness compares full LogId (engine_impl.rs:317) instead of index only; duplicate grant no longer emits SaveVote.
- [repair R2] closed-world vote traffic: requests carry elect-time last_log_id (new base var candidateLast), go to effective voters after SaveVote; grants delivered only from peers that granted, after their vote is flushed; self-grant precedes remote grants (FIFO notification channel).
- [repair R3] ReceiveAppend replaces ReceiveAppendDirect: follower appends the leader's actual entries and applies membership entries (append_membership), role from the new effective config.
- [repair R4] replication acks consume real flush-gated success responses (accepted index + leader vote).
- [repair] new leader progress is fresh (Leader::new); Restart restores leadership only for a member (Engine::startup uses is_leader -> contains); committedConfigs after restart taken from the committed membership entry.
- [property] Update.tla adds ElectionInitiatorIsVoter, CandidateIsVoterOfSnapshot (TLC separating/control states in spec/evidence/E1).

## Round 1 - Validation (harness rebase + trace validation)
- [harness] V0 patch reapplied unchanged on the update tree; rebased patch adds shared capture, candidate_last fields, full-LogId/entries args, RaftCore window probes, and 4 unit + 2 window scenarios (harness/INSTRUMENTATION.md).
- [observation] learner transfer target panics: `target not in quorum set` at proposer/candidate.rs:92 (unit and live cluster; traces/window/t99-transfer-to-learner/observations.json).
- [fix-spec] ReceiveVoteResponse requires the granting peer to be in the candidate quorum set; new base!CoreVoteResponsePanic models the grant_by panic (corePanic history flag, core stops); Update.tla adds NoCorePanic. (Trace: elect-learner.ndjson, t99 00004-vote-response-n3)
- [fix-trace-mapping] accepted_index: update_vote to a greater vote accepts IOId::new(vote) with no log id; Trace.tla observer accVoteIO maps this to -1 (r1 -> r2: 8 failures fixed). (Traces: elect-learner, elect-absent, t14/t99 transfer-elect, vote-request windows)
- [fix-spec] ReceiveVoteReject also covers a response with no current candidate (leader's committed-vote self-response passes does_vote_match). (Traces: t14 00007-vote-response-n2, t99 00012-vote-response-n0)
- [result] r3: 34/34 fresh traces PASS (TraceMatched + full post-state); 27/27 field/argument mutations rejected (spec/output/field-consumption/summary.tsv).
- [evidence] V0 suite replays 8/8 prior regression traces from the new code and rejects the 4 update/repair traces (spec/evidence/V0-replay/summary.tsv).

## Round 2 - Model Checking (standard MC.cfg)
- [fix-spec, Case B: bound artifact] MCTypeOK violated at depth 23 (spec/output/mc-standard-iter01-typeok.log): voter 2 won a transfer election with a full log and the establishment blank reached index MaxIndex+1. Not a system property; MCVoteResponse now explores a winning response only while the blank fits MaxIndex (exploration bound, like V0's counters). Base semantics unchanged.
- [result] standard MC.cfg (rerun): no violation; 30-min budget reached: 273,883,264 states generated, 51,451,838 distinct, depth 27, 19,201,232 left on queue (LIMITED_COVERAGE). Action coverage: spec/output/mc-standard-coverage.tsv (MCAddLearner and MCUniform 0 as in the MembershipLimit=1 bound; uniform exercised in Update_hunt_U1_absent*).

## Round 3 - Update campaigns (batch A)
- [bug] ElectionInitiatorIsVoter / CandidateIsVoterOfSnapshot / NoCorePanic violated over full MCNext (Update_full*.cfg), focused and open specs: learner transfer target elects and its RaftCore panics on its own vote grant (Case C; matches the real reproduction).
- [canary] reached: NonVoterCandidate, TransferVoterLeader, OldLeaderSuperseded, CrashBeforeSaveVote.
- [unresolved, pre-existing] Update_hunt_U1_absent.cfg (3 initial voters) violated MCDurableStateBounded before any transfer: the leader commits with a quorum excluding itself and SaveCommitted (no flush condition, engine/command.rs:240) persists committed ahead of its own durable log. docs/data/log_pointers.md:28-34 says committed <= flushed need not hold, while RaftState::validate requires committed <= last_log_id (raft_state/mod.rs:177) after restart; the outcome depends on storage ordering of save_committed vs append flush. Independent of the update; recorded as NEEDS MORE INFO, property not edited. Variant Update_hunt_U1_absent_nodsb.cfg omits only that already-recorded invariant to continue the absent-target scenario.

## Round 4 - Update campaigns (batches B, C, simulations)
- [result] Update_full_voter, Update_focused_voter, Update_open_voter, Update_discharge, Update_hunt_U3_voter, Update_hunt_U4_crash: no violation within budget (BFS 20-30 min + 20-min simulation follow-ups); all budget-limited (LIMITED_COVERAGE).
- [canary] CanaryTransferLeaderCommits reached by simulation (50 states, under a joint config); CanaryAbsentElect reached (21 states).
- [bug] Update_hunt_U1_absent_nodsb: ElectionInitiatorIsVoter violated by a removed leader handling TransferLeader(to=self) -- same root cause as MC-1.

## Final regression
- trace-validation-final: 34/34 fresh traces PASS on the final base/Trace (spec/output/trace-validation-final/summary.tsv).

## Result
Generation, validation and model checking completed for MODEL_CHANGE_REQUIRED. Converged after 1 validation repair batch and 1 MC bound repair. Bug hunting: 1 update-introduced bug (MC-1, REPRODUCED on the real implementation, absent on baseline) plus 1 pre-existing unresolved MC observation (MC-2, NEEDS MORE INFO). All clean model-checking results are budget-limited.
