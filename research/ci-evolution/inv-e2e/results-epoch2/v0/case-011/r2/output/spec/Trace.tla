------------------------------ MODULE Trace ------------------------------
(***************************************************************************
 * Trace validation for the Pre-Vote revision (rebased from the V0 prior). *
 * Each trace starts from the explicit pre-state of its first event on the *
 * focus node. Every later event's pre-state must equal the model state    *
 * (no re-synchronization), and every post-state field is compared.        *
 ***************************************************************************)
EXTENDS base, Json, IOUtils

TracePath == IF "SPECULAR_TRACE" \in DOMAIN IOEnv THEN IOEnv.SPECULAR_TRACE ELSE IOEnv.JSON
TraceRecords == ndJsonDeserialize(TracePath)
TraceLog == [k \in 1..Len(TraceRecords) |-> TraceRecords[k].event]

ASSUME Len(TraceLog) > 0

\* The harness records each event's pre-state immediately after the previous
\* event's post-state on the same engine; no unobserved mutation in between.
TraceContinuity ==
    \A k \in 2..Len(TraceLog) :
        /\ TraceLog[k].nid = TraceLog[k - 1].nid
        /\ TraceLog[k].pre = TraceLog[k - 1].post
ASSUME TraceContinuity

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
    /\ leaderVote = [i \in Server |-> IF i = Focus THEN SnapshotVote(Pre.leader_vote) ELSE DefaultVote(i)]
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
    \* UPDATE-MAP  code: engine_impl.rs:Engine::pre_candidate  update: Update!PreCandidateVars
    /\ preCandidateActive = [i \in Server |-> i = Focus /\ Pre.pre_candidate_active]
    /\ preCandidateVote = [i \in Server |-> IF i = Focus
                                                THEN SnapshotVote(Pre.pre_candidate_vote)
                                                ELSE DefaultVote(i)]
    /\ preCandidateConfig = [i \in Server |-> IF i = Focus
                                                  THEN JsonConfig(Pre.pre_candidate_config)
                                                  ELSE <<InitialConfig>>]
    /\ preGrants = [i \in Server |-> IF i = Focus THEN JsonSet(Pre.pre_grants) ELSE {}]

\* Pre-Vote requests that a queued SendPreVote dispatches (RaftCore sends to
\* effective voter_ids() minus self).
ExpectedPreVoteReqs(s, i) ==
    {PreVoteReqMsg(i, j, SnapshotVote(s.send_pre_vote_req.vote),
                   SnapshotLog(s.send_pre_vote_req.last_log)) :
        j \in ConfigVoters(JsonConfig(s.effective_config)) \ {i}}

NewPreVoteReqFrom(i) ==
    \E m \in messages' \ messages : m.kind = "PreVoteReq" /\ m.source = i

\* Compare an observed engine state (pre or post) with the model state given
\* as unprimed (St = "pre") or primed (St = "post") values.
StateMatches(s, i, r, v, ll, cc, cci, ec, eci, lv, ca, cv, cfg, g, la, ldv,
             vp, sp, ap, sgl, cr, pca, pcv, pcc, pg) ==
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
    /\ (s.candidate_active => cfg = JsonConfig(s.candidate_config))
    /\ (s.candidate_active => g = JsonSet(s.grants))
    /\ la = s.leader_active
    /\ (s.leader_active => ldv = SnapshotVote(s.leader_vote))
    /\ vp = s.save_vote_pending
    /\ sp = s.send_vote_pending
    /\ ap = s.append_pending
    /\ sgl = s.seen_greater_log
    /\ cr = s.crashed
    /\ pca = s.pre_candidate_active
    /\ (s.pre_candidate_active => pcv = SnapshotVote(s.pre_candidate_vote))
    /\ (s.pre_candidate_active => pcc = JsonConfig(s.pre_candidate_config))
    /\ (s.pre_candidate_active => pg = JsonSet(s.pre_grants))

