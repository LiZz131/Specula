------------------------------ MODULE base ------------------------------
(***************************************************************************
 * OpenRaft election reference model, updated for the source revision that  *
 * adds the optional Pre-Vote round (synthetic commit `update`).            *
 *                                                                         *
 * Source boundary (new revision): engine/engine_impl.rs,                  *
 * engine/handler/vote_handler/mod.rs, core/raft_core.rs,                  *
 * raft_state/membership_state/mod.rs, and proposer/candidate.rs.          *
 *                                                                         *
 * The prior V0 suite (exact-old) is the starting point. Every change      *
 * against it is marked with an UPDATE-MAP comment that names the source   *
 * change and the corresponding Update.tla focus, or with a REPAIR comment *
 * for an implementation-backed correction of the old abstraction.         *
 *************************************************************************)

EXTENDS Integers, Naturals, FiniteSets, Sequences, TLC

CONSTANTS Server, NodeOrder, MaxTerm, MaxLogIndex, InitialConfig

\* UPDATE-MAP
\* code: openraft/src/config/config.rs:Config::enable_pre_vote/get_enable_pre_vote,
\*       openraft/src/config/runtime_config.rs:RuntimeConfig::enable_pre_vote,
\*       openraft/src/raft/runtime_config_handle.rs:RuntimeConfigHandle::pre_vote
\* update: Update!AffectedActions (tick branch selection), Update cfgs
\* "Disabled": the default (None -> false); the timer always elects directly.
\* "Enabled":  the timer runs a Pre-Vote round for multi-voter configs.
\* "Runtime":  the flag is an AtomicBool toggled at run time; each tick may
\*             observe either value (nondeterministic union).
CONSTANT PreVoteSetting

ReferenceServer == {"1", "2", "3"}
ReferenceNodeOrder == <<"1", "2", "3">>
ReferenceInitialConfig == {"1", "2", "3"}

ASSUME /\ Server /= {}
       /\ Len(NodeOrder) = Cardinality(Server)
       /\ {NodeOrder[k] : k \in 1..Len(NodeOrder)} = Server
       /\ InitialConfig \subseteq Server
       /\ InitialConfig /= {}
       /\ MaxTerm \in Nat \ {0}
       /\ MaxLogIndex \in Nat \ {0}
       /\ PreVoteSetting \in {"Disabled", "Enabled", "Runtime"}

FirstNode == NodeOrder[1]

DefaultVote(i) == [term |-> 0, node |-> i, committed |-> FALSE]
Vote(t, n, c) == [term |-> t, node |-> n, committed |-> c]

NoLog(i) == [present |-> FALSE, term |-> 0, node |-> i, index |-> 0]
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

\* REPAIR (implementation-backed; inherited V0 defect): NoLog(i) carries a
\* node tag only so that Trace.tla can compare the harness encoding of None.
\* Option<LogId> compares None == None (log_id/mod.rs:18-61), so two absent
\* logs are equal whatever their tag. V0 used `a = b`, which made
\* LogLE(NoLog(j), NoLog(i)) FALSE for i /= j: no empty-log node could grant
\* a remote vote, and no 3-voter election could succeed from Init.
LogEq(a, b) == (~a.present /\ ~b.present) \/ a = b
LogLE(a, b) == LogEq(a, b) \/ LogLT(a, b)

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

\* UPDATE-MAP
\* code: openraft/src/core/raft_msg/mod.rs:RaftMsg::RequestPreVote,
\*       openraft/src/core/notification.rs:Notification::PreVoteResponse,
\*       openraft/src/network/v2/network.rs:RaftNetworkV2::pre_vote
\* update: Update!AffectedActions (DeliverPreVoteRequest/DeliverPreVoteResponse)
\* "PreVoteReq" carries the hypothetical next-term vote and the pre-candidate
\* last-log snapshot. "PreVoteResp" carries, in its `vote` field, the
\* pre-candidate vote that the runtime correlates (Notification::PreVoteResponse
\* candidate_vote); the responder's own vote in VoteResponse is never consumed
\* by Engine::handle_pre_vote_resp and is validated only in Trace.tla.
MessageKinds == {"VoteReq", "VoteResp", "Append", "PreVoteReq", "PreVoteResp"}

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
    \* code: openraft/src/engine/engine_impl.rs:Engine::pre_candidate,
    \*       Engine::new_pre_candidate, proposer/candidate.rs:Candidate
    \* update: Update!PreVoteVisible, Update!TickPreVoteNeverDeposesLeader
    \* Volatile Pre-Vote tracker: hypothetical vote, frozen effective
    \* membership, and granters. It is never persisted.
    preCandidateActive,
    preCandidateVote,
    preCandidateConfig,
    preGrants,
    \* Ghost/history variable, not implementation state: TRUE when the
    \* in-flight Pre-Vote round was started by the election timer
    \* (RaftCore::handle_tick_election) rather than by
    \* ExternalCommand::Elect { pre_vote: true }. Only Update.tla reads it.
    preCandidateByTick

