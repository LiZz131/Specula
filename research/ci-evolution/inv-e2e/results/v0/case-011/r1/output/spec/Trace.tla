------------------------------ MODULE Trace ------------------------------
EXTENDS base, Json, IOUtils

TraceRecords == ndJsonDeserialize(IOEnv.SPECULA_TRACE)
TraceLog == [k \in 1..Len(TraceRecords) |-> TraceRecords[k].event]

ASSUME Len(TraceLog) > 0

JsonSet(s) == {s[k] : k \in 1..Len(s)}
JsonConfig(c) == [k \in 1..Len(c) |-> JsonSet(c[k])]

SnapshotVote(v) == [term |-> v.term, node |-> v.node, committed |-> v.committed]
\* Absent logs (Option::None) map to the canonical base!NoLog record.
SnapshotLog(l) == IF l.present
                  THEN [present |-> TRUE, term |-> l.term, node |-> l.node, index |-> l.index]
                  ELSE NoLog(FirstNode)

PreEvent == TraceLog[1]
Focus == PreEvent.nid
Pre == PreEvent.pre

\* Every event of one trace concerns the focus node (engine-level harness).
ASSUME \A k \in 1..Len(TraceLog) : TraceLog[k].nid = TraceLog[1].nid

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
    \* UPDATE-MAP: Engine.pre_candidate (engine_impl.rs:95-101)
    /\ preCandidateActive = [i \in Server |-> i = Focus /\ Pre.pre_candidate_active]
    /\ preCandidateVote = [i \in Server |-> IF i = Focus
                                                THEN SnapshotVote(Pre.pre_candidate_vote)
                                                ELSE DefaultVote(i)]
    /\ preCandidateConfig = [i \in Server |-> IF i = Focus
                                                  THEN JsonConfig(Pre.pre_candidate_config)
                                                  ELSE <<InitialConfig>>]
    /\ preGrants = [i \in Server |-> IF i = Focus THEN JsonSet(Pre.pre_grants) ELSE {}]

