------------------------------ MODULE Trace ------------------------------
EXTENDS base, Json, IOUtils

(***************************************************************************
 * Category A linear trace replay. One file per scenario, one focus node.  *
 * Each event carries the focus node's captured pre- and post-state. The   *
 * first event's pre-state seeds TraceInit; every later event's pre-state *
 * is compared with the model state before its action fires. Between two  *
 * events the harness drains the engine command queue the way RaftCore     *
 * does (save_vote, SendVote spawn, log append completion); those runtime  *
 * steps are replayed by silent actions that are enabled only when the     *
 * next event's captured pre-state shows the corresponding flag cleared.   *
 *************************************************************************)

\* Trace path: IOEnv.JSON (trace-debugger tools) or IOEnv.SPECULA_TRACE (harness scripts).
TraceFile ==
    IF "JSON" \in DOMAIN IOEnv THEN IOEnv.JSON
    ELSE IF "SPECULA_TRACE" \in DOMAIN IOEnv THEN IOEnv.SPECULA_TRACE
    ELSE "../traces/start_election.ndjson"
TraceRecords == ndJsonDeserialize(TraceFile)
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
    \* code: openraft/src/engine/engine_impl.rs:95-101 (pre_candidate)
    \* update: Update!AffectedActions
    /\ preCandidateActive = [i \in Server |-> i = Focus /\ Pre.pre_candidate_active]
    /\ preCandidateVote = [i \in Server |-> IF i = Focus /\ Pre.pre_candidate_active
                                                THEN SnapshotVote(Pre.pre_candidate_vote)
                                                ELSE DefaultVote(i)]
    /\ preCandidateConfig = [i \in Server |-> IF i = Focus /\ Pre.pre_candidate_active
                                                  THEN JsonConfig(Pre.pre_candidate_config)
                                                  ELSE <<InitialConfig>>]
    /\ preGrants = [i \in Server |-> IF i = Focus /\ Pre.pre_candidate_active
                                         THEN JsonSet(Pre.pre_grants) ELSE {}]
    \* History bit only (not observable in the engine).
    /\ preRoundFromLeader = [i \in Server |-> FALSE]

(***************************************************************************
 * Field comparison shared by pre- and post-state checks. Arguments are the *
 * (primed or unprimed) model variables.                                    *
 *************************************************************************)
StateMatches(s, i, r, v, ll, cc, cci, ec, eci, lv, ca, cv, ccfg, gr, la,
             vpp, svp, lfp, sgl, cr, pca, pcv, pcc, pg) ==
    /\ r[i] = s.role
    /\ v[i] = SnapshotVote(s.vote)
    /\ ll[i] = SnapshotLog(s.last_log)
    /\ cc[i] = JsonConfig(s.committed_config)
    /\ cci[i] = s.committed_config_index
    /\ ec[i] = JsonConfig(s.effective_config)
    /\ eci[i] = s.effective_config_index
    /\ lv[i] = s.lease_valid
    /\ ca[i] = s.candidate_active
    /\ (s.candidate_active => cv[i] = SnapshotVote(s.candidate_vote))
    /\ (s.candidate_active => ccfg[i] = JsonConfig(s.candidate_config))
    /\ (s.candidate_active => gr[i] = JsonSet(s.grants))
    /\ la[i] = s.leader_active
    /\ vpp[i] = s.save_vote_pending
    /\ svp[i] = s.send_vote_pending
    /\ lfp[i] = s.append_pending
    /\ sgl[i] = s.seen_greater_log
    /\ cr[i] = s.crashed
    /\ pca[i] = s.pre_candidate_active
    /\ (s.pre_candidate_active => pcv[i] = SnapshotVote(s.pre_candidate_vote))
    /\ (s.pre_candidate_active => pcc[i] = JsonConfig(s.pre_candidate_config))
    /\ (s.pre_candidate_active => pg[i] = JsonSet(s.pre_grants))

ValidatePre(s, i) ==
    StateMatches(s, i, role, vote, lastLog, committedConfig, committedConfigIndex,
                 effectiveConfig, effectiveConfigIndex, leaseValid, candidateActive,
                 candidateVote, candidateConfig, grants, leaderActive,
                 votePersistPending, sendVotePending, logFlushPending,
                 seenGreaterLog, crashed, preCandidateActive, preCandidateVote,
                 preCandidateConfig, preGrants)

