------------------------------ MODULE Trace ------------------------------
EXTENDS base, Json, IOUtils

(***************************************************************************
 * Linear (Category A) replay of engine-level NDJSON traces collected by    *
 * harness/run.sh. Each file is produced by one test on one Engine; the     *
 * first event's `pre` state seeds the focus node, later events are checked *
 * by their `post` state only. See instrumentation-spec.md.                 *
 *************************************************************************)

TraceRecords == ndJsonDeserialize(IOEnv.SPECULA_TRACE)
TraceLog == [k \in 1..Len(TraceRecords) |-> TraceRecords[k].event]

ASSUME Len(TraceLog) > 0

JsonSet(s) == {s[k] : k \in 1..Len(s)}
JsonConfig(c) == [k \in 1..Len(c) |-> JsonSet(c[k])]

SnapshotVote(v) == [term |-> v.term, node |-> v.node, committed |-> v.committed]
SnapshotLog(l) == [present |-> l.present, term |-> l.term, node |-> l.node, index |-> l.index]

PreEvent == TraceLog[1]
Focus == PreEvent.nid
Pre == PreEvent.pre

VARIABLE cursor
traceVars == <<vars, cursor>>

TraceInit ==
    /\ Focus \in Server
    /\ cursor = 1
    \* Harness contract: commands are drained before the first event, so no
    \* request can be in flight in the seeded state.
    /\ ~Pre.send_pre_vote_pending
    /\ role = [i \in Server |-> IF i = Focus THEN Pre.role
                                  ELSE IF i \in InitialConfig THEN "Follower" ELSE "Learner"]
    /\ vote = [i \in Server |-> IF i = Focus THEN SnapshotVote(Pre.vote) ELSE DefaultVote(i)]
    /\ durableVote = vote
    /\ votePersistPending = [i \in Server |-> IF i = Focus THEN Pre.save_vote_pending ELSE FALSE]
    /\ replyPending = [i \in Server |-> FALSE]
    /\ replyMessage = [i \in Server |-> NoMessage]
    /\ sendVotePending = [i \in Server |-> IF i = Focus THEN Pre.send_vote_pending ELSE FALSE]
    /\ leaseValid = [i \in Server |-> IF i = Focus THEN Pre.lease_valid ELSE FALSE]
    /\ candidateActive = [i \in Server |-> i = Focus /\ Pre.candidate_active]
    /\ candidateVote = [i \in Server |-> IF i = Focus
                                             THEN SnapshotVote(Pre.candidate_vote)
                                             ELSE DefaultVote(i)]
    /\ candidateConfig = [i \in Server |-> IF i = Focus
                                               THEN JsonConfig(Pre.candidate_config)
                                               ELSE <<InitialConfig>>]
    /\ grants = [i \in Server |-> IF i = Focus THEN JsonSet(Pre.grants) ELSE {}]
    /\ sentVoteReq = [i \in Server |-> {}]
    \* UPDATE-MAP
    \* code: engine_impl.rs:Engine::pre_candidate (captured via pre_candidate_ref())
    \* update: Update!PreVoteVisible
    /\ preCandidateActive = [i \in Server |-> i = Focus /\ Pre.pre_candidate_active]
    /\ preCandidateVote = [i \in Server |-> IF i = Focus /\ Pre.pre_candidate_active
                                                THEN SnapshotVote(Pre.pre_candidate_vote)
                                                ELSE DefaultVote(i)]
    /\ preCandidateConfig = [i \in Server |-> IF i = Focus /\ Pre.pre_candidate_active
                                                  THEN JsonConfig(Pre.pre_candidate_config)
                                                  ELSE <<InitialConfig>>]
    /\ preGrants = [i \in Server |-> IF i = Focus /\ Pre.pre_candidate_active
                                         THEN JsonSet(Pre.pre_grants) ELSE {}]
    \* Ghost: the engine does not record who started a round.
    /\ preCandidateByTick = [i \in Server |-> FALSE]
    /\ leaderActive = [i \in Server |-> i = Focus /\ Pre.leader_active]
    /\ leaderVote = [i \in Server |-> IF i = Focus THEN SnapshotVote(Pre.vote) ELSE DefaultVote(i)]
    /\ leaderCertified = [i \in Server |-> FALSE]
    /\ leaderConfig = [i \in Server |-> IF i = Focus
                                            THEN JsonConfig(Pre.effective_config)
                                            ELSE <<InitialConfig>>]
    /\ leaderGrants = [i \in Server |-> {}]
    /\ lastLog = [i \in Server |-> IF i = Focus THEN SnapshotLog(Pre.last_log) ELSE NoLog(i)]
    /\ durableLastLog = lastLog
    /\ logFlushPending = [i \in Server |-> IF i = Focus THEN Pre.append_pending ELSE FALSE]
    /\ committedConfig = [i \in Server |-> IF i = Focus
                                               THEN JsonConfig(Pre.committed_config)
                                               ELSE <<InitialConfig>>]
    /\ committedConfigIndex = [i \in Server |-> IF i = Focus THEN Pre.committed_config_index ELSE 0]
    /\ effectiveConfig = [i \in Server |-> IF i = Focus
                                               THEN JsonConfig(Pre.effective_config)
                                               ELSE <<InitialConfig>>]
    /\ effectiveConfigIndex = [i \in Server |-> IF i = Focus THEN Pre.effective_config_index ELSE 0]
    /\ durableConfig = effectiveConfig
    /\ durableConfigIndex = effectiveConfigIndex
    /\ messages = {}
    /\ crashed = [i \in Server |-> i = Focus /\ Pre.crashed]
    /\ seenGreaterLog = [i \in Server |-> i = Focus /\ Pre.seen_greater_log]

