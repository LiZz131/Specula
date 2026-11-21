------------------------------ MODULE base ------------------------------
(***************************************************************************
 * OpenRaft election reference model, updated for the `update` revision    *
 * (neutral synthetic commit 3ab6cdd) that adds an optional Pre-Vote round. *
 *                                                                         *
 * Source boundary: openraft/src/engine/engine_impl.rs,                    *
 * engine/handler/vote_handler/mod.rs, core/raft_core.rs,                  *
 * raft_state/membership_state/mod.rs, and proposer/candidate.rs.          *
 *                                                                         *
 * Line references are to the updated tree                                 *
 * /work/current/.specula-output/artifact (commit `update`).               *
 * Prior exact-old references are kept where the code did not move.       *
 *************************************************************************)

EXTENDS Integers, Naturals, FiniteSets, Sequences, TLC

CONSTANTS Server, NodeOrder, MaxTerm, MaxLogIndex, InitialConfig,
          \* UPDATE-MAP
          \* code: openraft/src/core/raft_core.rs:2010-2035 (enable_pre_vote),
          \*       openraft/src/config/runtime_config.rs:11,19,
          \*       openraft/src/raft/runtime_config_handle.rs:51-53
          \* update: Update!TickPreVoteModes section
          \* The set of election-tick modes the runtime may use. {FALSE} is the
          \* historical behavior (default Config::enable_pre_vote = None), {TRUE}
          \* is a Pre-Vote cluster, {FALSE, TRUE} models runtime toggling via
          \* Raft::runtime_config().pre_vote(enabled).
          TickPreVoteModes

ReferenceServer == {"1", "2", "3"}
ReferenceNodeOrder == <<"1", "2", "3">>
ReferenceInitialConfig == {"1", "2", "3"}
PreVoteOnly == {TRUE}
PreVoteToggle == {FALSE, TRUE}
PreVoteOff == {FALSE}

ASSUME /\ Server /= {}
       /\ Len(NodeOrder) = Cardinality(Server)
       /\ {NodeOrder[k] : k \in 1..Len(NodeOrder)} = Server
       /\ InitialConfig \subseteq Server
       /\ InitialConfig /= {}
       /\ MaxTerm \in Nat \ {0}
       /\ MaxLogIndex \in Nat \ {0}
       /\ TickPreVoteModes \subseteq BOOLEAN
       /\ TickPreVoteModes /= {}

FirstNode == NodeOrder[1]

DefaultVote(i) == [term |-> 0, node |-> i, committed |-> FALSE]
Vote(t, n, c) == [term |-> t, node |-> n, committed |-> c]

\* REPAIR (prior model defect, validation round 2): Option<LogId>::None is a
\* single value (log_id/mod.rs:18-61); the prior encoding embedded the node id,
\* so None from two different nodes compared unequal and LogLE(None, None)
\* was FALSE, making every log-less vote/pre-vote request fail its log check
\* (no 3-voter election could ever succeed in the prior MC.cfg). All absent
\* logs now share one canonical record; the parameter is kept for callers.
NoLog(i) == [present |-> FALSE, term |-> 0, node |-> FirstNode, index |-> 0]
Log(t, n, x) == [present |-> TRUE, term |-> t, node |-> n, index |-> x]

NodePos(i) == CHOOSE k \in 1..Len(NodeOrder) : NodeOrder[k] = i

(***************************************************************************
 * The selected UTConfig uses leader_id_adv::LeaderId: term, then node,    *
 * then committed status.                                                  *
 * openraft/src/engine/testing.rs:38-48                                    *
 * openraft/src/vote/leader_id/leader_id_adv.rs:9-25                       *
 * openraft/src/vote/ref_vote.rs:35-60                                     *
 *************************************************************************)
VoteLT(a, b) ==
    \/ a.term < b.term
    \/ /\ a.term = b.term
       /\ NodePos(a.node) < NodePos(b.node)
    \/ /\ a.term = b.term
       /\ a.node = b.node
       /\ ~a.committed
       /\ b.committed

VoteLE(a, b) == a = b \/ VoteLT(a, b)

(***************************************************************************
 * Option<LogId> order: None < Some; LogId orders leader ID then index.     *
 * openraft/src/log_id/mod.rs:18-61                                        *
 *************************************************************************)
LogLT(a, b) ==
    \/ /\ ~a.present /\ b.present
    \/ /\ a.present /\ b.present
       /\ \/ a.term < b.term
          \/ /\ a.term = b.term
             /\ NodePos(a.node) < NodePos(b.node)
          \/ /\ a.term = b.term
             /\ a.node = b.node
             /\ a.index < b.index

LogLE(a, b) == a = b \/ LogLT(a, b)

IsConfig(c) ==
    /\ c \in Seq(SUBSET Server)
    /\ Len(c) \in 1..2
    /\ \A k \in 1..Len(c) : c[k] /= {}

ConfigVoters(c) == UNION {c[k] : k \in 1..Len(c)}
InConfig(i, c) == i \in ConfigVoters(c)
Majority(ids, oneConfig) == 2 * Cardinality(ids \cap oneConfig) > Cardinality(oneConfig)

(***************************************************************************
 * Joint quorum is a strict majority in every constituent configuration.  *
 * openraft/src/membership/membership_impl_quorum_set.rs:8-32              *
 * openraft/src/quorum/quorum_set_impl.rs:31-45                            *
 *************************************************************************)
IsQuorum(c, ids) == \A k \in 1..Len(c) : Majority(ids, c[k])

RoleFrom(i, v, cfg) ==
    IF InConfig(i, cfg)
    THEN IF v.node = i
         THEN IF v.committed THEN "Leader" ELSE "Candidate"
         ELSE "Follower"
    ELSE "Learner"

Message(kind, source, dest, v, lg, granted, transfer) ==
    [kind |-> kind,
     source |-> source,
     dest |-> dest,
     vote |-> v,
     lastLog |-> lg,
     granted |-> granted,
     transfer |-> transfer]

NoMessage == Message("None", FirstNode, FirstNode, DefaultVote(FirstNode), NoLog(FirstNode), FALSE, FALSE)


VARIABLES
    role,
    vote,
    durableVote,
    votePersistPending,
    replyPending,
    replyMessage,
    sendVotePending,
    leaseValid,
    candidateActive,
    candidateVote,
    candidateConfig,
    grants,
    sentVoteReq,
    leaderActive,
    leaderVote,
    leaderCertified,
    leaderConfig,
    leaderGrants,
    lastLog,
    durableLastLog,
    logFlushPending,
    committedConfig,
    committedConfigIndex,
    effectiveConfig,
    effectiveConfigIndex,
    durableConfig,
    durableConfigIndex,
    messages,
    crashed,
    seenGreaterLog,
    \* UPDATE-MAP
    \* code: openraft/src/engine/engine_impl.rs:95-101,117,149-165
    \* update: Update!PreVoteVisibleVars
    \* Engine.pre_candidate: Option<Candidate>. Its vote is the hypothetical
    \* next-term self vote; its quorum tracker is frozen from the effective
    \* membership at pre_elect(); grants are the granters() set.
    preCandidateActive,
    preCandidateVote,
    preCandidateConfig,
    preGrants