voteVars == <<vote, durableVote, votePersistPending, replyPending, replyMessage,
              sendVotePending, leaseValid>>
candidateVars == <<candidateActive, candidateVote, candidateConfig, grants, sentVoteReq>>
preVars == <<preCandidateActive, preCandidateVote, preCandidateConfig, preGrants,
             preCandidateByTick>>
leaderVars == <<leaderActive, leaderVote, leaderCertified, leaderConfig, leaderGrants>>
logVars == <<lastLog, durableLastLog, logFlushPending>>
configVars == <<committedConfig, committedConfigIndex, effectiveConfig,
                effectiveConfigIndex, durableConfig, durableConfigIndex>>
runtimeVars == <<role, crashed, seenGreaterLog>>
vars == <<runtimeVars, voteVars, candidateVars, preVars, leaderVars, logVars,
          configVars, messages>>

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
    /\ preCandidateActive = [i \in Server |-> FALSE]
    /\ preCandidateVote = vote
    /\ preCandidateConfig = [i \in Server |-> <<InitialConfig>>]
    /\ preGrants = [i \in Server |-> {}]
    /\ preCandidateByTick = [i \in Server |-> FALSE]
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

(***************************************************************************
 * Dropping Engine::pre_candidate (assign None). Inactive slots are reset   *
 * to a canonical value so that dead tracker contents do not split states.  *
 *************************************************************************)
\* UPDATE-MAP
\* code: openraft/src/engine/engine_impl.rs:do_elect (`self.pre_candidate = None`),
\*       openraft/src/engine/handler/vote_handler/mod.rs:become_following
\*       (`*self.pre_candidate = None`), Engine::new (restart)
\* update: Update!InteractionActions, Update!PreVoteProbeIsNextTerm
PreClearIf(i, clear) ==
    /\ preCandidateActive' = [preCandidateActive EXCEPT ![i] = IF clear THEN FALSE ELSE @]
    /\ preCandidateVote' = [preCandidateVote EXCEPT ![i] = IF clear THEN DefaultVote(i) ELSE @]
    /\ preCandidateConfig' = [preCandidateConfig EXCEPT ![i] = IF clear THEN <<InitialConfig>> ELSE @]
    /\ preGrants' = [preGrants EXCEPT ![i] = IF clear THEN {} ELSE @]
    /\ preCandidateByTick' = [preCandidateByTick EXCEPT ![i] = IF clear THEN FALSE ELSE @]

(***************************************************************************
 * Engine::do_elect. Candidate membership and last log are snapshotted      *
 * before the pending self vote is installed. SaveVote is queued before     *
 * SendVote. The new revision first drops any in-flight Pre-Vote round.     *
 * openraft/src/engine/engine_impl.rs:262-289 (do_elect)                    *
 * openraft/src/engine/engine_impl.rs:122-142 (new_candidate)              *
 * openraft/src/engine/handler/vote_handler/mod.rs:106-151 (update_vote)    *
 * openraft/src/raft_state/mod.rs:416-440 (calc_server_state)               *
 *                                                                         *
 * Retained V0 abstraction: an election is not started while a previous     *
 * vote save or a flush-gated reply is still pending. The implementation   *
 * does not wait; the model only delays such an election until the earlier *
 * PersistVote step, which is always enabled for a live node.               *
 *                                                                         *
 * `sglPost` is the post-value of seen_greater_log: Engine::do_elect does   *
 * not touch it; only the timer path resets it before electing.             *
 * Messages are left to the caller.                                         *
 *************************************************************************)