ValidatePost(s, i) ==
    /\ role'[i] = s.role
    /\ vote'[i] = SnapshotVote(s.vote)
    /\ lastLog'[i] = SnapshotLog(s.last_log)
    /\ committedConfig'[i] = JsonConfig(s.committed_config)
    /\ committedConfigIndex'[i] = s.committed_config_index
    /\ effectiveConfig'[i] = JsonConfig(s.effective_config)
    /\ effectiveConfigIndex'[i] = s.effective_config_index
    /\ leaseValid'[i] = s.lease_valid
    /\ candidateActive'[i] = s.candidate_active
    /\ (s.candidate_active => candidateVote'[i] = SnapshotVote(s.candidate_vote))
    /\ (s.candidate_active => candidateConfig'[i] = JsonConfig(s.candidate_config))
    /\ (s.candidate_active => grants'[i] = JsonSet(s.grants))
    \* UPDATE-MAP
    \* code: engine_impl.rs:Engine::pre_candidate; engine/command.rs:Command::SendPreVote
    \* update: Update!PreVoteVisible
    /\ preCandidateActive'[i] = s.pre_candidate_active
    /\ (s.pre_candidate_active => preCandidateVote'[i] = SnapshotVote(s.pre_candidate_vote))
    /\ (s.pre_candidate_active => preCandidateConfig'[i] = JsonConfig(s.pre_candidate_config))
    /\ (s.pre_candidate_active => preGrants'[i] = JsonSet(s.pre_grants))
    \* A queued SendPreVote command corresponds to emitted PreVoteReq messages
    \* (RaftCore drains it right after the engine event; see base!PreElect).
    /\ s.send_pre_vote_pending = (\E m \in messages' : m.kind = "PreVoteReq" /\ m.source = i)
    /\ leaderActive'[i] = s.leader_active
    /\ votePersistPending'[i] = s.save_vote_pending
    /\ sendVotePending'[i] = s.send_vote_pending
    /\ logFlushPending'[i] = s.append_pending
    /\ seenGreaterLog'[i] = s.seen_greater_log
    /\ crashed'[i] = s.crashed

ResponseMatches(e, i) ==
    LET expectedVote == SnapshotVote(e.args.response_vote)
        expectedGranted == e.args.response_granted
    IN \/ /\ replyPending'[i]
           /\ replyMessage'[i].kind = "VoteResp"
           /\ replyMessage'[i].vote = expectedVote
           /\ replyMessage'[i].granted = expectedGranted
       \/ \E m \in messages' :
              /\ m.kind = "VoteResp"
              /\ m.source = i
              /\ m.dest = e.args.source
              /\ m.vote = expectedVote
              /\ m.granted = expectedGranted

TraceStartElection(e) ==
    /\ StartElection(e.nid, e.args.transfer)
    /\ ValidatePost(e.post, e.nid)

TraceHandleVoteRequest(e) ==
    LET req == Message("VoteReq", e.args.source, e.nid,
                       SnapshotVote(e.args.vote), SnapshotLog(e.args.last_log),
                       FALSE, e.args.transfer)
    IN /\ HandleVoteRequest(e.nid, req, FALSE)
       /\ ValidatePost(e.post, e.nid)
       /\ ResponseMatches(e, e.nid)

TraceHandleVoteResponse(e) ==
    LET resp == Message("VoteResp", e.args.source, e.nid,
                        SnapshotVote(e.args.vote), SnapshotLog(e.args.last_log),
                        e.args.granted, FALSE)
    IN /\ HandleVoteResponse(e.nid, resp, FALSE)
       /\ ValidatePost(e.post, e.nid)

\* UPDATE-MAP
\* code: openraft/src/engine/engine_impl.rs:291-322 (Engine::pre_elect)
\* update: Update!AffectedActions (MCTickPreElect / MCExternalPreElect)
\* The engine-level call is shared by the timer and the external trigger; the
\* runtime-only guards and the origin ghost are not observable here, so the
\* replay uses the external-trigger form (no seen_greater_log reset). When a
\* SendPreVote command was queued, every emitted request must carry exactly
\* the captured request vote and last-log snapshot.
TracePreElect(e) ==
    /\ PreElect(e.nid, FALSE, seenGreaterLog[e.nid])
    /\ ValidatePost(e.post, e.nid)
    /\ e.args.request_present =
          (\E m \in messages' \ messages : m.kind = "PreVoteReq" /\ m.source = e.nid)
    /\ \A m \in messages' \ messages :
          m.kind = "PreVoteReq" =>
              /\ m.vote = SnapshotVote(e.args.request_vote)
              /\ m.lastLog = SnapshotLog(e.args.request_last_log)
    /\ {m.dest : m \in {x \in messages' \ messages : x.kind = "PreVoteReq"}} = JsonSet(e.args.request_targets)

\* UPDATE-MAP
\* code: openraft/src/engine/engine_impl.rs:406-447, raft_core.rs:1551-1562
\* update: Update!AffectedActions (MCDeliverPreVoteRequest), Update!PreVoteRequestIsReadOnly
TraceHandlePreVoteRequest(e) ==
    LET req == Message("PreVoteReq", e.args.source, e.nid,
                       SnapshotVote(e.args.vote), SnapshotLog(e.args.last_log),
                       FALSE, FALSE)
    IN /\ HandlePreVoteRequest(e.nid, req, FALSE)
       /\ ValidatePost(e.post, e.nid)
       /\ Message("PreVoteResp", e.nid, e.args.source, SnapshotVote(e.args.vote),
                  SnapshotLog(e.args.response_last_log), e.args.response_granted, FALSE)
             \in messages'
       \* The response returns the responder's unchanged vote.
       /\ SnapshotVote(e.args.response_vote) = vote'[e.nid]

\* UPDATE-MAP
\* code: openraft/src/engine/engine_impl.rs:511-554
\* update: Update!AffectedActions (MCDeliverPreVoteResponse),
\*         Update!TickPreVoteNeverDeposesLeader
TraceHandlePreVoteResponse(e) ==
    LET resp == Message("PreVoteResp", e.args.source, e.nid,
                        SnapshotVote(e.args.candidate_vote), SnapshotLog(e.args.last_log),
                        e.args.granted, FALSE)
    IN /\ HandlePreVoteResponse(e.nid, resp, FALSE)
       /\ ValidatePost(e.post, e.nid)

TraceAppendJointConfig(e) ==
    /\ AppendJointConfig(e.nid, JsonSet(e.args.target_config))
    /\ ValidatePost(e.post, e.nid)

TraceCommitMembership(e) ==
    /\ CommitMembership(e.nid)
    /\ ValidatePost(e.post, e.nid)

TraceRestart(e) ==
    /\ Restart(e.nid)
    /\ ValidatePost(e.post, e.nid)

TraceStep ==
    /\ cursor \in 1..Len(TraceLog)
    /\ LET e == TraceLog[cursor]
       IN CASE e.name = "StartElection"         -> TraceStartElection(e)
             [] e.name = "HandleVoteRequest"    -> TraceHandleVoteRequest(e)
             [] e.name = "HandleVoteResponse"   -> TraceHandleVoteResponse(e)
             [] e.name = "PreElect"             -> TracePreElect(e)
             [] e.name = "HandlePreVoteRequest" -> TraceHandlePreVoteRequest(e)
             [] e.name = "HandlePreVoteResponse"-> TraceHandlePreVoteResponse(e)
             [] e.name = "AppendJointConfig"    -> TraceAppendJointConfig(e)
             [] e.name = "CommitMembership"     -> TraceCommitMembership(e)
             [] e.name = "Restart"              -> TraceRestart(e)
             [] OTHER                            -> FALSE
    /\ cursor' = cursor + 1

TraceDone ==
    /\ cursor = Len(TraceLog) + 1
    /\ UNCHANGED traceVars

TraceNext == TraceStep \/ TraceDone

TraceSpec == TraceInit /\ [][TraceNext]_traceVars /\ WF_traceVars(TraceStep)
TraceConsumed == <>(cursor = Len(TraceLog) + 1)
TraceTypeOK == TypeOK /\ cursor \in 1..(Len(TraceLog) + 1)
TraceView == <<vars, cursor>>

=============================================================================