voteVars == <<vote, durableVote, votePersistPending, replyPending, replyMessage,
              sendVotePending, leaseValid>>
candidateVars == <<candidateActive, candidateVote, candidateConfig, grants, sentVoteReq>>
leaderVars == <<leaderActive, leaderVote, leaderCertified, leaderConfig, leaderGrants>>
logVars == <<lastLog, durableLastLog, logFlushPending>>
configVars == <<committedConfig, committedConfigIndex, effectiveConfig,
                effectiveConfigIndex, durableConfig, durableConfigIndex>>
runtimeVars == <<role, crashed, seenGreaterLog>>
preVoteVars == <<preCandidateActive, preCandidateVote, preCandidateConfig, preGrants>>
vars == <<runtimeVars, voteVars, candidateVars, leaderVars, logVars, configVars,
          messages, preVoteVars>>

(***************************************************************************
 * VoteHandler::update_internal_server_state after an accepted vote:       *
 * is_leader -> become_leader; is_leading -> nothing; otherwise            *
 * become_following(), which clears leader, candidate and (new) the        *
 * pre-candidate.                                                          *
 * openraft/src/engine/handler/vote_handler/mod.rs:154-162,234-250         *
 * openraft/src/raft_state/mod.rs:453-467                                  *
 *************************************************************************)
\* UPDATE-MAP
\* code: openraft/src/engine/handler/vote_handler/mod.rs:244
\* update: Update!AffectedActions (become_following callers)
Follows(i, v) == ~(v.node = i /\ InConfig(i, effectiveConfig[i]))

Init ==
    /\ role = [i \in Server |-> IF i \in InitialConfig THEN "Follower" ELSE "Learner"]
    /\ vote = [i \in Server |-> DefaultVote(i)]
    /\ durableVote = vote
    /\ votePersistPending = [i \in Server |-> FALSE]
    /\ replyPending = [i \in Server |-> FALSE]
    /\ replyMessage = [i \in Server |-> NoMessage]
    /\ sendVotePending = [i \in Server |-> FALSE]
    /\ leaseValid = [i \in Server |-> FALSE]
    /\ candidateActive = [i \in Server |-> FALSE]
    /\ candidateVote = vote
    /\ candidateConfig = [i \in Server |-> <<InitialConfig>>]
    /\ grants = [i \in Server |-> {}]
    /\ sentVoteReq = [i \in Server |-> {}]
    /\ leaderActive = [i \in Server |-> FALSE]
    /\ leaderVote = vote
    /\ leaderCertified = [i \in Server |-> FALSE]
    /\ leaderConfig = [i \in Server |-> <<InitialConfig>>]
    /\ leaderGrants = [i \in Server |-> {}]
    /\ lastLog = [i \in Server |-> NoLog(i)]
    /\ durableLastLog = lastLog
    /\ logFlushPending = [i \in Server |-> FALSE]
    /\ committedConfig = [i \in Server |-> <<InitialConfig>>]
    /\ committedConfigIndex = [i \in Server |-> 0]
    /\ effectiveConfig = committedConfig
    /\ effectiveConfigIndex = committedConfigIndex
    /\ durableConfig = committedConfig
    /\ durableConfigIndex = committedConfigIndex
    /\ messages = {}
    /\ crashed = [i \in Server |-> FALSE]
    /\ seenGreaterLog = [i \in Server |-> FALSE]
    \* openraft/src/engine/engine_impl.rs:117 (Engine::new: pre_candidate: None)
    /\ preCandidateActive = [i \in Server |-> FALSE]
    /\ preCandidateVote = vote
    /\ preCandidateConfig = [i \in Server |-> <<InitialConfig>>]
    /\ preGrants = [i \in Server |-> {}]

(***************************************************************************
 * Engine::do_elect. Candidate membership and last log are snapshotted     *
 * before the pending self vote is installed. SaveVote is queued before    *
 * SendVote. The update makes a real election supersede any in-flight      *
 * Pre-Vote round.                                                         *
 * openraft/src/engine/engine_impl.rs:122-146,262-289                      *
 * openraft/src/engine/handler/vote_handler/mod.rs:106-150                 *
 *                                                                         *
 * do_elect itself does not reset seen_greater_log; only the election tick *
 * does (raft_core.rs:2026-2027). `msgs` is the message set produced by    *
 * the caller's own message consumption, if any.                           *
 *                                                                         *
 * Guard ~votePersistPending /\ ~replyPending is inherited from the prior *
 * suite: the model keeps one pending vote-persist/reply slot, and in      *
 * scope SaveVote has no condition (engine/command.rs:340-364), so         *
 * RaftCore::run_engine_commands (raft_core.rs:1110-1160) completes it     *
 * before the next engine event on that node.                              *
 *************************************************************************)
\* UPDATE-MAP
\* code: openraft/src/engine/engine_impl.rs:262-264
\* update: Update!AffectedActions (StartElection, PreVoteWin)
DoElect(i, transfer, msgs, resetGreaterLog) ==
    /\ ~crashed[i]
    /\ vote[i].term < MaxTerm
    /\ ~votePersistPending[i]
    /\ ~replyPending[i]
    /\ LET nv == Vote(vote[i].term + 1, i, FALSE) IN
       /\ vote' = [vote EXCEPT ![i] = nv]
       /\ candidateActive' = [candidateActive EXCEPT ![i] = TRUE]
       /\ candidateVote' = [candidateVote EXCEPT ![i] = nv]
    /\ candidateConfig' = [candidateConfig EXCEPT ![i] = effectiveConfig[i]]
    /\ grants' = [grants EXCEPT ![i] = {}]
    /\ sentVoteReq' = [sentVoteReq EXCEPT ![i] = {}]
    /\ role' = [role EXCEPT ![i] = "Candidate"]
    /\ votePersistPending' = [votePersistPending EXCEPT ![i] = TRUE]
    /\ sendVotePending' = [sendVotePending EXCEPT ![i] = TRUE]
    /\ leaseValid' = [leaseValid EXCEPT ![i] = FALSE]
    \* engine_impl.rs:263-264: a real election supersedes any Pre-Vote round.
    /\ preCandidateActive' = [preCandidateActive EXCEPT ![i] = FALSE]
    /\ messages' = msgs
    /\ seenGreaterLog' = IF resetGreaterLog
                         THEN [seenGreaterLog EXCEPT ![i] = FALSE]
                         ELSE seenGreaterLog
    /\ UNCHANGED <<durableVote, replyPending, replyMessage, leaderVars,
                    logVars, configVars, crashed,
                    preCandidateVote, preCandidateConfig, preGrants>>