\* UPDATE-MAP
\* code: openraft/src/engine/engine_impl.rs:262-264 (pre_candidate = None)
\* update: Update!AffectedActions (DoElect reached from every election path)
DoElectCore(i, transfer, sglPost) ==
    /\ ~crashed[i]
    /\ vote[i].term < MaxTerm
    /\ ~votePersistPending[i]
    /\ ~replyPending[i]
    /\ LET nv == Vote(vote[i].term + 1, i, FALSE) IN
       /\ vote' = [vote EXCEPT ![i] = nv]
       /\ candidateActive' = [candidateActive EXCEPT ![i] = TRUE]
       /\ candidateVote' = [candidateVote EXCEPT ![i] = nv]
       \* engine_impl.rs:288 update_server_state_if_changed -> calc_server_state
       /\ role' = [role EXCEPT ![i] = RoleFrom(i, nv, effectiveConfig[i])]
    /\ candidateConfig' = [candidateConfig EXCEPT ![i] = effectiveConfig[i]]
    /\ grants' = [grants EXCEPT ![i] = {}]
    /\ sentVoteReq' = [sentVoteReq EXCEPT ![i] = {}]
    /\ votePersistPending' = [votePersistPending EXCEPT ![i] = TRUE]
    /\ sendVotePending' = [sendVotePending EXCEPT ![i] = TRUE]
    /\ leaseValid' = [leaseValid EXCEPT ![i] = FALSE]
    /\ seenGreaterLog' = [seenGreaterLog EXCEPT ![i] = sglPost]
    \* engine_impl.rs:263-264 "A real election supersedes any in-flight Pre-Vote round."
    /\ PreClearIf(i, TRUE)
    /\ UNCHANGED <<durableVote, replyPending, replyMessage, leaderVars,
                    logVars, configVars, crashed>>

DoElect(i, transfer, sglPost) ==
    /\ DoElectCore(i, transfer, sglPost)
    /\ UNCHANGED messages

(***************************************************************************
 * RaftCore-level elections that check `is_voter` before calling the       *
 * engine: ExternalCommand::Elect (raft_core.rs:1683-1695) and leadership   *
 * transfer. Neither resets seen_greater_log.                               *
 *************************************************************************)
\* REPAIR (independent of the source delta, implementation-backed):
\* V0 reset seenGreaterLog on every election start; the exact-old and new
\* ExternalCommand::Elect paths call Engine::elect without reset_greater_log
\* (raft_core.rs:1683-1695); only handle_tick_election resets it
\* (raft_core.rs:2026-2027).
StartElection(i, transfer) ==
    /\ InConfig(i, effectiveConfig[i])
    /\ DoElect(i, transfer, seenGreaterLog[i])

ExternalElect(i) == StartElection(i, FALSE)
StartTransferElection(i) == StartElection(i, TRUE)

(***************************************************************************
 * Engine::pre_elect. The hypothetical vote is (term + 1, self). The        *
 * pre-candidate freezes the effective membership and last log, grants      *
 * itself, and either elects at once (self is a quorum) or queues           *
 * SendPreVote. No vote, role, lease, or persistence change.                *
 * openraft/src/engine/engine_impl.rs:291-322 (pre_elect)                   *
 * openraft/src/engine/engine_impl.rs:144-165 (new_pre_candidate)          *
 *                                                                         *
 * SendPreVote has no IO condition (engine/command.rs: condition None) and  *
 * RaftCore::run_engine_commands drains it right after the engine event;    *
 * spawn_parallel_vote_requests (raft_core.rs:1384-1478) then sends the     *
 * fixed request to every other effective voter. The model emits these     *
 * requests in the same step. Delay, reordering, and loss remain possible   *
 * through the asynchronous message set and DropMessage.                    *
 *************************************************************************)
\* UPDATE-MAP
\* code: openraft/src/engine/engine_impl.rs:291-322, raft_core.rs:2339-2343
\* update: Update!AffectedActions (MCTickPreElect, MCExternalPreElect)
PreElect(i, byTick, sglPost) ==
    /\ ~crashed[i]
    \* bound: the probed term must stay inside the finite term domain
    /\ vote[i].term < MaxTerm
    /\ LET pv == Vote(vote[i].term + 1, i, FALSE)
           cfg == effectiveConfig[i]
       IN
       IF IsQuorum(cfg, {i})
       THEN \* engine_impl.rs:308-315: a single voter reaches its Pre-Vote
            \* quorum at once and calls elect(); do_elect drops the tracker.
            DoElect(i, FALSE, sglPost)
       ELSE
            /\ preCandidateActive' = [preCandidateActive EXCEPT ![i] = TRUE]
            /\ preCandidateVote' = [preCandidateVote EXCEPT ![i] = pv]
            /\ preCandidateConfig' = [preCandidateConfig EXCEPT ![i] = cfg]
            /\ preGrants' = [preGrants EXCEPT ![i] = {i}]
            /\ preCandidateByTick' = [preCandidateByTick EXCEPT ![i] = byTick]
            \* engine_impl.rs:317-321 SendPreVote { VoteRequest::new(pre_vote, last_log_id) }
            /\ messages' = messages \cup
                  {Message("PreVoteReq", i, j, pv, lastLog[i], FALSE, FALSE) :
                       j \in ConfigVoters(cfg) \ {i}}
            /\ seenGreaterLog' = [seenGreaterLog EXCEPT ![i] = sglPost]
            /\ UNCHANGED <<role, crashed, voteVars, candidateVars, leaderVars,
                            logVars, configVars>>

