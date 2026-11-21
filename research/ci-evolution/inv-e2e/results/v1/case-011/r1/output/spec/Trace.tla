------------------------------ MODULE Trace ------------------------------
(***************************************************************************
 * Linear (Category A) trace validation for the updated reference.          *
 *                                                                          *
 * Each NDJSON record captures one real Engine invocation of a single focus *
 * node with its pre- and post-state.  A trace may contain several engine  *
 * events of the same node (update interaction scenarios).  Between two     *
 * events the harness drains the engine's command queue the way RaftCore    *
 * would; the corresponding runtime completions (PersistVote, FlushLog,     *
 * vote/pre-vote dispatch, lease expiry) are replayed as tightly guarded    *
 * silent steps that may only move the model toward the next recorded      *
 * pre-state.  Every recorded event is checked against its pre-state and    *
 * its post-state.                                                          *
 *************************************************************************)
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
    \* UPDATE-MAP: pre-candidate fixture state (engine_impl.rs:95-101)
    \* update: Update!PreVoteState
    /\ preCandidateActive = [i \in Server |-> i = Focus /\ Pre.pre_candidate_active]
    /\ preCandidateVote = [i \in Server |-> IF i = Focus /\ Pre.pre_candidate_active
                                                THEN SnapshotVote(Pre.pre_candidate_vote)
                                                ELSE DefaultVote(i)]
    /\ preCandidateLastLog = [i \in Server |-> IF i = Focus /\ Pre.pre_candidate_active
                                                   THEN SnapshotLog(Pre.pre_candidate_last_log)
                                                   ELSE NoLog(i)]
    /\ preCandidateConfig = [i \in Server |-> IF i = Focus /\ Pre.pre_candidate_active
                                                  THEN JsonConfig(Pre.pre_candidate_config)
                                                  ELSE <<InitialConfig>>]
    /\ preGrants = [i \in Server |-> IF i = Focus /\ Pre.pre_candidate_active
                                         THEN JsonSet(Pre.pre_grants) ELSE {}]
    /\ sendPreVotePending = [i \in Server |-> i = Focus /\ Pre.send_pre_vote_pending]
    /\ preSentReq = [i \in Server |-> {}]
    /\ preStartRole = [i \in Server |-> IF i = Focus /\ Pre.pre_candidate_active
                                            THEN Pre.role ELSE "None"]

(***************************************************************************
 * State comparison shared by pre- and post-state checks.  `V` selects the  *
 * current (unprimed) or next (primed) value via the two wrappers below.     *
 *************************************************************************)
MatchesState(s, i, r, v, ll, cc, cci, ec, eci, lv, ca, cv, ccfg, g, la, svp, sdp,
              ap, sgl, cr, pca, pcv, pcll, pcc, pg, sppp) ==
    /\ r = s.role
    /\ v = SnapshotVote(s.vote)
    /\ ll = SnapshotLog(s.last_log)
    /\ cc = JsonConfig(s.committed_config)
    /\ cci = s.committed_config_index
    /\ ec = JsonConfig(s.effective_config)
    /\ eci = s.effective_config_index
    /\ lv = s.lease_valid
    /\ ca = s.candidate_active
    /\ (s.candidate_active => cv = SnapshotVote(s.candidate_vote))
    /\ (s.candidate_active => ccfg = JsonConfig(s.candidate_config))
    /\ (s.candidate_active => g = JsonSet(s.grants))
    /\ la = s.leader_active
    /\ svp = s.save_vote_pending
    /\ sdp = s.send_vote_pending
    /\ ap = s.append_pending
    /\ sgl = s.seen_greater_log
    /\ cr = s.crashed
    \* UPDATE-MAP: pre-candidate observation (engine_impl.rs:340-342)
    \* update: Update!PreVoteState
    /\ pca = s.pre_candidate_active
    /\ (s.pre_candidate_active => pcv = SnapshotVote(s.pre_candidate_vote))
    /\ (s.pre_candidate_active => pcll = SnapshotLog(s.pre_candidate_last_log))
    /\ (s.pre_candidate_active => pcc = JsonConfig(s.pre_candidate_config))
    /\ (s.pre_candidate_active => pg = JsonSet(s.pre_grants))
    /\ sppp = s.send_pre_vote_pending