\* ExternalCommand::Elect{pre_vote:false} and elect_by_leadership_transfer
\* require the node to be a voter (raft_core.rs:1683-1686).
StartElection(i, transfer) ==
    /\ InConfig(i, effectiveConfig[i])
    /\ DoElect(i, transfer, messages, FALSE)

(***************************************************************************
 * Engine::pre_elect: probe vote at term+1 for this node; no vote, lease,  *
 * or server-state change. The pre-candidate freezes the effective         *
 * membership and last log. A self-grant that is already a quorum (single  *
 * voter) proceeds directly to elect().                                    *
 * openraft/src/engine/engine_impl.rs:149-165,298-322                      *
 *                                                                         *
 * SendPreVote has no I/O precondition (engine/command.rs:359) and         *
 * spawn_parallel_vote_requests only spawns RPC tasks to the effective     *
 * voters other than self (raft_core.rs:1385-1478, 2342-2344); it runs in  *
 * the same run_engine_commands drain, so the requests are dispatched      *
 * with the pre_elect step. Per-RPC delay, reordering, timeout and         *
 * Unreachable are represented by the message set and DropMessage.        *
 *************************************************************************)
\* UPDATE-MAP
\* code: openraft/src/engine/engine_impl.rs:298-322
\* update: Update!AffectedActions (MCTickElect pre-vote branch, MCExternalPreElect)
PreElect(i, resetGreaterLog) ==
    /\ ~crashed[i]
    /\ vote[i].term < MaxTerm
    /\ LET pv == Vote(vote[i].term + 1, i, FALSE)
           cfg == effectiveConfig[i]
       IN
       IF IsQuorum(cfg, {i})
       THEN \* engine_impl.rs:308-315: self-grant reaches quorum -> elect()
            DoElect(i, FALSE, messages, resetGreaterLog)
       ELSE \* engine_impl.rs:317-321: queue SendPreVote, stay as-is
            /\ ~votePersistPending[i]
            /\ preCandidateActive' = [preCandidateActive EXCEPT ![i] = TRUE]
            /\ preCandidateVote' = [preCandidateVote EXCEPT ![i] = pv]
            /\ preCandidateConfig' = [preCandidateConfig EXCEPT ![i] = cfg]
            /\ preGrants' = [preGrants EXCEPT ![i] = {i}]
            /\ messages' = messages \cup
                  {Message("PreVoteReq", i, j, pv, lastLog[i], FALSE, FALSE) :
                       j \in ConfigVoters(cfg) \ {i}}
            /\ seenGreaterLog' = IF resetGreaterLog
                                 THEN [seenGreaterLog EXCEPT ![i] = FALSE]
                                 ELSE seenGreaterLog
            /\ UNCHANGED <<role, crashed, voteVars, candidateVars, leaderVars,
                            logVars, configVars>>

(***************************************************************************
 * RaftCore::handle_tick_election.                                          *
 * - skips an established server_state Leader and non-voters               *
 * - single voter: skip while a candidate exists, else elect immediately   *
 * - multiple voters: elect only after the local vote expired             *
 *   (is_expired(now, election_timeout) implies the lease expired)         *
 * - resets seen_greater_log, then pre_elect() when Pre-Vote is enabled    *
 *   for a multi-voter config, else elect().                               *
 * The "fresh round in flight" skip (raft_core.rs:2014-2024) is a timing   *
 * rate limit; time is abstract, so a stale round may be restarted.        *
 * openraft/src/core/raft_core.rs:1959-2036                                *
 *************************************************************************)
\* UPDATE-MAP
\* code: openraft/src/core/raft_core.rs:1981-2035
\* update: Update!AffectedActions (MCTickElect)
TickElect(i) ==
    /\ ~crashed[i]
    /\ role[i] /= "Leader"
    /\ InConfig(i, effectiveConfig[i])
    /\ LET voterCount == Cardinality(ConfigVoters(effectiveConfig[i])) IN
       /\ IF voterCount = 1 THEN ~candidateActive[i] ELSE ~leaseValid[i]
       /\ \E usePreVote \in TickPreVoteModes :
            \* reset_greater_log is applied by the tick before either path
            \* (raft_core.rs:2026-2027).
            IF usePreVote /\ voterCount > 1
            THEN PreElect(i, TRUE)                 \* raft_core.rs:2029-2031
            ELSE DoElect(i, FALSE, messages, TRUE) \* raft_core.rs:2032-2035

(***************************************************************************
 * RaftCore ExternalCommand::Elect { pre_vote }: voter check only, no role *
 * or lease check ("TODO: reject if it is already a leader?").            *
 * openraft/src/core/raft_core.rs:1683-1695                                *
 *************************************************************************)
ExternalElect(i) == StartElection(i, FALSE)

\* UPDATE-MAP
\* code: openraft/src/core/raft_core.rs:1683-1691
\* update: Update!AffectedActions (MCExternalPreElect)
ExternalPreElect(i) ==
    /\ InConfig(i, effectiveConfig[i])
    /\ PreElect(i, FALSE)

StartTransferElection(i) == StartElection(i, TRUE)

(***************************************************************************
 * save_vote() is awaited. A pending election gets a local granted response;
 * a vote-request reply held on IOFlushed becomes visible here.              *
 * openraft/src/core/raft_core.rs:2274-2303                                 *
 *************************************************************************)
PersistVote(i) ==
    /\ ~crashed[i]
    /\ votePersistPending[i]
    /\ VoteLT(durableVote[i], vote[i])
    /\ durableVote' = [durableVote EXCEPT ![i] = vote[i]]
    /\ votePersistPending' = [votePersistPending EXCEPT ![i] = FALSE]
    /\ messages' =
          IF replyPending[i]
          THEN messages \cup {replyMessage[i]}
          ELSE IF candidateActive[i]
                  /\ candidateVote[i] = vote[i]
                  /\ ~vote[i].committed
               THEN messages \cup {Message("VoteResp", i, i, vote[i], NoLog(i), TRUE, FALSE)}
               ELSE messages
    /\ replyPending' = [replyPending EXCEPT ![i] = FALSE]
    /\ replyMessage' = [replyMessage EXCEPT ![i] = NoMessage]
    /\ UNCHANGED <<role, vote, sendVotePending, leaseValid, candidateVars,
                    leaderVars, logVars, configVars, crashed, seenGreaterLog,
                    preVoteVars>>

