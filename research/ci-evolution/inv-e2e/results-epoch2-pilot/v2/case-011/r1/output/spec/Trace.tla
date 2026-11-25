------------------------------ MODULE Trace ------------------------------
EXTENDS base, Json, IOUtils

\* Trace selection: JSON (trace-debugger tools), SPECULAR_TRACE (harness
\* scripts), else a default retained trace.
JsonFile ==
    IF "JSON" \in DOMAIN IOEnv THEN IOEnv.JSON
    ELSE IF "SPECULAR_TRACE" \in DOMAIN IOEnv THEN IOEnv.SPECULAR_TRACE
    ELSE "../traces/start_election.ndjson"
TraceRecords == ndJsonDeserialize(JsonFile)
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

\* All events of one trace are emitted by the same exact Engine instance.
ASSUME \A k \in 1..Len(TraceLog) : TraceLog[k].nid = Focus

TraceInit ==
    /\ Focus \in Server
    /\ cursor = 1
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
    \* UPDATE-MAP
    \* code: openraft/src/engine/engine_impl.rs:95-101,149-164
    \* update: Update!PreVoteVars
    /\ preCandidateActive = [i \in Server |-> i = Focus /\ Pre.pre_candidate_active]
    /\ preCandidateVote = [i \in Server |-> IF i = Focus
                                                THEN SnapshotVote(Pre.pre_candidate_vote)
                                                ELSE DefaultVote(i)]
    /\ preCandidateConfig = [i \in Server |-> IF i = Focus
                                                  THEN JsonConfig(Pre.pre_candidate_config)
                                                  ELSE <<InitialConfig>>]
    /\ preCandidateLastLog = [i \in Server |-> IF i = Focus
                                                   THEN SnapshotLog(Pre.pre_candidate_last_log)
                                                   ELSE NoLog(i)]
    /\ preGrants = [i \in Server |-> IF i = Focus THEN JsonSet(Pre.pre_grants) ELSE {}]
    /\ sendPreVotePending = [i \in Server |-> i = Focus /\ Pre.send_pre_vote_pending]
    \* ghost observers: not implementation state
    /\ preRound = [i \in Server |-> IF i = Focus /\ Pre.pre_candidate_active THEN 1 ELSE 0]
    /\ preByTimer = [i \in Server |-> FALSE]

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
    /\ leaderActive'[i] = s.leader_active
    /\ votePersistPending'[i] = s.save_vote_pending
    /\ sendVotePending'[i] = s.send_vote_pending
    /\ logFlushPending'[i] = s.append_pending
    /\ seenGreaterLog'[i] = s.seen_greater_log
    /\ crashed'[i] = s.crashed
    \* UPDATE-MAP
    \* code: openraft/src/engine/engine_impl.rs:95-101,298-322,516-554
    \* update: Update!PreVoteVars
    /\ preCandidateActive'[i] = s.pre_candidate_active
    /\ (s.pre_candidate_active => preCandidateVote'[i] = SnapshotVote(s.pre_candidate_vote))
    /\ (s.pre_candidate_active => preCandidateConfig'[i] = JsonConfig(s.pre_candidate_config))
    /\ (s.pre_candidate_active => preCandidateLastLog'[i] = SnapshotLog(s.pre_candidate_last_log))
    /\ (s.pre_candidate_active => preGrants'[i] = JsonSet(s.pre_grants))
    /\ sendPreVotePending'[i] = s.send_pre_vote_pending

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

\* The engine call is Engine::elect() / elect_by_leadership_transfer().
TraceStartElection(e) ==
    /\ DoElect(e.nid, e.args.transfer, FALSE)
    /\ ValidatePost(e.post, e.nid)

\* Runtime boundary: the harness executes the queued SaveVote command.
TracePersistVote(e) ==
    /\ PersistVote(e.nid)
    /\ ValidatePost(e.post, e.nid)

\* Runtime boundary: one spawned SendVote RPC per target, then completion.
TraceSendVoteRequest(e) ==
    /\ SendVoteRequest(e.nid, e.args.target)
    /\ ValidatePost(e.post, e.nid)

TraceFinishVoteBroadcast(e) ==
    /\ FinishVoteBroadcast(e.nid)
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

\* Engine::handle_append_entries with an empty segment at the local last log.
TraceHandleAppendEntries(e) ==
    LET req == Message("Append", e.args.source, e.nid,
                       SnapshotVote(e.args.vote), SnapshotLog(e.args.last_log),
                       FALSE, FALSE)
    IN /\ HandleAppendEntries(e.nid, req, FALSE)
       /\ ValidatePost(e.post, e.nid)

\* UPDATE-MAP
\* code: openraft/src/engine/engine_impl.rs:298-322 (pre_elect)
\* update: Update!AffectedActions
\* The ghost round origin is not observable at the engine boundary.
TracePreElect(e) ==
    /\ \E byTimer \in BOOLEAN : PreElect(e.nid, byTimer, FALSE)
    /\ ValidatePost(e.post, e.nid)

\* Runtime boundary: the harness drains the queued Command::SendPreVote and
\* records its request (vote, last log id) and target set.
TraceSendPreVoteRequests(e) ==
    /\ SendPreVoteRequests(e.nid)
    /\ ValidatePost(e.post, e.nid)
    /\ preCandidateVote[e.nid] = SnapshotVote(e.args.vote)
    /\ preCandidateLastLog[e.nid] = SnapshotLog(e.args.last_log)
    /\ ConfigVoters(preCandidateConfig[e.nid]) \ {e.nid} = JsonSet(e.args.targets)

\* UPDATE-MAP
\* code: openraft/src/engine/engine_impl.rs:414-446 (handle_pre_vote_req)
\* update: Update!AffectedActions, Update!PreVoteResponderSideEffectFree
TraceHandlePreVoteRequest(e) ==
    LET req == PreMessage("PreVoteReq", e.args.source, e.nid,
                          SnapshotVote(e.args.vote), SnapshotLog(e.args.last_log),
                          FALSE, 0)
    IN /\ HandlePreVoteRequest(e.nid, req, FALSE)
       /\ ValidatePost(e.post, e.nid)
       \* the returned VoteResponse: responder vote/last log and granted bit
       /\ SnapshotVote(e.args.response_vote) = vote'[e.nid]
       /\ SnapshotLog(e.args.response_last_log) = lastLog'[e.nid]
       /\ \E m \in messages' :
              /\ m.kind = "PreVoteResp"
              /\ m.source = e.nid
              /\ m.dest = e.args.source
              /\ m.vote = SnapshotVote(e.args.vote)
              /\ m.lastLog = SnapshotLog(e.args.response_last_log)
              /\ m.granted = e.args.response_granted

\* UPDATE-MAP
\* code: openraft/src/engine/engine_impl.rs:516-554 (handle_pre_vote_resp)
\* update: Update!AffectedActions
\* `candidate_vote` is the Notification's echoed request vote; the engine
\* boundary has no round identity, so the current ghost round is assumed.
TraceHandlePreVoteResponse(e) ==
    LET resp == PreMessage("PreVoteResp", e.args.source, e.nid,
                           SnapshotVote(e.args.candidate_vote), SnapshotLog(e.args.last_log),
                           e.args.granted, preRound[e.nid])
    IN /\ HandlePreVoteResponse(e.nid, resp, FALSE)
       /\ ValidatePost(e.post, e.nid)

TraceAppendJointConfig(e) ==
    /\ AppendJointConfig(e.nid, JsonSet(e.args.target_config))
    /\ ValidatePost(e.post, e.nid)

\* Harness time boundary: the vote lease expires (Leased::disable_lease).
TraceExpireLease(e) ==
    /\ ExpireLease(e.nid)
    /\ ValidatePost(e.post, e.nid)

\* Runtime boundary: queued log append executed and its flush completed.
TraceFlushLog(e) ==
    /\ FlushLog(e.nid)
    /\ ValidatePost(e.post, e.nid)

TraceAppendUniformConfig(e) ==
    /\ AppendUniformConfig(e.nid)
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
             [] e.name = "PersistVote"           -> TracePersistVote(e)
             [] e.name = "SendVoteRequest"       -> TraceSendVoteRequest(e)
             [] e.name = "FinishVoteBroadcast"   -> TraceFinishVoteBroadcast(e)
             [] e.name = "HandleVoteRequest"     -> TraceHandleVoteRequest(e)
             [] e.name = "HandleVoteResponse"    -> TraceHandleVoteResponse(e)
             [] e.name = "HandleAppendEntries"   -> TraceHandleAppendEntries(e)
             [] e.name = "PreElect"              -> TracePreElect(e)
             [] e.name = "SendPreVoteRequests"   -> TraceSendPreVoteRequests(e)
             [] e.name = "HandlePreVoteRequest"  -> TraceHandlePreVoteRequest(e)
             [] e.name = "HandlePreVoteResponse" -> TraceHandlePreVoteResponse(e)
             [] e.name = "AppendJointConfig"     -> TraceAppendJointConfig(e)
             [] e.name = "AppendUniformConfig"   -> TraceAppendUniformConfig(e)
             [] e.name = "ExpireLease"           -> TraceExpireLease(e)
             [] e.name = "FlushLog"              -> TraceFlushLog(e)
             [] e.name = "CommitMembership"      -> TraceCommitMembership(e)
             [] e.name = "Restart"               -> TraceRestart(e)
             [] OTHER                             -> FALSE
    /\ cursor' = cursor + 1

TraceDone ==
    /\ cursor = Len(TraceLog) + 1
    /\ UNCHANGED traceVars

TraceNext == TraceStep \/ TraceDone

TraceSpec == TraceInit /\ [][TraceNext]_traceVars /\ WF_traceVars(TraceStep)
\* REQ-EVIDENCE TraceConsumed
\* intent:   every event of the recorded implementation trace is eventually matched by a model step.
\* status:   model-internal
\* watch:    none
\* verified: update
\* review:   ok
TraceConsumed == <>(cursor = Len(TraceLog) + 1)
\* REQ-EVIDENCE TraceTypeOK
\* intent:   TypeOK holds and the trace cursor stays within the bounds of the recorded trace.
\* status:   model-internal
\* watch:    none
\* verified: update
\* review:   ok
TraceTypeOK == TypeOK /\ cursor \in 1..(Len(TraceLog) + 1)
TraceView == <<vars, cursor>>

=============================================================================