(***************************************************************************
 * RaftCore::handle_tick_election (raft_core.rs:1959-2036).                 *
 *  - skip a cached Leader and a non-voter;                                 *
 *  - single voter: skip while a candidate exists, else elect directly;     *
 *  - multiple voters: require election-timeout expiry, which implies the   *
 *    leader lease has expired (is_expired(now, election_timeout));         *
 *  - Pre-Vote iff the runtime flag is on and there is more than one voter; *
 *    a fresh in-flight round is skipped and a stale one restarted, which   *
 *    the time abstraction admits nondeterministically;                     *
 *  - reset seen_greater_log, then pre_elect() or elect().                  *
 *************************************************************************)
\* REPAIR (independent of the source delta, implementation-backed):
\* V0 TickElect omitted the single-voter "candidate already in progress"
\* skip (raft_core.rs:1988-1994, also present in exact-old) and allowed a
\* multi-voter tick while the leader lease was still valid, although the
\* tick requires local_vote.is_expired(now, election_timeout)
\* (raft_core.rs:1996-2008).
VoterCount(i) == Cardinality(ConfigVoters(effectiveConfig[i]))

TickGuard(i) ==
    /\ role[i] /= "Leader"
    /\ InConfig(i, effectiveConfig[i])
    /\ IF VoterCount(i) = 1
       THEN ~candidateActive[i]
       ELSE ~leaseValid[i]

\* UPDATE-MAP
\* code: openraft/src/core/raft_core.rs:2010-2035
\* update: Update!AffectedActions (MCTickElect, MCTickPreElect)
TickElect(i) ==
    /\ TickGuard(i)
    /\ \/ VoterCount(i) = 1
       \/ PreVoteSetting \in {"Disabled", "Runtime"}
    /\ DoElect(i, FALSE, FALSE)

TickPreElect(i) ==
    /\ TickGuard(i)
    /\ VoterCount(i) > 1
    /\ PreVoteSetting \in {"Enabled", "Runtime"}
    /\ PreElect(i, TRUE, FALSE)

\* UPDATE-MAP
\* code: openraft/src/core/raft_core.rs:1683-1695 (ExternalCommand::Elect { pre_vote: true }),
\*       openraft/src/raft/trigger.rs:Trigger::elect(pre_vote)
\* update: Update!AffectedActions (MCExternalPreElect)
ExternalPreElect(i) ==
    /\ InConfig(i, effectiveConfig[i])
    /\ PreElect(i, FALSE, seenGreaterLog[i])

(***************************************************************************
 * save_vote() is awaited. A pending election gets a local granted response;
 * a vote-request reply held on IOFlushed becomes visible here.              *
 * openraft/src/core/raft_core.rs:2138-2166 (exact-old numbering)           *
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
    /\ UNCHANGED <<role, vote, sendVotePending, leaseValid, candidateVars, preVars,
                    leaderVars, logVars, configVars, crashed, seenGreaterLog>>

(***************************************************************************
 * Remote requests start only after the candidate vote is durable. Runtime  *
 * enumerates the current effective voters; the candidate validates against *
 * its frozen copy. Those are equal at election start.                       *
 * openraft/src/core/raft_core.rs:1384-1478, 2339-2341                       *
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
                    candidateConfig, grants, preVars, leaderVars, logVars, configVars>>

FinishVoteBroadcast(i) ==
    /\ sendVotePending[i]
    /\ ConfigVoters(candidateConfig[i]) \ {i} \subseteq sentVoteReq[i]
    /\ sendVotePending' = [sendVotePending EXCEPT ![i] = FALSE]
    /\ UNCHANGED <<runtimeVars, vote, durableVote, votePersistPending,
                    replyPending, replyMessage, leaseValid, candidateVars, preVars,
                    leaderVars, logVars, configVars, messages>>

RemainingMessages(m, consume) == IF consume THEN messages \ {m} ELSE messages

(***************************************************************************
 * Guard order is lease, then last-log, then vote comparison. Strict vote   *
 * changes defer the response until persistence; equal votes merely touch   *
 * the lease and can reply immediately. Accepting another node's vote runs  *
 * VoteHandler::become_following, which in the new revision also drops the  *
 * Pre-Vote tracker.                                                        *
 * openraft/src/engine/engine_impl.rs:349-404 (handle_vote_req)             *
 * openraft/src/engine/handler/vote_handler/mod.rs:106-162,234-249          *
 * openraft/src/core/raft_core.rs:1529-1549 (handle_vote_request)           *
 *************************************************************************)
\* UPDATE-MAP
\* code: openraft/src/engine/handler/vote_handler/mod.rs:244 (*self.pre_candidate = None)
\* update: Update!InteractionActions (DeliverVoteRequest)
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
           follows == grant /\ ~(nv.node = i /\ InConfig(i, effectiveConfig[i]))
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
       /\ PreClearIf(i, follows)
       /\ leaderActive' = [leaderActive EXCEPT ![i] = IF follows THEN FALSE
                                                      ELSE IF grant /\ nv.committed /\ nv.node = i
                                                           THEN TRUE ELSE @]
       /\ leaderVote' = [leaderVote EXCEPT ![i] = IF grant /\ nv.committed /\ nv.node = i
                                                  THEN nv ELSE @]
    /\ UNCHANGED <<durableVote, sendVotePending, candidateVote, candidateConfig,
                    grants, sentVoteReq, leaderCertified, leaderConfig,
                    leaderGrants, logVars, configVars, crashed, seenGreaterLog>>