(***************************************************************************
 * Remote requests start only after the candidate vote is durable. Runtime  *
 * enumerates the current effective voters; the candidate validates against *
 * its frozen copy. Those are equal at election start.                       *
 * openraft/src/core/raft_core.rs:1385-1478,2339-2341                       *
 *************************************************************************)
SendVoteRequest(i, j) ==
    /\ ~crashed[i]
    /\ candidateActive[i]
    /\ sendVotePending[i]
    /\ candidateVote[i] = vote[i]
    /\ VoteLE(candidateVote[i], durableVote[i])
    /\ j \in ConfigVoters(candidateConfig[i]) \ {i}
    /\ j \notin sentVoteReq[i]
    /\ messages' = messages \cup
          {Message("VoteReq", i, j, candidateVote[i], lastLog[i], FALSE, FALSE)}
    /\ sentVoteReq' = [sentVoteReq EXCEPT ![i] = @ \cup {j}]
    /\ UNCHANGED <<runtimeVars, voteVars, candidateActive, candidateVote,
                    candidateConfig, grants, leaderVars, logVars, configVars,
                    preVoteVars>>

FinishVoteBroadcast(i) ==
    /\ sendVotePending[i]
    /\ ConfigVoters(candidateConfig[i]) \ {i} \subseteq sentVoteReq[i]
    /\ sendVotePending' = [sendVotePending EXCEPT ![i] = FALSE]
    /\ UNCHANGED <<runtimeVars, vote, durableVote, votePersistPending,
                    replyPending, replyMessage, leaseValid, candidateVars,
                    leaderVars, logVars, configVars, messages, preVoteVars>>

RemainingMessages(m, consume) == IF consume THEN messages \ {m} ELSE messages

(***************************************************************************
 * Guard order is lease, then last-log, then vote comparison. Strict vote   *
 * changes defer the response until persistence; equal votes merely touch   *
 * the lease and can reply immediately. An accepted vote of another node    *
 * runs become_following(), which now also clears the pre-candidate.        *
 * openraft/src/engine/engine_impl.rs:350-404                               *
 * openraft/src/engine/handler/vote_handler/mod.rs:106-162,234-250          *
 * openraft/src/core/raft_core.rs:1532-1549                                 *
 *************************************************************************)
HandleVoteRequest(i, m, consume) ==
    /\ ~crashed[i]
    /\ m.kind = "VoteReq"
    /\ m.dest = i
    /\ ~votePersistPending[i]
    /\ ~replyPending[i]
    /\ LET leaseBlocked == vote[i].committed /\ leaseValid[i] /\ ~m.transfer
           logOK == LogLE(lastLog[i], m.lastLog)
           orderOK == VoteLE(vote[i], m.vote)
           grant == ~leaseBlocked /\ logOK /\ orderOK
           strict == grant /\ VoteLT(vote[i], m.vote)
           nv == IF grant THEN m.vote ELSE vote[i]
           resp == Message("VoteResp", i, m.source, nv, lastLog[i], grant, FALSE)
           follows == grant /\ Follows(i, nv)
       IN
       /\ vote' = [vote EXCEPT ![i] = nv]
       /\ role' = [role EXCEPT ![i] = IF grant THEN RoleFrom(i, nv, effectiveConfig[i]) ELSE @]
       /\ leaseValid' = [leaseValid EXCEPT ![i] = IF grant THEN nv.committed ELSE @]
       /\ votePersistPending' = [votePersistPending EXCEPT ![i] = strict]
       /\ replyPending' = [replyPending EXCEPT ![i] = strict]
       /\ replyMessage' = [replyMessage EXCEPT ![i] = IF strict THEN resp ELSE NoMessage]
       /\ messages' = IF strict
                       THEN RemainingMessages(m, consume)
                       ELSE RemainingMessages(m, consume) \cup {resp}
       /\ candidateActive' = [candidateActive EXCEPT ![i] = IF follows THEN FALSE ELSE @]
       /\ leaderActive' = [leaderActive EXCEPT ![i] = IF follows THEN FALSE
                                                      ELSE IF grant /\ nv.committed /\ nv.node = i
                                                           THEN TRUE ELSE @]
       /\ leaderVote' = [leaderVote EXCEPT ![i] = IF grant /\ nv.committed /\ nv.node = i
                                                  THEN nv ELSE @]
       \* UPDATE-MAP
       \* code: openraft/src/engine/handler/vote_handler/mod.rs:244
       \* update: Update!AffectedActions (DeliverVoteRequest)
       /\ preCandidateActive' = [preCandidateActive EXCEPT ![i] = IF follows THEN FALSE ELSE @]
    /\ UNCHANGED <<durableVote, sendVotePending, candidateVote, candidateConfig,
                    grants, sentVoteReq, leaderCertified, leaderConfig,
                    leaderGrants, logVars, configVars, crashed, seenGreaterLog,
                    preCandidateVote, preCandidateConfig, preGrants>>

DeliverVoteRequest(m) ==
    /\ m \in messages
    /\ HandleVoteRequest(m.dest, m, TRUE)

(***************************************************************************
 * Engine::handle_pre_vote_req: pure query. Lease (never a transfer), then *
 * last-log, then `req.vote >= local vote`; no vote/lease/role update and  *
 * no command other than the immediate Respond{when: None}.                *
 * openraft/src/engine/engine_impl.rs:414-447                              *
 * openraft/src/core/raft_core.rs:1551-1562,1603-1607                      *
 *                                                                         *
 * The response record carries the probed pre-candidate vote in `vote`    *
 * (the runtime's Notification::PreVoteResponse.candidate_vote,            *
 * raft_core.rs:1440-1458) and the responder's last log; the responder's  *
 * own VoteResponse.vote is not consumed by handle_pre_vote_resp.          *
 *************************************************************************)
\* UPDATE-MAP
\* code: openraft/src/engine/engine_impl.rs:414-447
\* update: Update!AffectedActions (DeliverPreVoteRequest)
HandlePreVoteRequest(i, m, consume) ==
    /\ ~crashed[i]
    /\ m.kind = "PreVoteReq"
    /\ m.dest = i
    /\ ~votePersistPending[i]
    /\ LET leaseBlocked == vote[i].committed /\ leaseValid[i]   \* :433-437
           logOK == LogLE(lastLog[i], m.lastLog)                \* :439-447 (reject if req < mine)
           orderOK == VoteLE(vote[i], m.vote)                   \* :445-446
           grant == ~leaseBlocked /\ logOK /\ orderOK
       IN messages' = RemainingMessages(m, consume) \cup
              {Message("PreVoteResp", i, m.source, m.vote, lastLog[i], grant, FALSE)}
    /\ UNCHANGED <<runtimeVars, voteVars, candidateVars, leaderVars, logVars,
                    configVars, preVoteVars>>

