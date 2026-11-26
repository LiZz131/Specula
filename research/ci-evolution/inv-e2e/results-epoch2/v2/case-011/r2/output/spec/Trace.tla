------------------------------ MODULE Trace ------------------------------
(***************************************************************************
 * Trace validation for the updated (pre-vote) reference.                  *
 *                                                                         *
 * Each NDJSON file holds one or more Engine transitions of a single focus *
 * node, captured around real Engine entry points by the test-only harness *
 * (harness/instrumentation.patch).  Every event carries the captured      *
 * pre-state and post-state.  Between events the harness drains queued     *
 * commands, standing in for RaftCore executing them; the corresponding    *
 * runtime completions (PersistVote, SendVoteRequest/FinishVoteBroadcast,  *
 * FlushLog) are matched by narrowly guarded silent steps that are enabled *
 * only when the NEXT event's captured pre-state shows the command gone.   *
 * Every event's pre-state is compared with the model state before its     *
 * action (ValidatePre), so a missing or extra silent step is rejected.    *
 *************************************************************************)
EXTENDS base, Json, IOUtils

TraceFile ==
    IF "SPECULAR_TRACE" \in DOMAIN IOEnv THEN IOEnv.SPECULAR_TRACE
    ELSE IF "JSON" \in DOMAIN IOEnv THEN IOEnv.JSON
    ELSE "../traces/start_election.ndjson"

TraceRecords == ndJsonDeserialize(TraceFile)
TraceLog == [k \in 1..Len(TraceRecords) |-> TraceRecords[k].event]

ASSUME Len(TraceLog) > 0
ASSUME \A k \in 1..Len(TraceLog) : TraceLog[k].nid = TraceLog[1].nid

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
    /\ preCandidateActive = [i \in Server |-> i = Focus /\ Pre.pre_candidate_active]
    /\ preCandidateVote = [i \in Server |-> IF i = Focus /\ Pre.pre_candidate_active
                                                THEN SnapshotVote(Pre.pre_candidate_vote)
                                                ELSE DefaultVote(i)]
    /\ preCandidateConfig = [i \in Server |-> IF i = Focus /\ Pre.pre_candidate_active
                                                  THEN JsonConfig(Pre.pre_candidate_config)
                                                  ELSE <<InitialConfig>>]
    /\ preGrants = [i \in Server |-> IF i = Focus /\ Pre.pre_candidate_active
                                         THEN JsonSet(Pre.pre_grants) ELSE {}]