DeliverVoteRequest(m) ==
    /\ m \in messages
    /\ HandleVoteRequest(m.dest, m, TRUE)

(***************************************************************************
 * Engine::handle_pre_vote_req + RaftCore::handle_pre_vote_request.         *
 * Lease (never a transfer), then last-log, then would-grant comparison;    *
 * no vote, lease, role, tracker, or command change. The response is sent   *
 * at once (Respond { when: None }): it is not gated on any vote flush.     *
 * openraft/src/engine/engine_impl.rs:406-447                               *
 * openraft/src/core/raft_core.rs:1551-1562, 1603-1607                      *
 *************************************************************************)
\* UPDATE-MAP
\* code: openraft/src/engine/engine_impl.rs:406-447, raft_core.rs:1551-1562
\* update: Update!AffectedActions (DeliverPreVoteRequest)
HandlePreVoteRequest(i, m, consume) ==
    /\ ~crashed[i]
    /\ m.kind = "PreVoteReq"
    /\ m.dest = i
    /\ LET \* engine_impl.rs:426-431
           leaseBlocked == vote[i].committed /\ leaseValid[i]
           \* engine_impl.rs:433-441 reject iff req.last_log_id < my last_log_id
           logOK == LogLE(lastLog[i], m.lastLog)
           \* engine_impl.rs:443-446 granted = req.vote >= my vote
           grant == ~leaseBlocked /\ logOK /\ VoteLE(vote[i], m.vote)
           resp == Message("PreVoteResp", i, m.source, m.vote, lastLog[i], grant, FALSE)
       IN messages' = RemainingMessages(m, consume) \cup {resp}
    /\ UNCHANGED <<runtimeVars, voteVars, candidateVars, preVars, leaderVars,
                    logVars, configVars>>

DeliverPreVoteRequest(m) ==
    /\ m \in messages
    /\ HandlePreVoteRequest(m.dest, m, TRUE)

(***************************************************************************
 * Exact granted vote equality advances the frozen quorum. Establishment    *
 * commits the vote in projected state and projects the leader blank log;   *
 * committed vote persistence remains pending. Establishment does not touch *
 * Engine::pre_candidate (establish_leader -> update_vote -> become_leader).*
 * openraft/src/engine/engine_impl.rs:449-509,855-881                       *
 * openraft/src/proposer/candidate.rs:97-133                                *
 *************************************************************************)
\* UPDATE-MAP
\* code: engine_impl.rs:855-881 (establish_leader keeps pre_candidate),
\*       vote_handler/mod.rs:154-162,234-249 (adopt -> become_following clears it)
\* update: Update!InteractionActions (DeliverVoteResponse),
\*         Update!TickPreVoteNeverDeposesLeader
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
       /\ PreClearIf(i, adopt /\ stripped.node /= i)
       /\ leaderVote' = [leaderVote EXCEPT ![i] = IF wins THEN cv ELSE @]
       /\ leaderCertified' = [leaderCertified EXCEPT ![i] = IF wins THEN TRUE ELSE @]
       /\ leaderConfig' = [leaderConfig EXCEPT ![i] = IF wins THEN candidateConfig[i] ELSE @]
       /\ leaderGrants' = [leaderGrants EXCEPT ![i] = IF wins THEN ng ELSE @]
       /\ votePersistPending' = [votePersistPending EXCEPT ![i] = IF wins \/ adopt THEN TRUE ELSE @]
       /\ sendVotePending' = [sendVotePending EXCEPT ![i] = IF wins \/ adopt THEN FALSE ELSE @]
       /\ lastLog' = [lastLog EXCEPT ![i] = IF wins /\ newIndex <= MaxLogIndex
                                              THEN Log(cv.term, cv.node, newIndex) ELSE @]
       /\ logFlushPending' = [logFlushPending EXCEPT ![i] = IF wins /\ newIndex <= MaxLogIndex
                                                                THEN TRUE ELSE @]
       /\ seenGreaterLog' = [seenGreaterLog EXCEPT ![i] =
                                IF candidateActive[i] /\ ~exact /\ LogLT(lastLog[i], m.lastLog)
                                THEN TRUE ELSE @]
       \* REPAIR (implementation-backed, V0 left leaseValid unchanged):
       \* establish_leader -> update_vote(committed) installs the leader's own
       \* vote with lease = leader_lease = election_timeout_max > 0
       \* (engine_impl.rs:869-873, vote_handler/mod.rs:126-137,
       \* engine_config.rs:46); adopting a stripped (uncommitted) vote installs
       \* lease 0. A fresh leader therefore rejects vote and Pre-Vote requests
       \* until ExpireLease.
       /\ leaseValid' = [leaseValid EXCEPT ![i] = IF wins THEN TRUE
                                                  ELSE IF adopt THEN FALSE ELSE @]
    /\ UNCHANGED <<durableVote, replyPending, replyMessage,
                    candidateVote, candidateConfig, sentVoteReq, durableLastLog,
                    configVars, crashed>>