DeliverPreVoteRequest(m) ==
    /\ m \in messages
    /\ HandlePreVoteRequest(m.dest, m, TRUE)

(***************************************************************************
 * Exact granted vote equality advances the frozen quorum. Establishment    *
 * commits the vote in projected state and projects the leader blank log;   *
 * committed vote persistence remains pending. establish_leader() consumes  *
 * only the candidate: the pre-candidate is not cleared (is_leader ->       *
 * become_leader, not become_following).                                    *
 * openraft/src/engine/engine_impl.rs:450-509,855-881                       *
 * openraft/src/proposer/candidate.rs:106-117                               *
 *************************************************************************)
HandleVoteResponse(i, m, consume) ==
    /\ ~crashed[i]
    /\ m.kind = "VoteResp"
    /\ m.dest = i
    /\ LET exact == candidateActive[i] /\ m.granted /\ m.vote = candidateVote[i]
           ng == grants[i] \cup {m.source}
           wins == exact /\ IsQuorum(candidateConfig[i], ng)
           cv == Vote(candidateVote[i].term, candidateVote[i].node, TRUE)
           stripped == Vote(m.vote.term, m.vote.node, FALSE)
           adopt == candidateActive[i] /\ ~exact /\ VoteLT(vote[i], stripped)
           newIndex == lastLog[i].index + 1
       IN
       /\ messages' = RemainingMessages(m, consume)
       /\ grants' = [grants EXCEPT ![i] = IF exact THEN ng ELSE @]
       /\ candidateActive' = [candidateActive EXCEPT ![i] = IF wins \/ adopt THEN FALSE ELSE @]
       /\ vote' = [vote EXCEPT ![i] = IF wins THEN cv ELSE IF adopt THEN stripped ELSE @]
       /\ role' = [role EXCEPT ![i] = IF wins THEN "Leader"
                                         ELSE IF adopt THEN RoleFrom(i, stripped, effectiveConfig[i])
                                         ELSE @]
       /\ leaderActive' = [leaderActive EXCEPT ![i] = IF wins THEN TRUE
                                                      ELSE IF adopt /\ stripped.node /= i THEN FALSE
                                                      ELSE @]
       /\ leaderVote' = [leaderVote EXCEPT ![i] = IF wins THEN cv ELSE @]
       /\ leaderCertified' = [leaderCertified EXCEPT ![i] = IF wins THEN TRUE ELSE @]
       /\ leaderConfig' = [leaderConfig EXCEPT ![i] = IF wins THEN candidateConfig[i] ELSE @]
       /\ leaderGrants' = [leaderGrants EXCEPT ![i] = IF wins THEN ng ELSE @]
       /\ votePersistPending' = [votePersistPending EXCEPT ![i] = IF wins \/ adopt THEN TRUE ELSE @]
       /\ sendVotePending' = [sendVotePending EXCEPT ![i] = IF wins \/ adopt THEN FALSE ELSE @]
       \* REPAIR (validation round 1): establish_leader -> update_vote(committed)
       \* installs the committed vote with leader_lease (vote_handler/mod.rs:121-133);
       \* adopting a stripped (uncommitted) vote installs a zero lease.
       /\ leaseValid' = [leaseValid EXCEPT ![i] = IF wins THEN TRUE ELSE IF adopt THEN FALSE ELSE @]
       /\ lastLog' = [lastLog EXCEPT ![i] = IF wins /\ newIndex <= MaxLogIndex
                                              THEN Log(cv.term, cv.node, newIndex) ELSE @]
       /\ logFlushPending' = [logFlushPending EXCEPT ![i] = IF wins /\ newIndex <= MaxLogIndex
                                                                THEN TRUE ELSE @]
       /\ seenGreaterLog' = [seenGreaterLog EXCEPT ![i] =
                                IF candidateActive[i] /\ ~exact /\ LogLT(lastLog[i], m.lastLog)
                                THEN TRUE ELSE @]
       \* UPDATE-MAP
       \* code: openraft/src/engine/engine_impl.rs:508 (update_vote -> become_following)
       \*       and :855-881 (establish_leader leaves pre_candidate untouched)
       \* update: Update!InteractionActions (DeliverVoteResponse)
       \* FIXCHECK (sanity control only, not the reference): establish_leader cancels the round
       /\ preCandidateActive' = [preCandidateActive EXCEPT ![i] =
                                     IF wins \/ (adopt /\ Follows(i, stripped)) THEN FALSE ELSE @]
    /\ UNCHANGED <<durableVote, replyPending, replyMessage,
                    candidateVote, candidateConfig, sentVoteReq, durableLastLog,
                    configVars, crashed, preCandidateVote, preCandidateConfig, preGrants>>

DeliverVoteResponse(m) ==
    /\ m \in messages
    /\ HandleVoteResponse(m.dest, m, TRUE)

(***************************************************************************
 * Pre-Vote response handling (runtime filter + engine).                   *
 * - RaftCore delivers it only while a pre-candidate exists whose leader   *
 *   id equals the notification's candidate_vote leader id                 *
 *   (raft_core.rs:1803-1820, 2067-2090); otherwise it is dropped.         *
 * - Engine::handle_pre_vote_resp: granted -> grant_by(target); a quorum   *
 *   calls elect(). Rejected with a greater responder log -> set the       *
 *   greater-log back-off. Never updates the local vote otherwise.         *
 * openraft/src/engine/engine_impl.rs:516-554                              *
 *************************************************************************)
\* UPDATE-MAP
\* code: openraft/src/engine/engine_impl.rs:516-554, openraft/src/core/raft_core.rs:1803-1820
\* update: Update!AffectedActions (DeliverPreVoteResponse), Update!PreVoteWinStep
HandlePreVoteResponse(i, m, consume) ==
    /\ ~crashed[i]
    /\ m.kind = "PreVoteResp"
    /\ m.dest = i
    /\ ~votePersistPending[i]
    /\ LET match == /\ preCandidateActive[i]
                    /\ m.vote.term = preCandidateVote[i].term
                    /\ m.vote.node = preCandidateVote[i].node
           ng == preGrants[i] \cup {m.source}
           wins == match /\ m.granted /\ IsQuorum(preCandidateConfig[i], ng)
       IN
       IF wins
       THEN \* engine_impl.rs:535-540: quorum would grant -> self.elect()
            DoElect(i, FALSE, RemainingMessages(m, consume), FALSE)
       ELSE /\ messages' = RemainingMessages(m, consume)
            /\ preGrants' = [preGrants EXCEPT ![i] = IF match /\ m.granted THEN ng ELSE @]
            /\ seenGreaterLog' = [seenGreaterLog EXCEPT ![i] =
                                     IF match /\ ~m.granted /\ LogLT(lastLog[i], m.lastLog)
                                     THEN TRUE ELSE @]
            /\ UNCHANGED <<role, crashed, voteVars, candidateVars, leaderVars,
                            logVars, configVars, preCandidateActive,
                            preCandidateVote, preCandidateConfig>>