ValidatePre(s, i) ==
    MatchesState(s, i, role[i], vote[i], lastLog[i], committedConfig[i],
                 committedConfigIndex[i], effectiveConfig[i], effectiveConfigIndex[i],
                 leaseValid[i], candidateActive[i], candidateVote[i],
                 candidateConfig[i], grants[i], leaderActive[i],
                 votePersistPending[i], sendVotePending[i], logFlushPending[i],
                 seenGreaterLog[i], crashed[i], preCandidateActive[i],
                 preCandidateVote[i], preCandidateLastLog[i],
                 preCandidateConfig[i], preGrants[i], sendPreVotePending[i])

ValidatePost(s, i) ==
    MatchesState(s, i, role'[i], vote'[i], lastLog'[i], committedConfig'[i],
                 committedConfigIndex'[i], effectiveConfig'[i], effectiveConfigIndex'[i],
                 leaseValid'[i], candidateActive'[i], candidateVote'[i],
                 candidateConfig'[i], grants'[i], leaderActive'[i],
                 votePersistPending'[i], sendVotePending'[i], logFlushPending'[i],
                 seenGreaterLog'[i], crashed'[i], preCandidateActive'[i],
                 preCandidateVote'[i], preCandidateLastLog'[i],
                 preCandidateConfig'[i], preGrants'[i], sendPreVotePending'[i])

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

\* UPDATE-MAP
\* code: engine/engine_impl.rs:414-447 (response = local vote, local last log, granted)
\* update: Update!PreVoteRequestPure
PreVoteResponseMatches(e, i) ==
    /\ SnapshotVote(e.args.response_vote) = vote[i]
    /\ SnapshotLog(e.args.response_last_log) = lastLog[i]
    /\ \E m \in messages' :
          /\ m.kind = "PreVoteResp"
          /\ m.source = i
          /\ m.dest = e.args.source
          /\ m.vote = SnapshotVote(e.args.vote)
          /\ m.lastLog = lastLog[i]
          /\ m.granted = e.args.response_granted

TraceStartElection(e) ==
    /\ StartElection(e.nid, e.args.transfer, FALSE)

TraceHandleVoteRequest(e) ==
    LET req == Message("VoteReq", e.args.source, e.nid,
                       SnapshotVote(e.args.vote), SnapshotLog(e.args.last_log),
                       FALSE, e.args.transfer)
    IN /\ HandleVoteRequest(e.nid, req, FALSE)
       /\ ResponseMatches(e, e.nid)

TraceHandleVoteResponse(e) ==
    LET resp == Message("VoteResp", e.args.source, e.nid,
                        SnapshotVote(e.args.vote), SnapshotLog(e.args.last_log),
                        e.args.granted, FALSE)
    IN HandleVoteResponse(e.nid, resp, FALSE)

TraceAppendJointConfig(e) ==
    AppendJointConfig(e.nid, JsonSet(e.args.target_config))

TraceCommitMembership(e) == CommitMembership(e.nid)

TraceRestart(e) == Restart(e.nid)

\* UPDATE-MAP
\* code: engine/engine_impl.rs:298-322
\* update: Update!AffectedActions (PreElect)
TracePreElect(e) == PreElect(e.nid, FALSE)

\* UPDATE-MAP
\* code: engine/engine_impl.rs:414-447
\* update: Update!AffectedActions (HandlePreVoteRequest)
TraceHandlePreVoteRequest(e) ==
    LET req == Message("PreVoteReq", e.args.source, e.nid,
                       SnapshotVote(e.args.vote), SnapshotLog(e.args.last_log),
                       FALSE, FALSE)
    IN /\ HandlePreVoteRequest(e.nid, req, FALSE)
       /\ PreVoteResponseMatches(e, e.nid)

\* UPDATE-MAP
\* code: core/raft_core.rs:1803-1820 + engine/engine_impl.rs:516-554
\* update: Update!AffectedActions (HandlePreVoteResponse)
TraceHandlePreVoteResponse(e) ==
    LET resp == Message("PreVoteResp", e.args.source, e.nid,
                        SnapshotVote(e.args.candidate_vote), SnapshotLog(e.args.last_log),
                        e.args.granted, FALSE)
    IN HandlePreVoteResponse(e.nid, resp, FALSE)

\* UPDATE-MAP
\* code: engine/engine_impl.rs:586-600 (append_entries -> update_vote)
\* update: Update!InteractionActions (HandleAppendEntries)
TraceHandleAppendEntries(e) ==
    LET req == Message("Append", e.args.source, e.nid,
                       SnapshotVote(e.args.vote), SnapshotLog(e.args.prev_log),
                       FALSE, FALSE)
    IN HandleAppendEntries(e.nid, req, FALSE)

TraceStep ==
    /\ cursor \in 1..Len(TraceLog)
    /\ LET e == TraceLog[cursor]
       IN /\ ValidatePre(e.pre, e.nid)
          /\ CASE e.name = "StartElection"         -> TraceStartElection(e)
               [] e.name = "HandleVoteRequest"     -> TraceHandleVoteRequest(e)
               [] e.name = "HandleVoteResponse"    -> TraceHandleVoteResponse(e)
               [] e.name = "AppendJointConfig"     -> TraceAppendJointConfig(e)
               [] e.name = "CommitMembership"      -> TraceCommitMembership(e)
               [] e.name = "Restart"               -> TraceRestart(e)
               [] e.name = "PreElect"              -> TracePreElect(e)
               [] e.name = "HandlePreVoteRequest"  -> TraceHandlePreVoteRequest(e)
               [] e.name = "HandlePreVoteResponse" -> TraceHandlePreVoteResponse(e)
               [] e.name = "HandleAppendEntries"   -> TraceHandleAppendEntries(e)
               [] OTHER                            -> FALSE
          /\ ValidatePost(e.post, e.nid)
    /\ cursor' = cursor + 1

(***************************************************************************
 * Silent runtime completions between two recorded engine events.  Each is   *
 * enabled only while the next recorded pre-state shows the corresponding   *
 * command/lease as already completed, so they commute and cannot lead the  *
 * replay into a dead end.                                                  *
 *************************************************************************)
NextPre == TraceLog[cursor].pre

SilentRuntime ==
    /\ cursor \in 1..Len(TraceLog)
    /\ \/ /\ votePersistPending[Focus] /\ ~NextPre.save_vote_pending
          /\ PersistVote(Focus)
       \/ /\ logFlushPending[Focus] /\ ~NextPre.append_pending
          /\ FlushLog(Focus)
       \/ /\ sendVotePending[Focus] /\ ~NextPre.send_vote_pending
          /\ \/ \E j \in Server : SendVoteRequest(Focus, j)
             \/ FinishVoteBroadcast(Focus)
       \/ /\ sendPreVotePending[Focus] /\ ~NextPre.send_pre_vote_pending
          /\ \/ \E j \in Server : SendPreVoteRequest(Focus, j)
             \/ FinishPreVoteBroadcast(Focus)
       \/ /\ leaseValid[Focus] /\ ~NextPre.lease_valid
          /\ ExpireLease(Focus)
    /\ UNCHANGED cursor

TraceDone ==
    /\ cursor = Len(TraceLog) + 1
    /\ UNCHANGED traceVars

TraceNext == TraceStep \/ SilentRuntime \/ TraceDone

TraceSpec == TraceInit /\ [][TraceNext]_traceVars /\ WF_traceVars(TraceStep)
                       /\ WF_traceVars(SilentRuntime)
TraceConsumed == <>(cursor = Len(TraceLog) + 1)
TraceTypeOK == TypeOK /\ cursor \in 1..(Len(TraceLog) + 1)
TraceView == <<vars, cursor>>

=============================================================================