DeliverVoteResponse(m) ==
    /\ m \in messages
    /\ HandleVoteResponse(m.dest, m, TRUE)

(***************************************************************************
 * Notification::PreVoteResponse + Engine::handle_pre_vote_resp.            *
 *  - RaftCore ignores it unless a pre-candidate exists and the response's   *
 *    candidate_vote has the pre-candidate's leader id                       *
 *    (raft_core.rs:1803-1820, 2066-2090);                                   *
 *  - a grant advances the frozen tally; a quorum calls elect() at once,     *
 *    with no role, lease, or leadership check (engine_impl.rs:526-541);     *
 *  - a rejection only records a greater remote last log                     *
 *    (engine_impl.rs:543-551); the local vote is never updated.             *
 *************************************************************************)
\* UPDATE-MAP
\* code: openraft/src/engine/engine_impl.rs:511-554, raft_core.rs:1803-1820,2066-2090
\* update: Update!AffectedActions (DeliverPreVoteResponse),
\*         Update!TickPreVoteNeverDeposesLeader, Update!SelfTermIncreaseNeedsPreVoteQuorum
PreVoteMatches(i, m) ==
    /\ preCandidateActive[i]
    /\ m.vote.term = preCandidateVote[i].term
    /\ m.vote.node = preCandidateVote[i].node

PreVoteWins(i, m) ==
    /\ PreVoteMatches(i, m)
    /\ m.granted
    /\ IsQuorum(preCandidateConfig[i], preGrants[i] \cup {m.source})

HandlePreVoteResponse(i, m, consume) ==
    /\ ~crashed[i]
    /\ m.kind = "PreVoteResp"
    /\ m.dest = i
    /\ \/ /\ PreVoteWins(i, m)
          \* engine_impl.rs:536-539 self.elect()
          /\ DoElectCore(i, FALSE, seenGreaterLog[i])
          /\ messages' = RemainingMessages(m, consume)
       \/ /\ ~PreVoteWins(i, m)
          /\ messages' = RemainingMessages(m, consume)
          /\ preGrants' = [preGrants EXCEPT ![i] =
                              IF PreVoteMatches(i, m) /\ m.granted THEN @ \cup {m.source} ELSE @]
          /\ seenGreaterLog' = [seenGreaterLog EXCEPT ![i] =
                                   IF PreVoteMatches(i, m) /\ ~m.granted /\ LogLT(lastLog[i], m.lastLog)
                                   THEN TRUE ELSE @]
          /\ UNCHANGED <<role, crashed, voteVars, candidateVars, preCandidateActive,
                          preCandidateVote, preCandidateConfig, preCandidateByTick,
                          leaderVars, logVars, configVars>>

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
    /\ UNCHANGED <<runtimeVars, voteVars, candidateVars, preVars, leaderVars,
                    durableLastLog, durableConfig, durableConfigIndex, messages>>

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
    /\ UNCHANGED <<runtimeVars, voteVars, candidateVars, preVars, leaderVars,
                    durableLastLog, durableConfig, durableConfigIndex, messages>>

(***************************************************************************
 * Commit copies effective to committed. Cached role refresh is separate.   *
 * openraft/src/raft_state/membership_state/mod.rs:121-147                  *
 * openraft/src/engine/engine_impl.rs:650-673 (refresh_server_state)        *
 *************************************************************************)