DeliverPreVoteResponse(m) ==
    /\ m \in messages
    /\ HandlePreVoteResponse(m.dest, m, TRUE)

(***************************************************************************
 * Ordinary coherent membership evolution: uniform old -> joint old/new -> *
 * uniform new. Append updates effective immediately and leaves cached      *
 * Leader state intact.                                                     *
 * openraft/src/raft_state/membership_state/mod.rs:183-203                  *
 * openraft/src/membership/membership.rs:280-339                            *
 *************************************************************************)
AppendJointConfig(i, target) ==
    /\ ~crashed[i]
    /\ leaderActive[i]
    /\ vote[i].committed /\ vote[i].node = i
    /\ committedConfigIndex[i] = effectiveConfigIndex[i]
    /\ Len(effectiveConfig[i]) = 1
    /\ target \subseteq Server /\ target /= {}
    /\ target /= effectiveConfig[i][1]
    /\ effectiveConfigIndex[i] < MaxLogIndex
    /\ lastLog[i].index < MaxLogIndex
    /\ committedConfig' = [committedConfig EXCEPT ![i] = effectiveConfig[i]]
    /\ committedConfigIndex' = [committedConfigIndex EXCEPT ![i] = effectiveConfigIndex[i]]
    /\ effectiveConfig' = [effectiveConfig EXCEPT ![i] = <<effectiveConfig[i][1], target>>]
    /\ effectiveConfigIndex' = [effectiveConfigIndex EXCEPT ![i] = @ + 1]
    /\ lastLog' = [lastLog EXCEPT ![i] = Log(vote[i].term, vote[i].node, lastLog[i].index + 1)]
    /\ logFlushPending' = [logFlushPending EXCEPT ![i] = TRUE]
    /\ UNCHANGED <<runtimeVars, voteVars, candidateVars, leaderVars,
                    durableLastLog, durableConfig, durableConfigIndex, messages,
                    preVoteVars>>

AppendUniformConfig(i) ==
    /\ ~crashed[i]
    /\ leaderActive[i]
    /\ vote[i].committed /\ vote[i].node = i
    /\ committedConfigIndex[i] = effectiveConfigIndex[i]
    /\ Len(effectiveConfig[i]) = 2
    /\ effectiveConfigIndex[i] < MaxLogIndex
    /\ lastLog[i].index < MaxLogIndex
    /\ committedConfig' = [committedConfig EXCEPT ![i] = effectiveConfig[i]]
    /\ committedConfigIndex' = [committedConfigIndex EXCEPT ![i] = effectiveConfigIndex[i]]
    /\ effectiveConfig' = [effectiveConfig EXCEPT ![i] = <<effectiveConfig[i][2]>>]
    /\ effectiveConfigIndex' = [effectiveConfigIndex EXCEPT ![i] = @ + 1]
    /\ lastLog' = [lastLog EXCEPT ![i] = Log(vote[i].term, vote[i].node, lastLog[i].index + 1)]
    /\ logFlushPending' = [logFlushPending EXCEPT ![i] = TRUE]
    /\ UNCHANGED <<runtimeVars, voteVars, candidateVars, leaderVars,
                    durableLastLog, durableConfig, durableConfigIndex, messages,
                    preVoteVars>>

(***************************************************************************
 * Commit copies effective to committed. Cached role refresh is separate.   *
 * openraft/src/raft_state/membership_state/mod.rs:121-147                  *
 *************************************************************************)
CommitMembership(i) ==
    /\ ~crashed[i]
    /\ committedConfigIndex[i] < effectiveConfigIndex[i]
    /\ committedConfig' = [committedConfig EXCEPT ![i] = effectiveConfig[i]]
    /\ committedConfigIndex' = [committedConfigIndex EXCEPT ![i] = effectiveConfigIndex[i]]
    /\ UNCHANGED <<runtimeVars, voteVars, candidateVars, leaderVars, logVars,
                    effectiveConfig, effectiveConfigIndex, durableConfig,
                    durableConfigIndex, messages, preVoteVars>>

(***************************************************************************
 * Engine::refresh_server_state -> update_internal_server_state; a node    *
 * that is now following runs become_following(), clearing leader,         *
 * candidate and pre-candidate.                                            *
 * openraft/src/engine/engine_impl.rs:660-673                              *
 *************************************************************************)
RefreshServerState(i) ==
    /\ ~crashed[i]
    /\ committedConfigIndex[i] = effectiveConfigIndex[i]
    /\ role' = [role EXCEPT ![i] = RoleFrom(i, vote[i], effectiveConfig[i])]
    /\ leaderActive' = [leaderActive EXCEPT ![i] = IF RoleFrom(i, vote[i], effectiveConfig[i]) = "Leader"
                                                    THEN @ ELSE FALSE]
    /\ candidateActive' = [candidateActive EXCEPT ![i] =
                              IF RoleFrom(i, vote[i], effectiveConfig[i]) = "Candidate" THEN @ ELSE FALSE]
    \* UPDATE-MAP
    \* code: openraft/src/engine/handler/vote_handler/mod.rs:244
    \* update: Update!InteractionActions (RefreshServerState)
    /\ preCandidateActive' = [preCandidateActive EXCEPT ![i] =
                                 IF Follows(i, vote[i]) THEN FALSE ELSE @]
    /\ UNCHANGED <<crashed, seenGreaterLog, voteVars, candidateVote,
                    candidateConfig, grants, sentVoteReq, leaderVote,
                    leaderCertified, leaderConfig, leaderGrants, logVars,
                    configVars, messages, preCandidateVote, preCandidateConfig,
                    preGrants>>

FlushLog(i) ==
    /\ ~crashed[i]
    /\ logFlushPending[i]
    /\ durableLastLog' = [durableLastLog EXCEPT ![i] = lastLog[i]]
    /\ logFlushPending' = [logFlushPending EXCEPT ![i] = FALSE]
    /\ durableConfig' = [durableConfig EXCEPT ![i] = effectiveConfig[i]]
    /\ durableConfigIndex' = [durableConfigIndex EXCEPT ![i] = effectiveConfigIndex[i]]
    /\ UNCHANGED <<runtimeVars, voteVars, candidateVars, leaderVars, lastLog,
                    committedConfig, committedConfigIndex, effectiveConfig,
                    effectiveConfigIndex, messages, preVoteVars>>

