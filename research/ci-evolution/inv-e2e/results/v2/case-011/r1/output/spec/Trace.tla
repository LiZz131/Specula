------------------------------ MODULE Trace ------------------------------
EXTENDS base, Json, IOUtils

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
    /\ \A k \in 1..Len(TraceLog) : TraceLog[k].nid = Focus
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
    \* update: Update!PreVoteVisibleState
    /\ preCandidateActive = [i \in Server |-> i = Focus /\ Pre.pre_candidate_active]
    /\ preCandidateVote = [i \in Server |-> IF i = Focus /\ Pre.pre_candidate_active
                                                THEN SnapshotVote(Pre.pre_candidate_vote)
                                                ELSE DefaultVote(i)]
    /\ preCandidateConfig = [i \in Server |-> IF i = Focus /\ Pre.pre_candidate_active
                                                  THEN JsonConfig(Pre.pre_candidate_config)
                                                  ELSE <<InitialConfig>>]
    /\ preGrants = [i \in Server |-> IF i = Focus /\ Pre.pre_candidate_active
                                         THEN JsonSet(Pre.pre_grants) ELSE {}]
    /\ preCandidateByTimer = [i \in Server |-> FALSE]
    /\ preRound = [i \in Server |-> 0]

(***************************************************************************
 * Field comparison shared by the pre-state check (unprimed) and the        *
 * post-state check (primed).                                               *
 *************************************************************************)
StateMatches(s, i, r, v, ll, cc, cci, ec, eci, lv, ca, cv, ccfg, gr, la, svp, sndp, ap,
             sgl, cr, pca, pcv, pcc, pg) ==
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
    /\ sndp[i] = s.send_vote_pending
    /\ ap[i] = s.append_pending
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
                 votePersistPending, sendVotePending, logFlushPending, seenGreaterLog,
                 crashed, preCandidateActive, preCandidateVote, preCandidateConfig, preGrants)