\* New Pre-Vote requests sent by this event, compared with send_pre_vote_pending.
NewPreVoteRequests(i) == {m \in messages' \ messages : m.kind = "PreVoteReq" /\ m.source = i}

ValidatePost(s, i) ==
    /\ StateMatches(s, i, role', vote', lastLog', committedConfig', committedConfigIndex',
                    effectiveConfig', effectiveConfigIndex', leaseValid', candidateActive',
                    candidateVote', candidateConfig', grants', leaderActive',
                    votePersistPending', sendVotePending', logFlushPending',
                    seenGreaterLog', crashed', preCandidateActive', preCandidateVote',
                    preCandidateConfig', preGrants')
    /\ s.send_pre_vote_pending = (NewPreVoteRequests(i) /= {})

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

\* UPDATE-MAP
\* code: openraft/src/engine/engine_impl.rs:298-322 (pre_elect); core/raft_core.rs:2010-2036
\* update: Update!AffectedActions (MCTickPreVote, MCExternalPreElect)
\* The emitted SendPreVote request must reach every other voter of the frozen
\* membership with the captured vote and last-log id.
TraceStartPreVote(e) ==
    /\ IF e.args.trigger = "tick" THEN TickPreVote(e.nid) ELSE ExternalPreElect(e.nid)
    /\ ValidatePost(e.post, e.nid)
    /\ e.post.send_pre_vote_pending =>
          /\ \A j \in ConfigVoters(preCandidateConfig'[e.nid]) \ {e.nid} :
                MessageR("PreVoteReq", e.nid, j, SnapshotVote(e.args.req_vote),
                         SnapshotLog(e.args.req_last_log), FALSE, FALSE,
                         SnapshotVote(e.args.req_vote)) \in messages'
          /\ \A m \in NewPreVoteRequests(e.nid) :
                m.dest \in ConfigVoters(preCandidateConfig'[e.nid]) \ {e.nid}

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
\* code: openraft/src/engine/engine_impl.rs:406-447 (handle_pre_vote_req)
\* update: Update!PreVoteRequestIsPure
TraceHandlePreVoteRequest(e) ==
    LET req == MessageR("PreVoteReq", e.args.source, e.nid,
                        SnapshotVote(e.args.vote), SnapshotLog(e.args.last_log),
                        FALSE, FALSE, SnapshotVote(e.args.vote))
    IN /\ HandlePreVoteRequest(e.nid, req, FALSE)
       /\ ValidatePost(e.post, e.nid)
       /\ MessageR("PreVoteResp", e.nid, e.args.source,
                   SnapshotVote(e.args.response_vote), SnapshotLog(e.args.response_last_log),
                   e.args.response_granted, FALSE, SnapshotVote(e.args.vote)) \in messages'

\* UPDATE-MAP
\* code: openraft/src/engine/engine_impl.rs:512-554 (handle_pre_vote_resp)
\* update: Update!PreVoteRoundNotOutlivedByOwnLeadership, Update!PreVoteElectionAtProbedVote
TraceHandlePreVoteResponse(e) ==
    LET resp == MessageR("PreVoteResp", e.args.source, e.nid,
                         SnapshotVote(e.args.vote), SnapshotLog(e.args.last_log),
                         e.args.granted, FALSE, SnapshotVote(e.args.candidate_vote))
    IN /\ HandlePreVoteResponse(e.nid, resp, FALSE)
       /\ ValidatePost(e.post, e.nid)

\* Engine::append_entries with an empty segment (heartbeat contact).
\* code: openraft/src/engine/engine_impl.rs:586-600; vote_handler/mod.rs:106-162,234-249
TraceHandleAppendEntries(e) ==
    LET req == Message("Append", e.args.source, e.nid,
                       SnapshotVote(e.args.vote), SnapshotLog(e.args.prev_log),
                       FALSE, FALSE)
    IN /\ HandleAppendEntries(e.nid, req, FALSE)
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
       IN /\ ValidatePre(e.pre, e.nid)
          /\ CASE e.name = "StartElection"       -> TraceStartElection(e)
               [] e.name = "StartPreVote"        -> TraceStartPreVote(e)
               [] e.name = "HandleVoteRequest"   -> TraceHandleVoteRequest(e)
               [] e.name = "HandleVoteResponse"  -> TraceHandleVoteResponse(e)
               [] e.name = "HandlePreVoteRequest" -> TraceHandlePreVoteRequest(e)
               [] e.name = "HandlePreVoteResponse" -> TraceHandlePreVoteResponse(e)
               [] e.name = "HandleAppendEntries" -> TraceHandleAppendEntries(e)
               [] e.name = "AppendJointConfig"   -> TraceAppendJointConfig(e)
               [] e.name = "CommitMembership"    -> TraceCommitMembership(e)
               [] e.name = "Restart"             -> TraceRestart(e)
               [] OTHER                          -> FALSE
    /\ cursor' = cursor + 1

(***************************************************************************
 * Silent runtime steps between two events (RaftCore::run_command for       *
 * SaveVote, SendVote, and the log flush callback; raft_core.rs:2262-2304,  *
 * 2339-2341). Each is enabled only while the corresponding pending flag   *
 * is set in the model and cleared in the next event's captured pre-state. *
 *************************************************************************)
NextPre == TraceLog[cursor].pre

SilentPersistVote ==
    /\ cursor \in 2..Len(TraceLog)
    /\ votePersistPending[Focus]
    /\ ~NextPre.save_vote_pending
    /\ PersistVote(Focus)
    /\ UNCHANGED cursor

SilentSendVote ==
    /\ cursor \in 2..Len(TraceLog)
    /\ sendVotePending[Focus]
    /\ ~NextPre.send_vote_pending
    /\ \/ \E j \in Server : SendVoteRequest(Focus, j)
       \/ FinishVoteBroadcast(Focus)
    /\ UNCHANGED cursor

SilentFlushLog ==
    /\ cursor \in 2..Len(TraceLog)
    /\ logFlushPending[Focus]
    /\ ~NextPre.append_pending
    /\ FlushLog(Focus)
    /\ UNCHANGED cursor

SilentStep == SilentPersistVote \/ SilentSendVote \/ SilentFlushLog

TraceDone ==
    /\ cursor = Len(TraceLog) + 1
    /\ UNCHANGED traceVars

TraceNext == TraceStep \/ SilentStep \/ TraceDone

TraceSpec == TraceInit /\ [][TraceNext]_traceVars /\ WF_traceVars(TraceStep \/ SilentStep)
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