(***************************************************************************
 * A leader may dispatch replication after the committed vote is durable.   *
 * Append return makes the log readable before its later flush callback.    *
 * openraft/src/core/raft_core.rs:2235-2273                                 *
 *************************************************************************)
SendAppendEntries(i, j) ==
    /\ ~crashed[i]
    /\ leaderActive[i]
    /\ vote[i].committed /\ vote[i].node = i
    /\ VoteLE(vote[i], durableVote[i])
    /\ j \in ConfigVoters(effectiveConfig[i]) \ {i}
    /\ messages' = messages \cup
          {Message("Append", i, j, vote[i], lastLog[i], FALSE, FALSE)}
    /\ UNCHANGED <<runtimeVars, voteVars, candidateVars, leaderVars, logVars,
                    configVars, preVoteVars>>

(***************************************************************************
 * Engine::append_entries first runs update_vote(); an accepted vote of     *
 * another node runs become_following() and now clears the pre-candidate.  *
 * openraft/src/engine/engine_impl.rs:560-602                               *
 *************************************************************************)
HandleAppendEntries(i, m, consume) ==
    /\ ~crashed[i]
    /\ m.kind = "Append"
    /\ m.dest = i
    /\ VoteLE(vote[i], m.vote)
    /\ ~votePersistPending[i]
    /\ LET strict == VoteLT(vote[i], m.vote) IN
       /\ vote' = [vote EXCEPT ![i] = m.vote]
       /\ votePersistPending' = [votePersistPending EXCEPT ![i] = strict]
       /\ leaseValid' = [leaseValid EXCEPT ![i] = m.vote.committed]
       /\ role' = [role EXCEPT ![i] = RoleFrom(i, m.vote, effectiveConfig[i])]
       /\ candidateActive' = [candidateActive EXCEPT ![i] = IF m.vote.node = i THEN @ ELSE FALSE]
       /\ leaderActive' = [leaderActive EXCEPT ![i] = IF m.vote.node = i /\ m.vote.committed
                                                      THEN TRUE ELSE FALSE]
       /\ leaderVote' = [leaderVote EXCEPT ![i] = IF m.vote.node = i /\ m.vote.committed
                                                  THEN m.vote ELSE @]
       \* UPDATE-MAP
       \* code: openraft/src/engine/handler/vote_handler/mod.rs:244
       \* update: Update!InteractionActions (DeliverAppendEntries)
       /\ preCandidateActive' = [preCandidateActive EXCEPT ![i] =
                                    IF Follows(i, m.vote) THEN FALSE ELSE @]
    /\ messages' = RemainingMessages(m, consume)
    /\ UNCHANGED <<crashed, seenGreaterLog, durableVote, replyPending,
                    replyMessage, sendVotePending, candidateVote,
                    candidateConfig, grants, sentVoteReq, leaderCertified,
                    leaderConfig, leaderGrants, logVars, configVars,
                    preCandidateVote, preCandidateConfig, preGrants>>

DeliverAppendEntries(m) ==
    /\ m \in messages
    /\ HandleAppendEntries(m.dest, m, TRUE)

ExpireLease(i) ==
    /\ leaseValid[i]
    /\ leaseValid' = [leaseValid EXCEPT ![i] = FALSE]
    /\ UNCHANGED <<runtimeVars, vote, durableVote, votePersistPending,
                    replyPending, replyMessage, sendVotePending, candidateVars,
                    leaderVars, logVars, configVars, messages, preVoteVars>>

DropMessage(m) ==
    /\ m \in messages
    /\ messages' = messages \ {m}
    /\ UNCHANGED <<runtimeVars, voteVars, candidateVars, leaderVars, logVars,
                    configVars, preVoteVars>>

(***************************************************************************
 * Crash keeps durable variables. Restart reconstructs vote/log/config and  *
 * clears candidate, pre-candidate, command, lease, and greater-log state.  *
 * openraft/src/storage/helper.rs:83-223,313-399                            *
 * openraft/src/engine/engine_impl.rs:107-120,168-214                       *
 *************************************************************************)
Crash(i) ==
    /\ ~crashed[i]
    /\ crashed' = [crashed EXCEPT ![i] = TRUE]
    /\ UNCHANGED <<role, seenGreaterLog, voteVars, candidateVars, leaderVars,
                    logVars, configVars, messages, preVoteVars>>

Restart(i) ==
    /\ crashed[i]
    /\ crashed' = [crashed EXCEPT ![i] = FALSE]
    /\ vote' = [vote EXCEPT ![i] = durableVote[i]]
    /\ votePersistPending' = [votePersistPending EXCEPT ![i] = FALSE]
    /\ replyPending' = [replyPending EXCEPT ![i] = FALSE]
    /\ replyMessage' = [replyMessage EXCEPT ![i] = NoMessage]
    /\ sendVotePending' = [sendVotePending EXCEPT ![i] = FALSE]
    /\ leaseValid' = [leaseValid EXCEPT ![i] = FALSE]
    /\ candidateActive' = [candidateActive EXCEPT ![i] = FALSE]
    /\ candidateVote' = [candidateVote EXCEPT ![i] = durableVote[i]]
    /\ candidateConfig' = [candidateConfig EXCEPT ![i] = durableConfig[i]]
    /\ grants' = [grants EXCEPT ![i] = {}]
    /\ sentVoteReq' = [sentVoteReq EXCEPT ![i] = {}]
    /\ leaderActive' = [leaderActive EXCEPT ![i] =
          durableVote[i].committed /\ durableVote[i].node = i /\ InConfig(i, durableConfig[i])]
    /\ leaderVote' = [leaderVote EXCEPT ![i] = durableVote[i]]
    /\ leaderCertified' = [leaderCertified EXCEPT ![i] = FALSE]
    /\ leaderConfig' = [leaderConfig EXCEPT ![i] = durableConfig[i]]
    /\ leaderGrants' = [leaderGrants EXCEPT ![i] = {}]
    /\ lastLog' = [lastLog EXCEPT ![i] = durableLastLog[i]]
    /\ logFlushPending' = [logFlushPending EXCEPT ![i] = FALSE]
    /\ committedConfig' = [committedConfig EXCEPT ![i] = durableConfig[i]]
    /\ effectiveConfig' = [effectiveConfig EXCEPT ![i] = durableConfig[i]]
    /\ committedConfigIndex' = [committedConfigIndex EXCEPT ![i] = durableConfigIndex[i]]
    /\ effectiveConfigIndex' = [effectiveConfigIndex EXCEPT ![i] = durableConfigIndex[i]]
    \* startup() restores an established self vote only when leader restore is
    \* enabled; every other persisted voter starts in Follower, even when its
    \* uncommitted vote still names itself.
    /\ role' = [role EXCEPT ![i] =
          IF durableVote[i].committed /\ durableVote[i].node = i /\ InConfig(i, durableConfig[i])
          THEN "Leader"
          ELSE IF InConfig(i, durableConfig[i]) THEN "Follower" ELSE "Learner"]
    /\ seenGreaterLog' = [seenGreaterLog EXCEPT ![i] = FALSE]
    \* UPDATE-MAP
    \* code: openraft/src/engine/engine_impl.rs:117 (Engine::new: pre_candidate: None)
    \* update: Update!InteractionActions (Restart)
    /\ preCandidateActive' = [preCandidateActive EXCEPT ![i] = FALSE]
    /\ preGrants' = [preGrants EXCEPT ![i] = {}]
    /\ UNCHANGED <<durableVote, durableLastLog, durableConfig, durableConfigIndex,
                    messages, preCandidateVote, preCandidateConfig>>

