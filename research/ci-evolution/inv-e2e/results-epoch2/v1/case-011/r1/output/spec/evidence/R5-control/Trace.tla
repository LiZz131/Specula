------------------------------ MODULE Trace ------------------------------
(***************************************************************************
 * Trace validation for the Pre-Vote revision. Category A single-file,     *
 * single-node traces captured around real Engine transitions by the       *
 * harness (harness/src/specula_trace_test.rs).                            *
 *                                                                         *
 * Every event's post-state is compared field by field. From the second    *
 * event on, the pre-state is compared too; between events the harness     *
 * lets the runtime execute queued commands, which the model reaches with  *
 * silent PersistVote / SendVoteRequest / FinishVoteBroadcast / FlushLog   *
 * steps that are only enabled while the next event's pre-state says the   *
 * corresponding command is no longer pending.                             *
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
    /\ appendBehindVote = [i \in Server |-> IF i = Focus THEN Pre.append_behind_vote ELSE FALSE]
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
    /\ preActive = [i \in Server |-> i = Focus /\ Pre.pre_candidate_active]
    /\ preVote = [i \in Server |-> IF i = Focus
                                       THEN SnapshotVote(Pre.pre_candidate_vote)
                                       ELSE DefaultVote(i)]
    /\ preConfig = [i \in Server |-> IF i = Focus
                                         THEN JsonConfig(Pre.pre_candidate_config)
                                         ELSE <<InitialConfig>>]
    /\ preGrants = [i \in Server |-> IF i = Focus THEN JsonSet(Pre.pre_grants) ELSE {}]

\* Post-state: every captured field of the focus node.
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
    /\ preActive'[i] = s.pre_candidate_active
    /\ (s.pre_candidate_active => preVote'[i] = SnapshotVote(s.pre_candidate_vote))
    /\ (s.pre_candidate_active => preConfig'[i] = JsonConfig(s.pre_candidate_config))
    /\ (s.pre_candidate_active => preGrants'[i] = JsonSet(s.pre_grants))
    /\ votePersistPending'[i] = s.save_vote_pending
    /\ sendVotePending'[i] = s.send_vote_pending
    /\ logFlushPending'[i] = s.append_pending
    /\ appendBehindVote'[i] = s.append_behind_vote
    /\ seenGreaterLog'[i] = s.seen_greater_log
    /\ crashed'[i] = s.crashed
    \* SendPreVote is dispatched in the same command drain: a PreVoteReq leaves
    \* this node in this step iff the transition queued SendPreVote.
    /\ (s.send_pre_vote_pending =>
          \E m \in messages' : m.kind = "PreVoteReq" /\ m.source = i /\ m.vote = preVote'[i])
    /\ (~s.send_pre_vote_pending =>
          \A m \in messages' \ messages : m.kind /= "PreVoteReq")

\* Pre-state (from the second event on): the model must have reached the
\* captured state through the previous event plus constrained silent steps.
ValidatePre(s, i) ==
    /\ role[i] = s.role
    /\ vote[i] = SnapshotVote(s.vote)
    /\ lastLog[i] = SnapshotLog(s.last_log)
    /\ committedConfig[i] = JsonConfig(s.committed_config)
    /\ committedConfigIndex[i] = s.committed_config_index
    /\ effectiveConfig[i] = JsonConfig(s.effective_config)
    /\ effectiveConfigIndex[i] = s.effective_config_index
    /\ leaseValid[i] = s.lease_valid
    /\ candidateActive[i] = s.candidate_active
    /\ (s.candidate_active => candidateVote[i] = SnapshotVote(s.candidate_vote))
    /\ (s.candidate_active => grants[i] = JsonSet(s.grants))
    /\ leaderActive[i] = s.leader_active
    /\ preActive[i] = s.pre_candidate_active
    /\ (s.pre_candidate_active => preVote[i] = SnapshotVote(s.pre_candidate_vote))
    /\ (s.pre_candidate_active => preGrants[i] = JsonSet(s.pre_grants))
    /\ votePersistPending[i] = s.save_vote_pending
    /\ sendVotePending[i] = s.send_vote_pending
    /\ logFlushPending[i] = s.append_pending
    /\ appendBehindVote[i] = s.append_behind_vote
    /\ seenGreaterLog[i] = s.seen_greater_log
    /\ crashed[i] = s.crashed

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

\* SendVote queued in this transition <=> a (new) real election snapshot.
SendVoteMatches(e, i) ==
    ("send_vote" \in DOMAIN e.args /\ e.args.send_vote.present) =>
        /\ sendVotePending'[i]
        /\ candidateVote'[i] = SnapshotVote(e.args.send_vote.vote)
        /\ lastLog'[i] = SnapshotLog(e.args.send_vote.last_log)

TraceStartElection(e) ==
    /\ StartElection(e.nid, e.args.transfer)
    /\ ValidatePost(e.post, e.nid)
    /\ SendVoteMatches(e, e.nid)

\* UPDATE-MAP code: engine_impl.rs:297-322 update: Update!AffectedActions
TracePreElect(e) ==
    /\ PreElect(e.nid)
    /\ ValidatePost(e.post, e.nid)
    /\ SendVoteMatches(e, e.nid)
    /\ e.args.send_pre_vote.present =>
          LET pv == SnapshotVote(e.args.send_pre_vote.vote)
              lg == SnapshotLog(e.args.send_pre_vote.last_log)
          IN /\ pv = preVote'[e.nid]
             /\ \A j \in ConfigVoters(effectiveConfig[e.nid]) \ {e.nid} :
                   MessageR("PreVoteReq", e.nid, j, pv, lg, FALSE, FALSE, pv) \in messages'

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

\* UPDATE-MAP code: engine_impl.rs:414-447 update: Update!HandlePreVoteRequestAffected
TraceHandlePreVoteRequest(e) ==
    LET rv == SnapshotVote(e.args.vote)
        req == MessageR("PreVoteReq", e.args.source, e.nid, rv,
                        SnapshotLog(e.args.last_log), FALSE, e.args.transfer, rv)
    IN /\ HandlePreVoteRequest(e.nid, req, FALSE)
       /\ ValidatePost(e.post, e.nid)
       /\ MessageR("PreVoteResp", e.nid, e.args.source,
                   SnapshotVote(e.args.response_vote), SnapshotLog(e.args.response_last_log),
                   e.args.response_granted, FALSE, rv) \in messages'

\* UPDATE-MAP code: engine_impl.rs:516-554 update: Update!HandlePreVoteResponseAffected
TraceHandlePreVoteResponse(e) ==
    LET resp == MessageR("PreVoteResp", e.args.source, e.nid,
                         SnapshotVote(e.args.vote), SnapshotLog(e.args.last_log),
                         e.args.granted, FALSE, SnapshotVote(e.args.round))
    IN /\ HandlePreVoteResponse(e.nid, resp, FALSE)
       /\ ValidatePost(e.post, e.nid)
       /\ SendVoteMatches(e, e.nid)

TraceHandleAppendEntries(e) ==
    LET req == Message("Append", e.args.source, e.nid,
                       SnapshotVote(e.args.vote), SnapshotLog(e.args.last_log),
                       FALSE, FALSE)
    IN /\ e.args.ok
       /\ HandleAppendEntries(e.nid, req, FALSE)
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
       IN /\ (cursor > 1 => ValidatePre(e.pre, e.nid))
          /\ CASE e.name = "StartElection"         -> TraceStartElection(e)
               [] e.name = "PreElect"              -> TracePreElect(e)
               [] e.name = "HandleVoteRequest"     -> TraceHandleVoteRequest(e)
               [] e.name = "HandleVoteResponse"    -> TraceHandleVoteResponse(e)
               [] e.name = "HandlePreVoteRequest"  -> TraceHandlePreVoteRequest(e)
               [] e.name = "HandlePreVoteResponse" -> TraceHandlePreVoteResponse(e)
               [] e.name = "HandleAppendEntries"   -> TraceHandleAppendEntries(e)
               [] e.name = "AppendJointConfig"     -> TraceAppendJointConfig(e)
               [] e.name = "CommitMembership"      -> TraceCommitMembership(e)
               [] e.name = "Restart"               -> TraceRestart(e)
               [] OTHER                             -> FALSE
    /\ cursor' = cursor + 1

(***************************************************************************
 * Silent runtime completions between two captured events (focus node      *
 * only). Each is enabled only while the model still has the command       *
 * pending and the next captured pre-state shows it completed.             *
 * raft_core.rs:2265-2305 (SaveVote awaited; AppendEntries submit/flush),  *
 * raft_core.rs:1385-1478,2339-2344 (vote request dispatch).               *
 *************************************************************************)
NextPre == TraceLog[cursor].pre

SilentStep ==
    /\ cursor \in 2..Len(TraceLog)
    /\ \/ /\ votePersistPending[Focus] /\ ~NextPre.save_vote_pending
          /\ PersistVote(Focus)
       \/ /\ sendVotePending[Focus] /\ ~NextPre.send_vote_pending
          /\ \/ \E j \in Server : SendVoteRequest(Focus, j)
             \/ FinishVoteBroadcast(Focus)
       \/ /\ logFlushPending[Focus] /\ ~NextPre.append_pending
          /\ FlushLog(Focus)
    /\ UNCHANGED cursor

TraceDone ==
    /\ cursor = Len(TraceLog) + 1
    /\ UNCHANGED traceVars

TraceNext == TraceStep \/ SilentStep \/ TraceDone

TraceSpec == TraceInit /\ [][TraceNext]_traceVars /\ WF_traceVars(TraceStep \/ SilentStep)
TraceConsumed == <>(cursor = Len(TraceLog) + 1)
TraceTypeOK == TypeOK /\ cursor \in 1..(Len(TraceLog) + 1)
TraceView == <<vars, cursor>>

\* Fields consumed by this module (checked by harness/check-trace-fields.sh).
ConsumedStateFields ==
    {"role", "vote", "last_log", "committed_config", "committed_config_index",
     "effective_config", "effective_config_index", "lease_valid",
     "candidate_active", "candidate_vote", "candidate_config", "grants",
     "leader_active", "pre_candidate_active", "pre_candidate_vote",
     "pre_candidate_config", "pre_grants", "save_vote_pending",
     "send_vote_pending", "send_pre_vote_pending", "append_pending",
     "append_behind_vote", "seen_greater_log", "crashed"}

=============================================================================