\* Pre-state agreement for every event after the first one (multi-event
\* traces): the harness must not have changed engine state between events
\* other than through the recorded transitions.
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
    /\ (s.candidate_active => candidateConfig[i] = JsonConfig(s.candidate_config))
    /\ (s.candidate_active => grants[i] = JsonSet(s.grants))
    /\ leaderActive[i] = s.leader_active
    /\ votePersistPending[i] = s.save_vote_pending
    /\ sendVotePending[i] = s.send_vote_pending
    /\ logFlushPending[i] = s.append_pending
    /\ seenGreaterLog[i] = s.seen_greater_log
    /\ crashed[i] = s.crashed
    /\ preCandidateActive[i] = s.pre_candidate_active
    /\ (s.pre_candidate_active => preCandidateVote[i] = SnapshotVote(s.pre_candidate_vote))
    /\ (s.pre_candidate_active => preCandidateConfig[i] = JsonConfig(s.pre_candidate_config))
    /\ (s.pre_candidate_active => preGrants[i] = JsonSet(s.pre_grants))

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
    \* UPDATE-MAP: pre-candidate post-state (engine_impl.rs:149-165,263-264,298-322,516-554,
    \* vote_handler/mod.rs:244)
    /\ preCandidateActive'[i] = s.pre_candidate_active
    /\ (s.pre_candidate_active => preCandidateVote'[i] = SnapshotVote(s.pre_candidate_vote))
    /\ (s.pre_candidate_active => preCandidateConfig'[i] = JsonConfig(s.pre_candidate_config))
    /\ (s.pre_candidate_active => preGrants'[i] = JsonSet(s.pre_grants))

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

\* The SendPreVote command observed after pre_elect() corresponds exactly to
\* the PreVoteReq messages the model dispatched in this step: same probe vote,
\* same last log, one per other voter of the frozen configuration.
PreVoteRequestsMatch(e, i) ==
    LET sent == {m \in messages' \ messages : m.kind = "PreVoteReq" /\ m.source = i}
    IN IF e.post.send_pre_vote_pending
       THEN /\ sent /= {}
            /\ \A m \in sent : /\ m.vote = SnapshotVote(e.args.req_vote)
                               /\ m.lastLog = SnapshotLog(e.args.req_last_log)
            /\ {m.dest : m \in sent} = ConfigVoters(JsonConfig(e.post.pre_candidate_config)) \ {i}
       ELSE sent = {}

TraceStartElection(e) ==
    /\ ValidatePre(e.pre, e.nid)
    /\ StartElection(e.nid, e.args.transfer)
    /\ ValidatePost(e.post, e.nid)

\* UPDATE-MAP: engine-level pre_elect() as invoked by
\* ExternalCommand::Elect{pre_vote:true} (raft_core.rs:1683-1691)
TracePreElect(e) ==
    /\ ValidatePre(e.pre, e.nid)
    /\ ExternalPreElect(e.nid)
    /\ ValidatePost(e.post, e.nid)
    /\ PreVoteRequestsMatch(e, e.nid)

TraceHandleVoteRequest(e) ==
    LET req == Message("VoteReq", e.args.source, e.nid,
                       SnapshotVote(e.args.vote), SnapshotLog(e.args.last_log),
                       FALSE, e.args.transfer)
    IN /\ ValidatePre(e.pre, e.nid)
       /\ HandleVoteRequest(e.nid, req, FALSE)
       /\ ValidatePost(e.post, e.nid)
       /\ ResponseMatches(e, e.nid)

\* UPDATE-MAP: Engine::handle_pre_vote_req (engine_impl.rs:414-447)
TraceHandlePreVoteRequest(e) ==
    LET req == Message("PreVoteReq", e.args.source, e.nid,
                       SnapshotVote(e.args.vote), SnapshotLog(e.args.last_log),
                       FALSE, FALSE)
    IN /\ ValidatePre(e.pre, e.nid)
       /\ HandlePreVoteRequest(e.nid, req, FALSE)
       /\ ValidatePost(e.post, e.nid)
       \* the engine returns its own, unchanged vote and last log
       /\ SnapshotVote(e.args.response_vote) = vote[e.nid]
       /\ \E m \in messages' :
             /\ m.kind = "PreVoteResp"
             /\ m.source = e.nid
             /\ m.dest = e.args.source
             /\ m.vote = SnapshotVote(e.args.vote)
             /\ m.lastLog = SnapshotLog(e.args.response_last_log)
             /\ m.granted = e.args.response_granted

TraceHandleVoteResponse(e) ==
    LET resp == Message("VoteResp", e.args.source, e.nid,
                        SnapshotVote(e.args.vote), SnapshotLog(e.args.last_log),
                        e.args.granted, FALSE)
    IN /\ ValidatePre(e.pre, e.nid)
       /\ HandleVoteResponse(e.nid, resp, FALSE)
       /\ ValidatePost(e.post, e.nid)

\* UPDATE-MAP: RaftCore Notification::PreVoteResponse filter + Engine::handle_pre_vote_resp
\* (raft_core.rs:1803-1820, engine_impl.rs:516-554). `candidate_vote` is the
\* notification's pre-candidate vote that the runtime matched.
TraceHandlePreVoteResponse(e) ==
    LET resp == Message("PreVoteResp", e.args.source, e.nid,
                        SnapshotVote(e.args.candidate_vote), SnapshotLog(e.args.last_log),
                        e.args.granted, FALSE)
    IN /\ ValidatePre(e.pre, e.nid)
       /\ HandlePreVoteResponse(e.nid, resp, FALSE)
       /\ ValidatePost(e.post, e.nid)

\* Engine::append_entries with an empty segment (heartbeat contact).
TraceHandleAppendEntries(e) ==
    LET m == Message("Append", e.args.source, e.nid, SnapshotVote(e.args.vote),
                     NoLog(e.args.source), FALSE, FALSE)
    IN /\ ValidatePre(e.pre, e.nid)
       /\ HandleAppendEntries(e.nid, m, FALSE)
       /\ ValidatePost(e.post, e.nid)

TraceAppendJointConfig(e) ==
    /\ ValidatePre(e.pre, e.nid)
    /\ AppendJointConfig(e.nid, JsonSet(e.args.target_config))
    /\ ValidatePost(e.post, e.nid)

TraceCommitMembership(e) ==
    /\ ValidatePre(e.pre, e.nid)
    /\ CommitMembership(e.nid)
    /\ ValidatePost(e.post, e.nid)

TraceRestart(e) ==
    /\ ValidatePre(e.pre, e.nid)
    /\ Restart(e.nid)
    /\ ValidatePost(e.post, e.nid)

(***************************************************************************
 * RunCommands: the harness hands the queued engine commands to the        *
 * runtime boundary between two engine events (RaftCore::                  *
 * run_engine_commands, raft_core.rs:1110-1160). The completed runtime    *
 * effects are replayed by tightly-guarded silent model steps that may     *
 * fire only for the commands named in this event; the event itself is    *
 * consumed once the model state equals the recorded post-state.           *
 *************************************************************************)
AtRunCommands == /\ cursor \in 1..Len(TraceLog)
                 /\ TraceLog[cursor].name = "RunCommands"

RunCmds == JsonSet(TraceLog[cursor].args.commands)

TraceRunCommandsSilent ==
    /\ AtRunCommands
    /\ LET i == TraceLog[cursor].nid IN
       \/ "SaveVote" \in RunCmds /\ PersistVote(i)
       \/ "AppendEntries" \in RunCmds /\ FlushLog(i)
       \/ "SendVote" \in RunCmds /\ \E j \in Server : SendVoteRequest(i, j)
       \/ "SendVote" \in RunCmds /\ FinishVoteBroadcast(i)
    /\ UNCHANGED cursor

TraceRunCommands(e) ==
    /\ UNCHANGED vars
    /\ ValidatePost(e.post, e.nid)

TraceStep ==
    /\ cursor \in 1..Len(TraceLog)
    /\ LET e == TraceLog[cursor]
       IN CASE e.name = "StartElection"         -> TraceStartElection(e)
             [] e.name = "PreElect"              -> TracePreElect(e)
             [] e.name = "HandleVoteRequest"     -> TraceHandleVoteRequest(e)
             [] e.name = "HandlePreVoteRequest"  -> TraceHandlePreVoteRequest(e)
             [] e.name = "HandleVoteResponse"    -> TraceHandleVoteResponse(e)
             [] e.name = "HandlePreVoteResponse" -> TraceHandlePreVoteResponse(e)
             [] e.name = "HandleAppendEntries"   -> TraceHandleAppendEntries(e)
             [] e.name = "AppendJointConfig"     -> TraceAppendJointConfig(e)
             [] e.name = "CommitMembership"      -> TraceCommitMembership(e)
             [] e.name = "Restart"               -> TraceRestart(e)
             [] e.name = "RunCommands"           -> TraceRunCommands(e)
             [] OTHER                             -> FALSE
    /\ cursor' = cursor + 1

TraceDone ==
    /\ cursor = Len(TraceLog) + 1
    /\ UNCHANGED traceVars

TraceNext == TraceStep \/ TraceRunCommandsSilent \/ TraceDone

TraceSpec == TraceInit /\ [][TraceNext]_traceVars
                       /\ WF_traceVars(TraceStep \/ TraceRunCommandsSilent)
TraceConsumed == <>(cursor = Len(TraceLog) + 1)
TraceTypeOK == TypeOK /\ cursor \in 1..(Len(TraceLog) + 1)
TraceView == <<vars, cursor>>

\* Field-consumption audit: every event field used above, so a harness that
\* omits a mandatory field fails during evaluation rather than vacuously.
EventFieldsPresent ==
    \A k \in 1..Len(TraceLog) :
        LET e == TraceLog[k] IN
        /\ e.name = "RunCommands" \/
           \A s \in {e.pre, e.post} :
              {"role", "vote", "last_log", "committed_config", "committed_config_index",
               "effective_config", "effective_config_index", "lease_valid",
               "candidate_active", "candidate_vote", "candidate_config", "grants",
               "leader_active", "save_vote_pending", "send_vote_pending",
               "append_pending", "seen_greater_log", "crashed",
               "pre_candidate_active", "pre_candidate_vote", "pre_candidate_config",
               "pre_grants", "send_pre_vote_pending"} \subseteq DOMAIN s

ASSUME EventFieldsPresent

=============================================================================