ValidatePost(s, i) ==
    StateMatches(s, i, role', vote', lastLog', committedConfig', committedConfigIndex',
                 effectiveConfig', effectiveConfigIndex', leaseValid', candidateActive',
                 candidateVote', candidateConfig', grants', leaderActive',
                 votePersistPending', sendVotePending', logFlushPending', seenGreaterLog',
                 crashed', preCandidateActive', preCandidateVote', preCandidateConfig',
                 preGrants')

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
    /\ StartElection(e.nid, e.args.transfer, FALSE)
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

TraceAppendJointConfig(e) ==
    /\ AppendJointConfig(e.nid, JsonSet(e.args.target_config))
    /\ ValidatePost(e.post, e.nid)

TraceCommitMembership(e) ==
    /\ CommitMembership(e.nid)
    /\ ValidatePost(e.post, e.nid)

TraceRestart(e) ==
    /\ Restart(e.nid)
    /\ ValidatePost(e.post, e.nid)

\* Engine::append_entries with an empty segment at the local last log: the
\* vote update / become_following transition (engine_impl.rs:586-600).
TraceHandleAppendEntries(e) ==
    LET m == Message("Append", e.args.source, e.nid, SnapshotVote(e.args.vote),
                     SnapshotLog(e.args.prev_log), FALSE, FALSE)
    IN /\ e.args.accepted
       /\ HandleAppendEntries(e.nid, m, FALSE)
       /\ ValidatePost(e.post, e.nid)

(***************************************************************************
 * Pre-Vote wrappers.                                                       *
 * UPDATE-MAP                                                               *
 * code: openraft/src/engine/engine_impl.rs:297-322,414-447,516-554          *
 * update: Update!PreElectAction, Update!HandlePreVoteRequestAction,         *
 *         Update!HandlePreVoteResponseAction                                *
 *************************************************************************)
\* Inbound Pre-Vote messages are sent by untraced peers. TraceInjectInbound puts
\* the message in flight immediately before the event that consumes it, so the
\* replayed step consumes it from `messages` exactly as DeliverPreVote* does.
InboundMessage(e) ==
    IF e.name = "HandlePreVoteRequest"
    THEN PreVoteMessage("PreVoteReq", e.args.source, e.nid,
                        SnapshotVote(e.args.vote), SnapshotLog(e.args.last_log), FALSE, 0)
    ELSE PreVoteMessage("PreVoteResp", e.args.source, e.nid,
                        SnapshotVote(e.args.candidate_vote), SnapshotLog(e.args.last_log),
                        e.args.granted, preRound[e.nid])

NewPreVoteReqs(i) == {m \in messages' \ messages : m.kind = "PreVoteReq" /\ m.source = i}

\* by_timer = true replays the timer's reset_greater_log(); pre_elect() sequence
\* (raft_core.rs:2027-2031); by_timer = false replays ExternalCommand::Elect
\* { pre_vote: true } (raft_core.rs:1683-1696). send_pre_vote_req is the queued
\* SendPreVote command; every emitted request must carry its vote and last log.
TracePreElect(e) ==
    LET i == e.nid IN
    /\ IF e.args.by_timer THEN TickPreElect(i) ELSE ExternalPreElect(i)
    /\ ValidatePost(e.post, i)
    /\ (e.post.send_pre_vote_pending = (NewPreVoteReqs(i) /= {}))
    /\ e.post.send_pre_vote_pending =>
          \A m \in NewPreVoteReqs(i) :
              /\ m.vote = SnapshotVote(e.args.send_pre_vote_req.vote)
              /\ m.lastLog = SnapshotLog(e.args.send_pre_vote_req.last_log)

\* The engine's response carries the responder's own (unchanged) vote and
\* last log; the RaftCore responds at once (raft_core.rs:1551-1562).
TraceHandlePreVoteRequest(e) ==
    LET i == e.nid
        req == InboundMessage(e)
    IN /\ req \in messages
       /\ HandlePreVoteRequest(i, req, TRUE)
       /\ ValidatePost(e.post, i)
       /\ SnapshotVote(e.args.response_vote) = vote'[i]
       /\ SnapshotLog(e.args.response_last_log) = lastLog'[i]
       /\ e.args.commands_emitted = 0
       /\ \E m \in messages' \ messages :
              /\ m.kind = "PreVoteResp" /\ m.source = i /\ m.dest = e.args.source
              /\ m.granted = e.args.response_granted
              /\ m.lastLog = SnapshotLog(e.args.response_last_log)

\* The harness only delivers a response after the RaftCore correlation check
\* (raft_core.rs:1815-1816) would pass; candidate_vote is the probed vote
\* carried by Notification::PreVoteResponse.
TraceHandlePreVoteResponse(e) ==
    LET i == e.nid
        resp == InboundMessage(e)
    IN /\ resp \in messages
       /\ HandlePreVoteResponse(i, resp, TRUE)
       /\ ValidatePost(e.post, i)

(***************************************************************************
 * Runtime command completion between two engine events of a multi-event   *
 * trace. Enabled only when the next event's recorded pre-state shows the  *
 * corresponding queued command as no longer pending.                      *
 * openraft/src/core/raft_core.rs:1110-1160 (command drain)                 *
 *************************************************************************)
NextPre == TraceLog[cursor].pre

TraceRuntimeDrain ==
    /\ cursor \in 2..Len(TraceLog)
    /\ LET i == TraceLog[cursor].nid IN
       \/ /\ votePersistPending[i] /\ ~NextPre.save_vote_pending
          /\ PersistVote(i)
       \/ /\ logFlushPending[i] /\ ~NextPre.append_pending
          /\ FlushLog(i)
       \/ \* real time passes between events: a lease the next event no longer sees
          /\ leaseValid[i] /\ ~NextPre.lease_valid
          /\ ExpireLease(i)
       \/ /\ sendVotePending[i] /\ ~NextPre.send_vote_pending
          /\ ~votePersistPending[i]
          /\ \/ \E j \in Server : SendVoteRequest(i, j)
             \/ FinishVoteBroadcast(i)
    /\ UNCHANGED cursor

TraceInjectInbound ==
    /\ cursor \in 1..Len(TraceLog)
    /\ TraceLog[cursor].name \in {"HandlePreVoteRequest", "HandlePreVoteResponse"}
    /\ InboundMessage(TraceLog[cursor]) \notin messages
    /\ messages' = messages \cup {InboundMessage(TraceLog[cursor])}
    /\ UNCHANGED <<runtimeVars, voteVars, candidateVars, leaderVars, logVars, configVars,
                    preVoteVars, cursor>>

TraceStep ==
    /\ cursor \in 1..Len(TraceLog)
    /\ LET e == TraceLog[cursor]
       IN /\ ValidatePre(e.pre, e.nid)
          /\ CASE e.name = "StartElection"       -> TraceStartElection(e)
               [] e.name = "HandleVoteRequest"  -> TraceHandleVoteRequest(e)
               [] e.name = "HandleVoteResponse" -> TraceHandleVoteResponse(e)
               [] e.name = "AppendJointConfig"  -> TraceAppendJointConfig(e)
               [] e.name = "CommitMembership"   -> TraceCommitMembership(e)
               [] e.name = "Restart"            -> TraceRestart(e)
               [] e.name = "HandleAppendEntries" -> TraceHandleAppendEntries(e)
               [] e.name = "PreElect"           -> TracePreElect(e)
               [] e.name = "HandlePreVoteRequest"  -> TraceHandlePreVoteRequest(e)
               [] e.name = "HandlePreVoteResponse" -> TraceHandlePreVoteResponse(e)
               [] OTHER                          -> FALSE
    /\ cursor' = cursor + 1

TraceDone ==
    /\ cursor = Len(TraceLog) + 1
    /\ UNCHANGED traceVars

TraceNext == TraceStep \/ TraceRuntimeDrain \/ TraceInjectInbound \/ TraceDone

TraceSpec == TraceInit /\ [][TraceNext]_traceVars /\ WF_traceVars(TraceStep \/ TraceRuntimeDrain \/ TraceInjectInbound)
\* REQ-EVIDENCE TraceConsumed
\* intent:   every event of the recorded implementation trace is eventually matched by a model step.
\* status:   model-internal
\* watch:    none
\* verified: update (pre-vote revision)
\* review:   ok
TraceConsumed == <>(cursor = Len(TraceLog) + 1)
\* REQ-EVIDENCE TraceTypeOK
\* intent:   TypeOK holds and the trace cursor stays within the bounds of the recorded trace.
\* status:   model-internal
\* watch:    none
\* verified: update (pre-vote revision)
\* review:   ok
TraceTypeOK == TypeOK /\ cursor \in 1..(Len(TraceLog) + 1)
TraceView == <<vars, cursor>>

=============================================================================