Next ==
    \/ \E i \in Server : TickElect(i) \/ ExternalElect(i) \/ StartTransferElection(i)
                           \/ ExternalPreElect(i)
    \/ \E i \in Server : PersistVote(i) \/ FinishVoteBroadcast(i) \/ FlushLog(i)
    \/ \E i \in Server : ExpireLease(i) \/ Restart(i) \/ RefreshServerState(i)
    \/ \E i \in Server, j \in Server : SendVoteRequest(i, j) \/ SendAppendEntries(i, j)
    \/ \E m \in messages : DeliverVoteRequest(m) \/ DeliverVoteResponse(m)
                              \/ DeliverAppendEntries(m) \/ DropMessage(m)
                              \/ DeliverPreVoteRequest(m) \/ DeliverPreVoteResponse(m)
    \/ \E i \in Server, target \in SUBSET Server : AppendJointConfig(i, target)
    \/ \E i \in Server : AppendUniformConfig(i) \/ CommitMembership(i) \/ Crash(i)

Spec == Init /\ [][Next]_vars

VoteSet == [term : 0..MaxTerm, node : Server, committed : BOOLEAN]

TypeOK ==
    /\ role \in [Server -> {"Learner", "Follower", "Candidate", "Leader"}]
    /\ vote \in [Server -> VoteSet]
    /\ durableVote \in [Server -> VoteSet]
    /\ votePersistPending \in [Server -> BOOLEAN]
    /\ replyPending \in [Server -> BOOLEAN]
    /\ sendVotePending \in [Server -> BOOLEAN]
    /\ leaseValid \in [Server -> BOOLEAN]
    /\ candidateActive \in [Server -> BOOLEAN]
    /\ candidateVote \in [Server -> VoteSet]
    /\ \A i \in Server : IsConfig(candidateConfig[i])
    /\ grants \in [Server -> SUBSET Server]
    /\ sentVoteReq \in [Server -> SUBSET Server]
    /\ leaderActive \in [Server -> BOOLEAN]
    /\ leaderVote \in [Server -> VoteSet]
    /\ leaderCertified \in [Server -> BOOLEAN]
    /\ \A i \in Server : IsConfig(leaderConfig[i])
    /\ leaderGrants \in [Server -> SUBSET Server]
    /\ \A i \in Server :
          /\ lastLog[i].present \in BOOLEAN
          /\ lastLog[i].term \in 0..MaxTerm
          /\ lastLog[i].node \in Server
          /\ lastLog[i].index \in 0..MaxLogIndex
          /\ durableLastLog[i].present \in BOOLEAN
          /\ durableLastLog[i].term \in 0..MaxTerm
          /\ durableLastLog[i].node \in Server
          /\ durableLastLog[i].index \in 0..MaxLogIndex
    /\ logFlushPending \in [Server -> BOOLEAN]
    /\ \A i \in Server : IsConfig(committedConfig[i]) /\ IsConfig(effectiveConfig[i])
                           /\ IsConfig(durableConfig[i])
    /\ committedConfigIndex \in [Server -> 0..MaxLogIndex]
    /\ effectiveConfigIndex \in [Server -> 0..MaxLogIndex]
    /\ durableConfigIndex \in [Server -> 0..MaxLogIndex]
    /\ crashed \in [Server -> BOOLEAN]
    /\ seenGreaterLog \in [Server -> BOOLEAN]
    /\ preCandidateActive \in [Server -> BOOLEAN]
    /\ preCandidateVote \in [Server -> VoteSet]
    /\ \A i \in Server : IsConfig(preCandidateConfig[i])
    /\ preGrants \in [Server -> SUBSET Server]
    /\ \A m \in messages :
          /\ m.kind \in {"VoteReq", "VoteResp", "Append", "PreVoteReq", "PreVoteResp"}
          /\ m.source \in Server /\ m.dest \in Server
          /\ m.vote.term \in 0..MaxTerm /\ m.vote.node \in Server
          /\ m.vote.committed \in BOOLEAN
          /\ m.lastLog.present \in BOOLEAN
          /\ m.lastLog.term \in 0..MaxTerm
          /\ m.lastLog.node \in Server
          /\ m.lastLog.index \in 0..MaxLogIndex
          /\ m.granted \in BOOLEAN /\ m.transfer \in BOOLEAN

DurableVoteNotAhead == \A i \in Server : VoteLE(durableVote[i], vote[i])
DurableLogNotAhead == \A i \in Server : LogLE(durableLastLog[i], lastLog[i])

VoteRequestAfterDurable ==
    \A m \in messages : m.kind = "VoteReq" => VoteLE(m.vote, durableVote[m.source])

GrantedResponseAfterDurable ==
    \A m \in messages : m.kind = "VoteResp" /\ m.granted => VoteLE(m.vote, durableVote[m.source])

LeaderRoleHasCommittedSelfVote ==
    \A i \in Server : role[i] = "Leader" => vote[i].committed /\ vote[i].node = i

CandidateRoleHasPendingSelfVote ==
    \A i \in Server : role[i] = "Candidate" => ~vote[i].committed /\ vote[i].node = i

CertifiedLeaderHasFrozenQuorum ==
    \A i \in Server : leaderCertified[i] => IsQuorum(leaderConfig[i], leaderGrants[i])

MembershipAtMostOneOutstanding ==
    \A i \in Server :
        /\ committedConfigIndex[i] <= effectiveConfigIndex[i]
        /\ effectiveConfigIndex[i] <= committedConfigIndex[i] + 1

NoForgedMessageEndpoints ==
    \A m \in messages : m.source \in Server /\ m.dest \in Server

=============================================================================