ValidatePost(s, i) ==
    /\ StateMatches(s, i, role'[i], vote'[i], lastLog'[i], committedConfig'[i],
                    committedConfigIndex'[i], effectiveConfig'[i], effectiveConfigIndex'[i],
                    leaseValid'[i], candidateActive'[i], candidateVote'[i],
                    candidateConfig'[i], grants'[i], leaderActive'[i], leaderVote'[i],
                    votePersistPending'[i], sendVotePending'[i], logFlushPending'[i],
                    seenGreaterLog'[i], crashed'[i], preCandidateActive'[i],
                    preCandidateVote'[i], preCandidateConfig'[i], preGrants'[i])
    \* A queued SendPreVote is dispatched with exactly the recorded request.
    /\ s.send_pre_vote_pending = NewPreVoteReqFrom(i)
    /\ (s.send_pre_vote_pending => ExpectedPreVoteReqs(s, i) \subseteq messages')

ValidatePre(s, i) ==
    StateMatches(s, i, role[i], vote[i], lastLog[i], committedConfig[i],
                 committedConfigIndex[i], effectiveConfig[i], effectiveConfigIndex[i],
                 leaseValid[i], candidateActive[i], candidateVote[i],
                 candidateConfig[i], grants[i], leaderActive[i], leaderVote[i],
                 votePersistPending[i], sendVotePending[i], logFlushPending[i],
                 seenGreaterLog[i], crashed[i], preCandidateActive[i],
                 preCandidateVote[i], preCandidateConfig[i], preGrants[i])

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

TraceAppendJointConfig(e) ==
    /\ AppendJointConfig(e.nid, JsonSet(e.args.target_config))
    /\ ValidatePost(e.post, e.nid)

TraceCommitMembership(e) ==
    /\ CommitMembership(e.nid)
    /\ ValidatePost(e.post, e.nid)

TraceRestart(e) ==
    /\ Restart(e.nid)
    /\ ValidatePost(e.post, e.nid)

(***************************************************************************
 * UPDATE-MAP                                                              *
 * code: engine_impl.rs:pre_elect; raft_core.rs:handle_tick_election,      *
 *       ExternalCommand::Elect { pre_vote: true }                         *
 * update: Update!PreElectFocus                                            *
 ***************************************************************************)
TracePreElect(e) ==
    /\ CASE e.args.trigger = "tick"     -> TickPreElect(e.nid)
         [] e.args.trigger = "external" -> ExternalPreElect(e.nid)
         [] OTHER                        -> FALSE
    /\ ValidatePost(e.post, e.nid)

(***************************************************************************
 * UPDATE-MAP                                                              *
 * code: engine_impl.rs:handle_pre_vote_req; raft_core.rs:                 *
 *       handle_pre_vote_request (Respond { when: None })                  *
 * update: Update!HandlePreVoteRequestFocus                                *
 * The returned response must be the immediately visible PreVoteResp with  *
 * the observed grant and responder last log; the responder's reported     *
 * vote must equal its (unchanged) model vote.                             *
 ***************************************************************************)
TraceHandlePreVoteRequest(e) ==
    LET req == PreVoteReqMsg(e.args.source, e.nid, SnapshotVote(e.args.vote),
                             SnapshotLog(e.args.last_log))
    IN /\ HandlePreVoteRequest(e.nid, req, FALSE)
       /\ ValidatePost(e.post, e.nid)
       /\ PreVoteRespMsg(e.nid, e.args.source, SnapshotVote(e.args.vote),
                         SnapshotLog(e.args.response_last_log),
                         e.args.response_granted) \in messages'
       /\ SnapshotVote(e.args.response_vote) = vote'[e.nid]
       /\ ~replyPending'[e.nid]

(***************************************************************************
 * UPDATE-MAP                                                              *
 * code: raft_core.rs:Notification::PreVoteResponse,                       *
 *       does_pre_candidate_vote_match; engine_impl.rs:handle_pre_vote_resp *
 * update: Update!HandlePreVoteResponseFocus                               *
 * The model's runtime gate must agree with the harness-observed gate.     *
 ***************************************************************************)
TraceHandlePreVoteResponse(e) ==
    LET resp == PreVoteRespMsg(e.args.source, e.nid, SnapshotVote(e.args.candidate_vote),
                               SnapshotLog(e.args.last_log), e.args.granted)
    IN /\ e.args.forwarded = (preCandidateActive[e.nid]
                                /\ preCandidateVote[e.nid] = SnapshotVote(e.args.candidate_vote))
       /\ HandlePreVoteResponse(e.nid, resp, FALSE)
       /\ ValidatePost(e.post, e.nid)

(***************************************************************************
 * Harness emulation of RaftCore::run_command for the commands queued by    *
 * the previous engine event. Silent model steps (PersistVote,              *
 * SendVoteRequest, FinishVoteBroadcast, FlushLog) are enabled only while   *
 * the current event is RuntimeDrain and only for its node; the event is    *
 * consumed once no persistence/dispatch remains pending, and its post      *
 * state is then compared.                                                  *
 ***************************************************************************)
TraceRuntimeSilent ==
    /\ cursor \in 1..Len(TraceLog)
    /\ TraceLog[cursor].name = "RuntimeDrain"
    /\ LET i == TraceLog[cursor].nid IN
       \/ PersistVote(i)
       \/ \E j \in Server : SendVoteRequest(i, j)
       \/ FinishVoteBroadcast(i)
       \/ FlushLog(i)
    /\ UNCHANGED cursor

TraceRuntimeDrain(e) ==
    /\ ~votePersistPending[e.nid]
    /\ ~sendVotePending[e.nid]
    /\ ~logFlushPending[e.nid]
    /\ UNCHANGED vars
    /\ ValidatePost(e.post, e.nid)

TraceStep ==
    /\ cursor \in 1..Len(TraceLog)
    /\ LET e == TraceLog[cursor]
       IN /\ e.nid \in Server
          \* Silent runtime steps run only inside a RuntimeDrain event, so every
          \* other event's pre-state must equal the current model state. A
          \* RuntimeDrain pre-state is tied to the previous post by TraceContinuity.
          /\ (cursor > 1 /\ e.name /= "RuntimeDrain" => ValidatePre(e.pre, e.nid))
          /\ CASE e.name = "StartElection"         -> TraceStartElection(e)
               [] e.name = "HandleVoteRequest"     -> TraceHandleVoteRequest(e)
               [] e.name = "HandleVoteResponse"    -> TraceHandleVoteResponse(e)
               [] e.name = "AppendJointConfig"     -> TraceAppendJointConfig(e)
               [] e.name = "CommitMembership"      -> TraceCommitMembership(e)
               [] e.name = "Restart"               -> TraceRestart(e)
               [] e.name = "PreElect"              -> TracePreElect(e)
               [] e.name = "HandlePreVoteRequest"  -> TraceHandlePreVoteRequest(e)
               [] e.name = "HandlePreVoteResponse" -> TraceHandlePreVoteResponse(e)
               [] e.name = "RuntimeDrain"          -> TraceRuntimeDrain(e)
               [] OTHER                             -> FALSE
    /\ cursor' = cursor + 1

TraceDone ==
    /\ cursor = Len(TraceLog) + 1
    /\ UNCHANGED traceVars

TraceNext == TraceStep \/ TraceRuntimeSilent \/ TraceDone

TraceSpec == TraceInit /\ [][TraceNext]_traceVars /\ WF_traceVars(TraceStep)
                       /\ WF_traceVars(TraceRuntimeSilent)
TraceConsumed == <>(cursor = Len(TraceLog) + 1)
TraceMatched == TraceConsumed
TraceTypeOK == TypeOK /\ cursor \in 1..(Len(TraceLog) + 1)
TraceView == <<vars, cursor>>

=============================================================================