\* Pre-vote requests issued by the focus node for its active round, as captured
\* from the queued Command::SendPreVote (core/raft_core.rs:2342-2344).
PreVoteRequestsIssued(s, i) ==
    \A j \in ConfigVoters(preCandidateConfig'[i]) \ {i} :
        \E m \in messages' :
            /\ m.kind = "PreVoteReq"
            /\ m.source = i
            /\ m.dest = j
            /\ m.vote = SnapshotVote(s.send_pre_vote_req.vote)
            /\ m.lastLog = SnapshotLog(s.send_pre_vote_req.last_log)

\* Field-by-field comparison of a captured snapshot with model state.
\* `St(x)` selects either the current (pre) or next (post) value of a variable.
StateMatches(s, i, r, v, ll, cc, cci, ec, eci, lv, ca, cv, ccfg, gr, la, svp, sdp, ap, sgl, cr,
             pca, pcv, pcc, pgr) ==
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
    /\ svp[i] = s.save_vote_pending
    /\ sdp[i] = s.send_vote_pending
    /\ ap[i] = s.append_pending
    /\ sgl[i] = s.seen_greater_log
    /\ cr[i] = s.crashed
    /\ pca[i] = s.pre_candidate_active
    /\ (s.pre_candidate_active => pcv[i] = SnapshotVote(s.pre_candidate_vote))
    /\ (s.pre_candidate_active => pcc[i] = JsonConfig(s.pre_candidate_config))
    /\ (s.pre_candidate_active => pgr[i] = JsonSet(s.pre_grants))

ValidatePre(s, i) ==
    StateMatches(s, i, role, vote, lastLog, committedConfig, committedConfigIndex,
                 effectiveConfig, effectiveConfigIndex, leaseValid, candidateActive,
                 candidateVote, candidateConfig, grants, leaderActive, votePersistPending,
                 sendVotePending, logFlushPending, seenGreaterLog, crashed,
                 preCandidateActive, preCandidateVote, preCandidateConfig, preGrants)

ValidatePost(s, i) ==
    /\ StateMatches(s, i, role', vote', lastLog', committedConfig', committedConfigIndex',
                    effectiveConfig', effectiveConfigIndex', leaseValid', candidateActive',
                    candidateVote', candidateConfig', grants', leaderActive', votePersistPending',
                    sendVotePending', logFlushPending', seenGreaterLog', crashed',
                    preCandidateActive', preCandidateVote', preCandidateConfig', preGrants')
    \* A queued SendPreVote is exactly the creation of a round with its requests.
    /\ (s.send_pre_vote_pending => PreVoteRequestsIssued(s, i))

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

PreVoteResponseMatches(e, i) ==
    \E m \in messages' :
        /\ m.kind = "PreVoteResp"
        /\ m.source = i
        /\ m.dest = e.args.source
        /\ m.vote = SnapshotVote(e.args.response_vote)
        /\ m.lastLog = SnapshotLog(e.args.response_last_log)
        /\ m.granted = e.args.response_granted
        /\ m.reqVote = SnapshotVote(e.args.vote)

Caller(e) == IF "caller" \in DOMAIN e.args THEN e.args.caller ELSE "external"

TraceStartElection(e) ==
    /\ IF Caller(e) = "tick" THEN TickElect(e.nid)
       ELSE IF e.args.transfer THEN StartTransferElection(e.nid)
       ELSE ExternalElect(e.nid)
    /\ ValidatePost(e.post, e.nid)

\* UPDATE-MAP
\* code: openraft/src/engine/engine_impl.rs:297-322; core/raft_core.rs:2027-2031 (tick caller)
\* update: Update!AffectedActions (MCTickPreElect, MCExternalPreElect)
TracePreElect(e) ==
    /\ IF Caller(e) = "tick" THEN TickPreElect(e.nid) ELSE ExternalPreElect(e.nid)
    /\ ValidatePost(e.post, e.nid)
    /\ e.post.send_pre_vote_pending = preCandidateActive'[e.nid]

TraceHandleVoteRequest(e) ==
    LET req == Message("VoteReq", e.args.source, e.nid,
                       SnapshotVote(e.args.vote), SnapshotLog(e.args.last_log),
                       FALSE, e.args.transfer)
    IN /\ HandleVoteRequest(e.nid, req, FALSE)
       /\ ValidatePost(e.post, e.nid)
       /\ ResponseMatches(e, e.nid)

TraceHandlePreVoteRequest(e) ==
    LET req == PreVoteMessage("PreVoteReq", e.args.source, e.nid,
                              SnapshotVote(e.args.vote), SnapshotLog(e.args.last_log),
                              FALSE, SnapshotVote(e.args.vote))
    IN /\ HandlePreVoteRequest(e.nid, req, FALSE)
       /\ ValidatePost(e.post, e.nid)
       /\ PreVoteResponseMatches(e, e.nid)

TraceHandleVoteResponse(e) ==
    LET resp == Message("VoteResp", e.args.source, e.nid,
                        SnapshotVote(e.args.vote), SnapshotLog(e.args.last_log),
                        e.args.granted, FALSE)
    IN /\ HandleVoteResponse(e.nid, resp, FALSE)
       /\ ValidatePost(e.post, e.nid)

TraceHandlePreVoteResponse(e) ==
    LET resp == PreVoteMessage("PreVoteResp", e.args.source, e.nid,
                               SnapshotVote(e.args.vote), SnapshotLog(e.args.last_log),
                               e.args.granted, SnapshotVote(e.args.req_vote))
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
       IN /\ ValidatePre(e.pre, e.nid)
          /\ CASE e.name = "StartElection"         -> TraceStartElection(e)
               [] e.name = "PreElect"              -> TracePreElect(e)
               [] e.name = "HandleVoteRequest"     -> TraceHandleVoteRequest(e)
               [] e.name = "HandlePreVoteRequest"  -> TraceHandlePreVoteRequest(e)
               [] e.name = "HandleVoteResponse"    -> TraceHandleVoteResponse(e)
               [] e.name = "HandlePreVoteResponse" -> TraceHandlePreVoteResponse(e)
               [] e.name = "AppendJointConfig"     -> TraceAppendJointConfig(e)
               [] e.name = "CommitMembership"      -> TraceCommitMembership(e)
               [] e.name = "Restart"               -> TraceRestart(e)
               [] OTHER                             -> FALSE
    /\ cursor' = cursor + 1

(***************************************************************************
 * Silent runtime completions between captured events.  Each is enabled     *
 * only on the focus node, only while an unconsumed event remains, and only *
 * when that event's captured pre-state shows the corresponding queued      *
 * command already executed.                                                *
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
    /\ ~votePersistPending[Focus]
    /\ \/ \E j \in Server : SendVoteRequest(Focus, j)
       \/ FinishVoteBroadcast(Focus)
    /\ UNCHANGED cursor

SilentFlushLog ==
    /\ cursor \in 2..Len(TraceLog)
    /\ logFlushPending[Focus]
    /\ ~NextPre.append_pending
    /\ FlushLog(Focus)
    /\ UNCHANGED cursor

TraceDone ==
    /\ cursor = Len(TraceLog) + 1
    /\ UNCHANGED traceVars

TraceNext == TraceStep \/ SilentPersistVote \/ SilentSendVote \/ SilentFlushLog \/ TraceDone

\* Fairness covers the silent completions too: TraceStep is enabled only after
\* the silent steps required by the next event's pre-state have been taken.
TraceSpec == TraceInit /\ [][TraceNext]_traceVars
             /\ WF_traceVars(TraceStep \/ SilentPersistVote \/ SilentSendVote \/ SilentFlushLog)
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