CommitMembership(i) ==
    /\ ~crashed[i]
    /\ committedConfigIndex[i] < effectiveConfigIndex[i]
    /\ committedConfig' = [committedConfig EXCEPT ![i] = effectiveConfig[i]]
    /\ committedConfigIndex' = [committedConfigIndex EXCEPT ![i] = effectiveConfigIndex[i]]
    /\ UNCHANGED <<runtimeVars, voteVars, candidateVars, preVars, leaderVars, logVars,
                    effectiveConfig, effectiveConfigIndex, durableConfig,
                    durableConfigIndex, messages>>

\* UPDATE-MAP
\* code: engine_impl.rs:660-673 -> update_internal_server_state ->
\*       become_following clears pre_candidate (vote_handler/mod.rs:234-249)
\* update: Update!InteractionActions (RefreshServerState)
RefreshServerState(i) ==
    /\ ~crashed[i]
    /\ committedConfigIndex[i] = effectiveConfigIndex[i]
    /\ LET r == RoleFrom(i, vote[i], effectiveConfig[i]) IN
       /\ role' = [role EXCEPT ![i] = r]
       /\ leaderActive' = [leaderActive EXCEPT ![i] = IF r = "Leader" THEN @ ELSE FALSE]
       /\ candidateActive' = [candidateActive EXCEPT ![i] = IF r = "Candidate" THEN @ ELSE FALSE]
       /\ PreClearIf(i, r \notin {"Leader", "Candidate"})
    /\ UNCHANGED <<crashed, seenGreaterLog, voteVars, candidateVote,
                    candidateConfig, grants, sentVoteReq, leaderVote,
                    leaderCertified, leaderConfig, leaderGrants, logVars,
                    configVars, messages>>

FlushLog(i) ==
    /\ ~crashed[i]
    /\ logFlushPending[i]
    /\ durableLastLog' = [durableLastLog EXCEPT ![i] = lastLog[i]]
    /\ logFlushPending' = [logFlushPending EXCEPT ![i] = FALSE]
    /\ durableConfig' = [durableConfig EXCEPT ![i] = effectiveConfig[i]]
    /\ durableConfigIndex' = [durableConfigIndex EXCEPT ![i] = effectiveConfigIndex[i]]
    /\ UNCHANGED <<runtimeVars, voteVars, candidateVars, preVars, leaderVars, lastLog,
                    committedConfig, committedConfigIndex, effectiveConfig,
                    effectiveConfigIndex, messages>>

(***************************************************************************
 * A leader may dispatch replication after the committed vote is durable.   *
 * Append return makes the log readable before its later flush callback.    *
 * openraft/src/core/raft_core.rs (SendVote/Replicate command dispatch)     *
 *************************************************************************)
SendAppendEntries(i, j) ==
    /\ ~crashed[i]
    /\ leaderActive[i]
    /\ vote[i].committed /\ vote[i].node = i
    /\ VoteLE(vote[i], durableVote[i])
    /\ j \in ConfigVoters(effectiveConfig[i]) \ {i}
    /\ messages' = messages \cup
          {Message("Append", i, j, vote[i], lastLog[i], FALSE, FALSE)}
    /\ UNCHANGED <<runtimeVars, voteVars, candidateVars, preVars, leaderVars, logVars, configVars>>

\* UPDATE-MAP
\* code: AppendEntries -> update_vote -> become_following clears pre_candidate
\*       (vote_handler/mod.rs:154-162,234-249)
\* update: Update!InteractionActions (DeliverAppendEntries)
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
       /\ PreClearIf(i, m.vote.node /= i)
       /\ leaderActive' = [leaderActive EXCEPT ![i] = IF m.vote.node = i /\ m.vote.committed
                                                      THEN TRUE ELSE FALSE]
       /\ leaderVote' = [leaderVote EXCEPT ![i] = IF m.vote.node = i /\ m.vote.committed
                                                  THEN m.vote ELSE @]
    /\ messages' = RemainingMessages(m, consume)
    /\ UNCHANGED <<crashed, seenGreaterLog, durableVote, replyPending,
                    replyMessage, sendVotePending, candidateVote,
                    candidateConfig, grants, sentVoteReq, leaderCertified,
                    leaderConfig, leaderGrants, logVars, configVars>>

DeliverAppendEntries(m) ==
    /\ m \in messages
    /\ HandleAppendEntries(m.dest, m, TRUE)

ExpireLease(i) ==
    /\ leaseValid[i]
    /\ leaseValid' = [leaseValid EXCEPT ![i] = FALSE]
    /\ UNCHANGED <<runtimeVars, vote, durableVote, votePersistPending,
                    replyPending, replyMessage, sendVotePending, candidateVars, preVars,
                    leaderVars, logVars, configVars, messages>>

DropMessage(m) ==
    /\ m \in messages
    /\ messages' = messages \ {m}
    /\ UNCHANGED <<runtimeVars, voteVars, candidateVars, preVars, leaderVars, logVars, configVars>>

(***************************************************************************
 * Crash keeps durable variables. Restart reconstructs vote/log/config and  *
 * clears candidate, pre-candidate, command, lease, and greater-log state.   *
 * openraft/src/storage/helper.rs:83-223,313-399                            *
 * openraft/src/engine/engine_impl.rs:105-120 (Engine::new: pre_candidate None)
 * openraft/src/engine/engine_impl.rs:166-214 (startup)                     *
 *************************************************************************)
Crash(i) ==
    /\ ~crashed[i]
    /\ crashed' = [crashed EXCEPT ![i] = TRUE]
    /\ UNCHANGED <<role, seenGreaterLog, voteVars, candidateVars, preVars, leaderVars,
                    logVars, configVars, messages>>

\* UPDATE-MAP
\* code: engine_impl.rs:117 (pre_candidate: None in Engine::new)
\* update: Update!InteractionActions (Restart)
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
    /\ PreClearIf(i, TRUE)
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
    \* REPAIR (Case B found by MC_hunt_prevote_membership.cfg): an RPC response
    \* reaches only the RaftCore task that issued the request
    \* (spawn_parallel_vote_requests sends it on that core's tx_notification,
    \* raft_core.rs:1384-1478); a restarted core never receives responses to the
    \* old incarnation's requests. Pre-Vote handling is read-only on the
    \* responder, so dropping the old incarnation's Pre-Vote requests and every
    \* Pre-Vote response addressed to it removes no responder behavior.
    \* (Real vote responses keep the V0 abstraction; a stale VoteResp cannot
    \* match a later candidate vote, so it is harmless.)
    /\ messages' = {m \in messages :
                      ~(\/ m.kind = "PreVoteResp" /\ m.dest = i
                        \/ m.kind = "PreVoteReq" /\ m.source = i)}
    /\ UNCHANGED <<durableVote, durableLastLog, durableConfig, durableConfigIndex>>

Next ==
    \/ \E i \in Server : TickElect(i) \/ TickPreElect(i) \/ ExternalElect(i)
                           \/ ExternalPreElect(i) \/ StartTransferElection(i)
    \/ \E i \in Server : PersistVote(i) \/ FinishVoteBroadcast(i) \/ FlushLog(i)
    \/ \E i \in Server : ExpireLease(i) \/ Restart(i) \/ RefreshServerState(i)
    \/ \E i \in Server, j \in Server : SendVoteRequest(i, j) \/ SendAppendEntries(i, j)
    \/ \E m \in messages : DeliverVoteRequest(m) \/ DeliverVoteResponse(m)
                              \/ DeliverAppendEntries(m) \/ DropMessage(m)
                              \/ DeliverPreVoteRequest(m) \/ DeliverPreVoteResponse(m)
    \/ \E i \in Server, target \in SUBSET Server : AppendJointConfig(i, target)
    \/ \E i \in Server : AppendUniformConfig(i) \/ CommitMembership(i) \/ Crash(i)

Spec == Init /\ [][Next]_vars

VoteDomain == [term : 0..MaxTerm, node : Server, committed : BOOLEAN]

TypeOK ==
    /\ role \in [Server -> {"Learner", "Follower", "Candidate", "Leader"}]
    /\ vote \in [Server -> VoteDomain]
    /\ durableVote \in [Server -> VoteDomain]
    /\ votePersistPending \in [Server -> BOOLEAN]
    /\ replyPending \in [Server -> BOOLEAN]
    /\ sendVotePending \in [Server -> BOOLEAN]
    /\ leaseValid \in [Server -> BOOLEAN]
    /\ candidateActive \in [Server -> BOOLEAN]
    /\ candidateVote \in [Server -> VoteDomain]
    /\ \A i \in Server : IsConfig(candidateConfig[i])
    /\ grants \in [Server -> SUBSET Server]
    /\ sentVoteReq \in [Server -> SUBSET Server]
    /\ preCandidateActive \in [Server -> BOOLEAN]
    /\ preCandidateVote \in [Server -> VoteDomain]
    /\ \A i \in Server : IsConfig(preCandidateConfig[i])
    /\ preGrants \in [Server -> SUBSET Server]
    /\ preCandidateByTick \in [Server -> BOOLEAN]
    /\ leaderActive \in [Server -> BOOLEAN]
    /\ leaderVote \in [Server -> VoteDomain]
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
    /\ \A m \in messages :
          /\ m.kind \in MessageKinds
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
