------------------------------ MODULE base ------------------------------
(***************************************************************************
 * OpenRaft election reference model, updated for the Pre-Vote revision.  *
 *                                                                         *
 * Prior (V0) source boundary: engine/engine_impl.rs,                      *
 * engine/handler/vote_handler/mod.rs, core/raft_core.rs,                  *
 * raft_state/membership_state/mod.rs, and proposer/candidate.rs.          *
 *                                                                         *
 * Current revision ("update" commit) adds an optional Pre-Vote round:    *
 * Engine::pre_elect / handle_pre_vote_req / handle_pre_vote_resp, the     *
 * Engine.pre_candidate quorum tracker, Command::SendPreVote, the          *
 * RaftMsg::RequestPreVote and Notification::PreVoteResponse paths, the    *
 * runtime/config enable_pre_vote switch, and ExternalCommand::Elect       *
 * { pre_vote }. Line numbers below refer to the updated source unless    *
 * marked "old".                                                           *
 *************************************************************************)

EXTENDS Integers, Naturals, FiniteSets, Sequences, TLC

\* UPDATE-MAP
\* code: openraft/src/config/config.rs:Config::enable_pre_vote,get_enable_pre_vote;
\*       openraft/src/config/runtime_config.rs:RuntimeConfig::enable_pre_vote;
\*       openraft/src/raft/runtime_config_handle.rs:RuntimeConfigHandle::pre_vote
\* update: Update!PreVoteSetup (PreVoteNodes selects nodes whose election timer
\*         runs the Pre-Vote round; ExternalPreElect is available on every node)
CONSTANTS Server, NodeOrder, MaxTerm, MaxLogIndex, InitialConfig, PreVoteNodes

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
       /\ PreVoteNodes \subseteq Server

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

\* Leader-id equality, as used by RaftCore::does_pre_candidate_vote_match
\* (core/raft_core.rs:2067-2090): term and node only, committed bit ignored.
SameLeaderId(a, b) == a.term = b.term /\ a.node = b.node

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

\* REPAIR (pre-existing): Option<LogId>::None carries no node; two absent
\* log ids are equal (`None >= None`), whatever placeholder node NoLog(i)
\* records. engine_impl.rs:379 (handle_vote_req), :434 (handle_pre_vote_req).
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

\* UPDATE-MAP
\* code: openraft/src/core/raft_msg/mod.rs:RaftMsg::RequestPreVote;
\*       openraft/src/core/notification.rs:Notification::PreVoteResponse
\* update: Update!PreVoteMessages
\* The `round` field is a ghost observer (not an implementation field): it
\* names the Pre-Vote round (Candidate instance created by new_pre_candidate)
\* that emitted a request, and is echoed by the response. No implementation
\* guard reads it; only Update.tla properties do. Non-pre-vote messages use 0.
Message(kind, source, dest, v, lg, granted, transfer) ==
    [kind |-> kind,
     source |-> source,
     dest |-> dest,
     vote |-> v,
     lastLog |-> lg,
     granted |-> granted,
     transfer |-> transfer,
     round |-> 0]

PreMessage(kind, source, dest, v, lg, granted, rnd) ==
    [kind |-> kind,
     source |-> source,
     dest |-> dest,
     vote |-> v,
     lastLog |-> lg,
     granted |-> granted,
     transfer |-> FALSE,
     round |-> rnd]

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
    \* code: openraft/src/engine/engine_impl.rs:95-101 (Engine.pre_candidate),
    \*       engine_impl.rs:149-164 (new_pre_candidate), proposer/candidate.rs:66-118
    \* update: Update!PreVoteVars
    preCandidateActive,    \* Engine.pre_candidate.is_some()
    preCandidateVote,      \* pre_candidate.vote_ref(): hypothetical (term+1, self, uncommitted)
    preCandidateConfig,    \* frozen effective membership quorum set of the round
    preCandidateLastLog,   \* pre_candidate.last_log_id(), carried in SendPreVote
    preGrants,             \* pre_candidate.granters()
    sendPreVotePending,    \* queued Command::SendPreVote not yet executed by runtime
    preRound,              \* ghost: number of Pre-Vote rounds created on the node
    preByTimer             \* ghost: current round was started by the election timer

voteVars == <<vote, durableVote, votePersistPending, replyPending, replyMessage,
              sendVotePending, leaseValid>>
candidateVars == <<candidateActive, candidateVote, candidateConfig, grants, sentVoteReq>>
leaderVars == <<leaderActive, leaderVote, leaderCertified, leaderConfig, leaderGrants>>
logVars == <<lastLog, durableLastLog, logFlushPending>>
configVars == <<committedConfig, committedConfigIndex, effectiveConfig,
                effectiveConfigIndex, durableConfig, durableConfigIndex>>
runtimeVars == <<role, crashed, seenGreaterLog>>
preVars == <<preCandidateActive, preCandidateVote, preCandidateConfig,
             preCandidateLastLog, preGrants, sendPreVotePending, preRound, preByTimer>>
\* Pre-candidate content that is only replaced by new_pre_candidate.
preSnapshotVars == <<preCandidateVote, preCandidateConfig, preCandidateLastLog,
                     preRound, preByTimer>>
vars == <<runtimeVars, voteVars, candidateVars, leaderVars, logVars, configVars,
          messages, preVars>>

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
    \* Engine::new: pre_candidate: None (engine_impl.rs:117)
    /\ preCandidateActive = [i \in Server |-> FALSE]
    /\ preCandidateVote = vote
    /\ preCandidateConfig = [i \in Server |-> <<InitialConfig>>]
    /\ preCandidateLastLog = lastLog
    /\ preGrants = [i \in Server |-> {}]
    /\ sendPreVotePending = [i \in Server |-> FALSE]
    /\ preRound = [i \in Server |-> 0]
    /\ preByTimer = [i \in Server |-> FALSE]

GreaterLogAfter(i, reset) ==
    seenGreaterLog' = IF reset THEN [seenGreaterLog EXCEPT ![i] = FALSE] ELSE seenGreaterLog

(***************************************************************************
 * Engine::do_elect. Candidate membership and last log are snapshotted     *
 * before the pending self vote is installed. SaveVote is queued before    *
 * SendVote. The update adds `self.pre_candidate = None` at entry.          *
 * do_elect itself has no voter check (callers check); update_vote() then   *
 * calls update_internal_server_state(): a node that is not leading         *
 * (not in membership) becomes following, dropping candidate and leader.    *
 * openraft/src/engine/engine_impl.rs:113-140,262-290                       *
 * openraft/src/engine/handler/vote_handler/mod.rs:106-160,234-252          *
 * RaftCore awaits SaveVote before the next event: the ~votePersistPending  *
 * and ~replyPending guards keep event processing after that boundary.      *
 * `messages` and `preGrants` are left to the caller.                       *
 *************************************************************************)
\* UPDATE-MAP
\* code: openraft/src/engine/engine_impl.rs:262-264 (pre_candidate = None)
\* update: Update!AffectedActions (DoElect via TickElect/ExternalElect/PreVote win)
DoElectCore(i, transfer, resetGreater) ==
    /\ ~crashed[i]
    /\ vote[i].term < MaxTerm
    /\ ~votePersistPending[i]
    /\ ~replyPending[i]
    /\ LET nv == Vote(vote[i].term + 1, i, FALSE)
           member == InConfig(i, effectiveConfig[i])
       IN
       /\ vote' = [vote EXCEPT ![i] = nv]
       /\ candidateActive' = [candidateActive EXCEPT ![i] = member]
       /\ candidateVote' = [candidateVote EXCEPT ![i] = nv]
       /\ role' = [role EXCEPT ![i] = RoleFrom(i, nv, effectiveConfig[i])]
       /\ leaderActive' = [leaderActive EXCEPT ![i] = IF member THEN @ ELSE FALSE]
    /\ candidateConfig' = [candidateConfig EXCEPT ![i] = effectiveConfig[i]]
    /\ grants' = [grants EXCEPT ![i] = {}]
    /\ sentVoteReq' = [sentVoteReq EXCEPT ![i] = {}]
    /\ votePersistPending' = [votePersistPending EXCEPT ![i] = TRUE]
    /\ sendVotePending' = [sendVotePending EXCEPT ![i] = TRUE]
    /\ leaseValid' = [leaseValid EXCEPT ![i] = FALSE]
    /\ preCandidateActive' = [preCandidateActive EXCEPT ![i] = FALSE]
    /\ GreaterLogAfter(i, resetGreater)
    /\ UNCHANGED <<durableVote, replyPending, replyMessage, leaderVote,
                    leaderCertified, leaderConfig, leaderGrants, logVars,
                    configVars, crashed, sendPreVotePending, preSnapshotVars>>

DoElect(i, transfer, resetGreater) ==
    /\ DoElectCore(i, transfer, resetGreater)
    /\ UNCHANGED <<messages, preGrants>>

(***************************************************************************
 * Engine::pre_elect. Snapshot (term+1, self) as a hypothetical vote, the   *
 * effective membership, and the last log in a new pre-candidate; grant     *
 * itself. A single-voter quorum proceeds directly to elect(); otherwise    *
 * only Command::SendPreVote is queued: no vote, lease, or role change.     *
 * openraft/src/engine/engine_impl.rs:149-164,298-322                       *
 * Callers check voter membership (raft_core.rs:1683-1686,1971-1974).       *
 *************************************************************************)
\* UPDATE-MAP
\* code: openraft/src/engine/engine_impl.rs:298-322 (pre_elect)
\* update: Update!AffectedActions (MCTickElect pre-vote branch, MCExternalPreElect)
PreElect(i, byTimer, resetGreater) ==
    /\ ~crashed[i]
    /\ ~votePersistPending[i]
    /\ ~replyPending[i]
    \* The previous SendPreVote command was executed before this event.
    /\ ~sendPreVotePending[i]
    /\ vote[i].term < MaxTerm
    /\ IF IsQuorum(effectiveConfig[i], {i})
       THEN \* engine_impl.rs:311-315: self-grant reaches quorum -> elect()
            /\ DoElect(i, FALSE, resetGreater)
            /\ UNCHANGED <<sendPreVotePending>>
       ELSE
            /\ preCandidateActive' = [preCandidateActive EXCEPT ![i] = TRUE]
            /\ preCandidateVote' = [preCandidateVote EXCEPT ![i] = Vote(vote[i].term + 1, i, FALSE)]
            /\ preCandidateConfig' = [preCandidateConfig EXCEPT ![i] = effectiveConfig[i]]
            /\ preCandidateLastLog' = [preCandidateLastLog EXCEPT ![i] = lastLog[i]]
            /\ preGrants' = [preGrants EXCEPT ![i] = {i}]
            /\ sendPreVotePending' = [sendPreVotePending EXCEPT ![i] = TRUE]
            /\ preRound' = [preRound EXCEPT ![i] = @ + 1]
            /\ preByTimer' = [preByTimer EXCEPT ![i] = byTimer]
            /\ GreaterLogAfter(i, resetGreater)
            /\ UNCHANGED <<role, crashed, voteVars, candidateVars, leaderVars,
                            logVars, configVars, messages>>

(***************************************************************************
 * RaftCore::handle_tick_election. Leaders and non-voters skip. Multiple    *
 * voters require the local vote lease plus election timeout to expire,     *
 * which implies an expired lease. A single voter with an active election   *
 * skips. With enable_pre_vote and more than one voter, a Pre-Vote round    *
 * runs instead of an election; a fresh in-flight round is only restarted   *
 * after election_timeout, which this untimed model admits at any tick.     *
 * reset_greater_log() precedes either path.                               *
 * openraft/src/core/raft_core.rs:1959-2036                                  *
 *************************************************************************)
\* UPDATE-MAP
\* code: openraft/src/core/raft_core.rs:2010-2036 (pre-vote tick branch)
\* update: Update!AffectedActions (MCTickElect)
TickElect(i) ==
    /\ role[i] /= "Leader"
    /\ InConfig(i, effectiveConfig[i])
    /\ ~leaseValid[i]
    /\ LET multi == Cardinality(ConfigVoters(effectiveConfig[i])) > 1
       IN IF multi /\ i \in PreVoteNodes
          THEN PreElect(i, TRUE, TRUE)
          ELSE /\ (multi \/ ~candidateActive[i])
               /\ DoElect(i, FALSE, TRUE)

(***************************************************************************
 * ExternalCommand::Elect { pre_vote } and HandleTransferLeader.           *
 * External elect checks only voter membership, not role or lease.          *
 * openraft/src/core/raft_core.rs:1665-1693                                  *
 *************************************************************************)
\* UPDATE-MAP
\* code: openraft/src/core/raft_core.rs:1683-1690; raft/trigger.rs:Trigger::elect(pre_vote)
\* update: Update!AffectedActions (MCExternalElect, MCExternalPreElect)
ExternalElect(i) ==
    /\ InConfig(i, effectiveConfig[i])
    /\ DoElect(i, FALSE, FALSE)

ExternalPreElect(i) ==
    /\ InConfig(i, effectiveConfig[i])
    /\ PreElect(i, FALSE, FALSE)

\* Leader-chosen transfer target; the environment selects voters only.
StartTransferElection(i) ==
    /\ InConfig(i, effectiveConfig[i])
    /\ DoElect(i, TRUE, FALSE)

(***************************************************************************
 * save_vote() is awaited. A pending election gets a local granted response;
 * a vote-request reply held on IOFlushed becomes visible here.              *
 * openraft/src/core/raft_core.rs:2274-2300                                 *
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
                    leaderVars, logVars, configVars, crashed, seenGreaterLog, preVars>>

(***************************************************************************
 * Remote requests start only after the candidate vote is durable. Runtime  *
 * executes the queued SendVote command even when update_vote() dropped the *
 * candidate in the same event (a non-member electing itself); the request  *
 * content is the queued VoteRequest, fixed at do_elect.                    *
 * openraft/src/core/raft_core.rs:1385-1478,2339-2341                       *
 *************************************************************************)
SendVoteRequest(i, j) ==
    /\ ~crashed[i]
    /\ sendVotePending[i]
    /\ candidateVote[i] = vote[i]
    /\ VoteLE(candidateVote[i], durableVote[i])
    /\ j \in ConfigVoters(candidateConfig[i]) \ {i}
    /\ j \notin sentVoteReq[i]
    /\ messages' = messages \cup
          {Message("VoteReq", i, j, candidateVote[i], lastLog[i], FALSE, FALSE)}
    /\ sentVoteReq' = [sentVoteReq EXCEPT ![i] = @ \cup {j}]
    /\ UNCHANGED <<runtimeVars, voteVars, candidateActive, candidateVote,
                    candidateConfig, grants, leaderVars, logVars, configVars, preVars>>

FinishVoteBroadcast(i) ==
    /\ sendVotePending[i]
    /\ ConfigVoters(candidateConfig[i]) \ {i} \subseteq sentVoteReq[i]
    /\ sendVotePending' = [sendVotePending EXCEPT ![i] = FALSE]
    /\ UNCHANGED <<runtimeVars, vote, durableVote, votePersistPending,
                    replyPending, replyMessage, leaseValid, candidateVars,
                    leaderVars, logVars, configVars, messages, preVars>>

(***************************************************************************
 * Runtime execution of Command::SendPreVote: one Pre-Vote RPC is spawned   *
 * per other voter of the effective membership (equal to the round's frozen *
 * membership because the command runs right after pre_elect). No vote      *
 * durability precondition: nothing was persisted.                          *
 * openraft/src/core/raft_core.rs:1385-1478,2342-2344                       *
 *************************************************************************)
\* UPDATE-MAP
\* code: openraft/src/core/raft_core.rs:2342-2344, 1385-1478 (VoteRequestKind::PreVote)
\* update: Update!AffectedActions (SendPreVoteRequests)
SendPreVoteRequests(i) ==
    /\ ~crashed[i]
    /\ sendPreVotePending[i]
    /\ messages' = messages \cup
          {PreMessage("PreVoteReq", i, j, preCandidateVote[i], preCandidateLastLog[i],
                      FALSE, preRound[i]) :
              j \in ConfigVoters(preCandidateConfig[i]) \ {i}}
    /\ sendPreVotePending' = [sendPreVotePending EXCEPT ![i] = FALSE]
    /\ UNCHANGED <<runtimeVars, voteVars, candidateVars, leaderVars, logVars,
                    configVars, preCandidateActive, preGrants, preSnapshotVars>>

RemainingMessages(m, consume) == IF consume THEN messages \ {m} ELSE messages

(***************************************************************************
 * Guard order is lease, then last-log, then vote comparison. Strict vote   *
 * changes defer the response until persistence; equal votes merely touch   *
 * the lease and can reply immediately. Accepting a vote not led by this    *
 * member calls become_following(), which now also drops pre_candidate.     *
 * openraft/src/engine/engine_impl.rs:350-401                               *
 * openraft/src/engine/handler/vote_handler/mod.rs:106-160,234-252          *
 * openraft/src/core/raft_core.rs:1532-1549                                 *
 *************************************************************************)
\* UPDATE-MAP
\* code: openraft/src/engine/handler/vote_handler/mod.rs:244 (pre_candidate = None)
\* update: Update!InteractionActions (DeliverVoteRequest clears a pre-candidate)
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
       /\ preCandidateActive' = [preCandidateActive EXCEPT ![i] = IF follows THEN FALSE ELSE @]
       /\ leaderActive' = [leaderActive EXCEPT ![i] = IF follows THEN FALSE
                                                      ELSE IF grant /\ nv.committed /\ nv.node = i
                                                           THEN TRUE ELSE @]
       /\ leaderVote' = [leaderVote EXCEPT ![i] = IF grant /\ nv.committed /\ nv.node = i
                                                  THEN nv ELSE @]
    /\ UNCHANGED <<durableVote, sendVotePending, candidateVote, candidateConfig,
                    grants, sentVoteReq, leaderCertified, leaderConfig,
                    leaderGrants, logVars, configVars, crashed, seenGreaterLog,
                    preGrants, sendPreVotePending, preSnapshotVars>>

DeliverVoteRequest(m) ==
    /\ m \in messages
    /\ HandleVoteRequest(m.dest, m, TRUE)

(***************************************************************************
 * Engine::handle_pre_vote_req answered at once by RaftCore (no IO wait).   *
 * Lease (never a transfer), then last-log, then vote comparison; no state  *
 * is read-modified and no command except the response is emitted.         *
 * The response is routed back as Notification::PreVoteResponse carrying   *
 * the request's vote as candidate_vote; resp.vote (the responder's vote)   *
 * is never read by the requester, so `vote` holds candidate_vote here.     *
 * openraft/src/engine/engine_impl.rs:414-446                               *
 * openraft/src/core/raft_core.rs:1551-1562,1603-1607,1440-1458             *
 *************************************************************************)
\* UPDATE-MAP
\* code: openraft/src/engine/engine_impl.rs:414-446; core/raft_core.rs:1551-1562
\* update: Update!AffectedActions (DeliverPreVoteRequest), Update!PreVoteResponderSideEffectFree
HandlePreVoteRequest(i, m, consume) ==
    /\ ~crashed[i]
    /\ m.kind = "PreVoteReq"
    /\ m.dest = i
    /\ ~votePersistPending[i]
    /\ ~replyPending[i]
    /\ LET leaseBlocked == vote[i].committed /\ leaseValid[i]
           logOK == LogLE(lastLog[i], m.lastLog)
           grant == ~leaseBlocked /\ logOK /\ VoteLE(vote[i], m.vote)
       IN messages' = RemainingMessages(m, consume) \cup
             {PreMessage("PreVoteResp", i, m.source, m.vote, lastLog[i], grant, m.round)}
    /\ UNCHANGED <<runtimeVars, voteVars, candidateVars, leaderVars, logVars,
                    configVars, preVars>>

DeliverPreVoteRequest(m) ==
    /\ m \in messages
    /\ HandlePreVoteRequest(m.dest, m, TRUE)

(***************************************************************************
 * Exact granted vote equality advances the frozen quorum. Establishment    *
 * commits the vote in projected state and projects the leader blank log;   *
 * committed vote persistence remains pending. establish_leader() does not  *
 * touch pre_candidate. A rejected response adopts the stripped vote via    *
 * update_vote(); become_following() then drops pre_candidate too.          *
 * openraft/src/engine/engine_impl.rs:449-513,855-880                       *
 * openraft/src/proposer/candidate.rs:106-118                               *
 *************************************************************************)
\* UPDATE-MAP
\* code: openraft/src/engine/engine_impl.rs:855-880 (establish_leader keeps pre_candidate);
\*       vote_handler/mod.rs:244
\* update: Update!InteractionActions (DeliverVoteResponse)
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
           follows == adopt /\ ~(stripped.node = i /\ InConfig(i, effectiveConfig[i]))
           newIndex == lastLog[i].index + 1
       IN
       /\ messages' = RemainingMessages(m, consume)
       /\ grants' = [grants EXCEPT ![i] = IF exact THEN ng ELSE @]
       /\ candidateActive' = [candidateActive EXCEPT ![i] = IF wins \/ adopt THEN FALSE ELSE @]
       /\ preCandidateActive' = [preCandidateActive EXCEPT ![i] = IF follows THEN FALSE ELSE @]
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
       /\ lastLog' = [lastLog EXCEPT ![i] = IF wins /\ newIndex <= MaxLogIndex
                                              THEN Log(cv.term, cv.node, newIndex) ELSE @]
       /\ logFlushPending' = [logFlushPending EXCEPT ![i] = IF wins /\ newIndex <= MaxLogIndex
                                                                THEN TRUE ELSE @]
       /\ seenGreaterLog' = [seenGreaterLog EXCEPT ![i] =
                                IF candidateActive[i] /\ ~exact /\ LogLT(lastLog[i], m.lastLog)
                                THEN TRUE ELSE @]
       \* REPAIR (pre-existing): establish_leader() -> update_vote(committed
       \* self vote) installs it with the leader lease (vote_handler/mod.rs:124-131,
       \* 133-137), so the new Leader's own lease is valid.
       /\ leaseValid' = [leaseValid EXCEPT ![i] = IF wins THEN TRUE ELSE @]
    /\ UNCHANGED <<durableVote, replyPending, replyMessage,
                    candidateVote, candidateConfig, sentVoteReq, durableLastLog,
                    configVars, crashed, preGrants, sendPreVotePending, preSnapshotVars>>

DeliverVoteResponse(m) ==
    /\ m \in messages
    /\ HandleVoteResponse(m.dest, m, TRUE)

(***************************************************************************
 * Notification::PreVoteResponse. RaftCore forwards it only while a         *
 * pre-candidate exists whose vote has the same leader id (term, node) as   *
 * the response's candidate_vote. Engine::handle_pre_vote_resp then counts  *
 * a grant with grant_by(), which panics if the responder is not a voter of *
 * the round's frozen quorum set; a quorum calls elect(). A rejection with  *
 * a greater responder log sets seen_greater_log. RaftCore has completed    *
 * the previous event's awaited SaveVote before handling a notification.    *
 * openraft/src/core/raft_core.rs:1803-1820,2067-2090                       *
 * openraft/src/engine/engine_impl.rs:516-554                               *
 * openraft/src/proposer/candidate.rs:106-112                               *
 *************************************************************************)
\* UPDATE-MAP
\* code: openraft/src/core/raft_core.rs:1803-1820,2067-2090; engine_impl.rs:516-554
\* update: Update!AffectedActions (DeliverPreVoteResponse), Update!PreVoteStaleResponseIgnored,
\*         Update!PreVoteResponseNeverPanics, Update!TimerPreVoteElectionFromFollowerState
HandlePreVoteResponse(i, m, consume) ==
    /\ ~crashed[i]
    /\ m.kind = "PreVoteResp"
    /\ m.dest = i
    /\ ~votePersistPending[i]
    /\ ~replyPending[i]
    /\ LET matched == preCandidateActive[i] /\ SameLeaderId(m.vote, preCandidateVote[i])
           member == m.source \in ConfigVoters(preCandidateConfig[i])
           ng == preGrants[i] \cup {m.source}
       IN
       CASE matched /\ m.granted /\ ~member ->
                \* candidate.rs:107 expect("target not in quorum set"): the
                \* RaftCore task panics; the node stops like a crash.
                /\ crashed' = [crashed EXCEPT ![i] = TRUE]
                /\ messages' = RemainingMessages(m, consume)
                /\ UNCHANGED <<role, seenGreaterLog, voteVars, candidateVars,
                                leaderVars, logVars, configVars, preVars>>
         [] matched /\ m.granted /\ IsQuorum(preCandidateConfig[i], ng) ->
                \* engine_impl.rs:535-540: a quorum would grant -> elect()
                /\ preGrants' = [preGrants EXCEPT ![i] = ng]
                /\ messages' = RemainingMessages(m, consume)
                /\ DoElectCore(i, FALSE, FALSE)
         [] matched /\ m.granted ->
                /\ preGrants' = [preGrants EXCEPT ![i] = ng]
                /\ messages' = RemainingMessages(m, consume)
                /\ UNCHANGED <<runtimeVars, voteVars, candidateVars, leaderVars,
                                logVars, configVars, preCandidateActive,
                                sendPreVotePending, preSnapshotVars>>
         [] matched /\ ~m.granted /\ LogLT(lastLog[i], m.lastLog) ->
                \* engine_impl.rs:544-551: seen a greater log during pre-vote
                /\ seenGreaterLog' = [seenGreaterLog EXCEPT ![i] = TRUE]
                /\ messages' = RemainingMessages(m, consume)
                /\ UNCHANGED <<role, crashed, voteVars, candidateVars, leaderVars,
                                logVars, configVars, preVars>>
         [] OTHER ->
                \* stale (no matching pre-candidate) or plain rejection
                /\ messages' = RemainingMessages(m, consume)
                /\ UNCHANGED <<runtimeVars, voteVars, candidateVars, leaderVars,
                                logVars, configVars, preVars>>

DeliverPreVoteResponse(m) ==
    /\ m \in messages
    /\ HandlePreVoteResponse(m.dest, m, TRUE)

(***************************************************************************
 * Ordinary coherent membership evolution: uniform old -> joint old/new -> *
 * uniform new. Append updates effective immediately and leaves cached      *
 * Leader state (and any pre-candidate) intact.                             *
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
                    durableLastLog, durableConfig, durableConfigIndex, messages, preVars>>

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
                    durableLastLog, durableConfig, durableConfigIndex, messages, preVars>>

(***************************************************************************
 * Commit copies effective to committed. Cached role refresh is separate.   *
 * openraft/src/raft_state/membership_state/mod.rs:121-147                  *
 * openraft/src/engine/engine_impl.rs:660-673 (refresh_server_state ->      *
 * update_internal_server_state: Leader keeps state, leading keeps, other    *
 * become_following() drops leader, candidate, and pre_candidate)            *
 *************************************************************************)
CommitMembership(i) ==
    /\ ~crashed[i]
    /\ committedConfigIndex[i] < effectiveConfigIndex[i]
    /\ committedConfig' = [committedConfig EXCEPT ![i] = effectiveConfig[i]]
    /\ committedConfigIndex' = [committedConfigIndex EXCEPT ![i] = effectiveConfigIndex[i]]
    /\ UNCHANGED <<runtimeVars, voteVars, candidateVars, leaderVars, logVars,
                    effectiveConfig, effectiveConfigIndex, durableConfig,
                    durableConfigIndex, messages, preVars>>

\* UPDATE-MAP
\* code: openraft/src/engine/handler/vote_handler/mod.rs:154-162,234-252
\* update: Update!InteractionActions (RefreshServerState)
RefreshServerState(i) ==
    /\ ~crashed[i]
    /\ committedConfigIndex[i] = effectiveConfigIndex[i]
    /\ LET r == RoleFrom(i, vote[i], effectiveConfig[i]) IN
       /\ role' = [role EXCEPT ![i] = r]
       /\ leaderActive' = [leaderActive EXCEPT ![i] = IF r = "Leader" THEN @ ELSE FALSE]
       /\ candidateActive' = [candidateActive EXCEPT ![i] = IF r = "Candidate" THEN @ ELSE FALSE]
       /\ preCandidateActive' = [preCandidateActive EXCEPT ![i] =
                                    IF r \in {"Leader", "Candidate"} THEN @ ELSE FALSE]
    /\ UNCHANGED <<crashed, seenGreaterLog, voteVars, candidateVote,
                    candidateConfig, grants, sentVoteReq, leaderVote,
                    leaderCertified, leaderConfig, leaderGrants, logVars,
                    configVars, messages, preGrants, sendPreVotePending, preSnapshotVars>>

FlushLog(i) ==
    /\ ~crashed[i]
    /\ logFlushPending[i]
    /\ durableLastLog' = [durableLastLog EXCEPT ![i] = lastLog[i]]
    /\ logFlushPending' = [logFlushPending EXCEPT ![i] = FALSE]
    /\ durableConfig' = [durableConfig EXCEPT ![i] = effectiveConfig[i]]
    /\ durableConfigIndex' = [durableConfigIndex EXCEPT ![i] = effectiveConfigIndex[i]]
    /\ UNCHANGED <<runtimeVars, voteVars, candidateVars, leaderVars, lastLog,
                    committedConfig, committedConfigIndex, effectiveConfig,
                    effectiveConfigIndex, messages, preVars>>

(***************************************************************************
 * A leader may dispatch replication after the committed vote is durable.   *
 * Append return makes the log readable before its later flush callback.    *
 * openraft/src/core/raft_core.rs (run_command AppendEntries/Replicate)     *
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
                    configVars, preVars>>

\* UPDATE-MAP
\* code: openraft/src/engine/handler/vote_handler/mod.rs:244 via update_vote()
\* update: Update!InteractionActions (DeliverAppendEntries clears a pre-candidate)
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
       /\ preCandidateActive' = [preCandidateActive EXCEPT ![i] = IF m.vote.node = i THEN @ ELSE FALSE]
       /\ leaderActive' = [leaderActive EXCEPT ![i] = IF m.vote.node = i /\ m.vote.committed
                                                      THEN TRUE ELSE FALSE]
       /\ leaderVote' = [leaderVote EXCEPT ![i] = IF m.vote.node = i /\ m.vote.committed
                                                  THEN m.vote ELSE @]
    /\ messages' = RemainingMessages(m, consume)
    /\ UNCHANGED <<crashed, seenGreaterLog, durableVote, replyPending,
                    replyMessage, sendVotePending, candidateVote,
                    candidateConfig, grants, sentVoteReq, leaderCertified,
                    leaderConfig, leaderGrants, logVars, configVars,
                    preGrants, sendPreVotePending, preSnapshotVars>>

DeliverAppendEntries(m) ==
    /\ m \in messages
    /\ HandleAppendEntries(m.dest, m, TRUE)

ExpireLease(i) ==
    /\ leaseValid[i]
    /\ leaseValid' = [leaseValid EXCEPT ![i] = FALSE]
    /\ UNCHANGED <<runtimeVars, vote, durableVote, votePersistPending,
                    replyPending, replyMessage, sendVotePending, candidateVars,
                    leaderVars, logVars, configVars, messages, preVars>>

DropMessage(m) ==
    /\ m \in messages
    /\ messages' = messages \ {m}
    /\ UNCHANGED <<runtimeVars, voteVars, candidateVars, leaderVars, logVars,
                    configVars, preVars>>

(***************************************************************************
 * Crash keeps durable variables. Restart reconstructs vote/log/config and  *
 * clears candidate, pre-candidate, command, lease, and greater-log state.  *
 * openraft/src/storage/helper.rs:83-223,313-399                            *
 * openraft/src/engine/engine_impl.rs:107-120 (Engine::new),166-210         *
 *************************************************************************)
Crash(i) ==
    /\ ~crashed[i]
    /\ crashed' = [crashed EXCEPT ![i] = TRUE]
    /\ UNCHANGED <<role, seenGreaterLog, voteVars, candidateVars, leaderVars,
                    logVars, configVars, messages, preVars>>

\* UPDATE-MAP
\* code: openraft/src/engine/engine_impl.rs:117 (pre_candidate: None on Engine::new)
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
    /\ preCandidateActive' = [preCandidateActive EXCEPT ![i] = FALSE]
    /\ preGrants' = [preGrants EXCEPT ![i] = {}]
    /\ sendPreVotePending' = [sendPreVotePending EXCEPT ![i] = FALSE]
    /\ UNCHANGED <<durableVote, durableLastLog, durableConfig, durableConfigIndex,
                    messages, preSnapshotVars>>

Next ==
    \/ \E i \in Server : TickElect(i) \/ ExternalElect(i) \/ ExternalPreElect(i)
                           \/ StartTransferElection(i)
    \/ \E i \in Server : PersistVote(i) \/ FinishVoteBroadcast(i) \/ FlushLog(i)
                           \/ SendPreVoteRequests(i)
    \/ \E i \in Server : ExpireLease(i) \/ Restart(i) \/ RefreshServerState(i)
    \/ \E i \in Server, j \in Server : SendVoteRequest(i, j) \/ SendAppendEntries(i, j)
    \/ \E m \in messages : DeliverVoteRequest(m) \/ DeliverVoteResponse(m)
                              \/ DeliverAppendEntries(m) \/ DropMessage(m)
                              \/ DeliverPreVoteRequest(m) \/ DeliverPreVoteResponse(m)
    \/ \E i \in Server, target \in SUBSET Server : AppendJointConfig(i, target)
    \/ \E i \in Server : AppendUniformConfig(i) \/ CommitMembership(i) \/ Crash(i)

Spec == Init /\ [][Next]_vars

\* REQ-EVIDENCE TypeOK
\* intent:   every model variable except replyMessage, and every field of every in-flight message, stays inside its declared domain.
\* status:   model-internal
\* watch:    none
\* verified: update
\* note:     update: extended with the Pre-Vote variables (pre-candidate, pending SendPreVote, ghost round/origin) and the PreVoteReq/PreVoteResp message kinds and ghost round field; see spec/invariant-evidence.json E-TypeOK.
\* review:   intent narrowed to exclude replyMessage, which the formula does not constrain, so the intent no longer claims "every model variable".
TypeOK ==
    /\ role \in [Server -> {"Learner", "Follower", "Candidate", "Leader"}]
    /\ vote \in [Server -> [term : 0..MaxTerm, node : Server, committed : BOOLEAN]]
    /\ durableVote \in [Server -> [term : 0..MaxTerm, node : Server, committed : BOOLEAN]]
    /\ votePersistPending \in [Server -> BOOLEAN]
    /\ replyPending \in [Server -> BOOLEAN]
    /\ sendVotePending \in [Server -> BOOLEAN]
    /\ leaseValid \in [Server -> BOOLEAN]
    /\ candidateActive \in [Server -> BOOLEAN]
    /\ candidateVote \in [Server -> [term : 0..MaxTerm, node : Server, committed : BOOLEAN]]
    /\ \A i \in Server : IsConfig(candidateConfig[i])
    /\ grants \in [Server -> SUBSET Server]
    /\ sentVoteReq \in [Server -> SUBSET Server]
    /\ leaderActive \in [Server -> BOOLEAN]
    /\ leaderVote \in [Server -> [term : 0..MaxTerm, node : Server, committed : BOOLEAN]]
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
    /\ preCandidateVote \in [Server -> [term : 0..MaxTerm, node : Server, committed : BOOLEAN]]
    /\ \A i \in Server : IsConfig(preCandidateConfig[i])
    /\ \A i \in Server :
          /\ preCandidateLastLog[i].present \in BOOLEAN
          /\ preCandidateLastLog[i].term \in 0..MaxTerm
          /\ preCandidateLastLog[i].node \in Server
          /\ preCandidateLastLog[i].index \in 0..MaxLogIndex
    /\ preGrants \in [Server -> SUBSET Server]
    /\ sendPreVotePending \in [Server -> BOOLEAN]
    /\ preRound \in [Server -> Nat]
    /\ preByTimer \in [Server -> BOOLEAN]
    /\ \A m \in messages :
          /\ m.kind \in {"VoteReq", "VoteResp", "Append", "PreVoteReq", "PreVoteResp"}
          /\ m.round \in Nat
          /\ m.source \in Server /\ m.dest \in Server
          /\ m.vote.term \in 0..MaxTerm /\ m.vote.node \in Server
          /\ m.vote.committed \in BOOLEAN
          /\ m.lastLog.present \in BOOLEAN
          /\ m.lastLog.term \in 0..MaxTerm
          /\ m.lastLog.node \in Server
          /\ m.lastLog.index \in 0..MaxLogIndex
          /\ m.granted \in BOOLEAN /\ m.transfer \in BOOLEAN

\* REQ-EVIDENCE DurableVoteNotAhead
\* intent:   on every node, the vote stored on disk is never ahead of the node's in-memory (current) vote.
\* status:   impl-abstraction
\* evidence: comment source/openraft/src/raft_state/io_state/io_progress.rs:12 "Invariant: `flushed <= submitted <= accepted`" -> one step only: the stored vote never runs ahead of the vote accepted for I/O (not the in-memory vote)
\* evidence: doc source/openraft/src/docs/data/log_io_progress.md:17 "The invariant maintained is: `flushed <= submitted <= accepted`" -> one step only: the stored vote never runs ahead of the vote accepted for I/O (not the in-memory vote)
\* evidence: doc source/openraft/src/docs/data/io_id.md:19 "Both operations share the same `IOProgress` tracker" -> vote saves are part of the I/O cursors that invariant orders
\* evidence: impl source/openraft/src/engine/handler/vote_handler/mod.rs:134 "self.state.vote.update(C::now(), leader_lease, vote.clone());"
\* evidence: impl source/openraft/src/engine/handler/vote_handler/mod.rs:135 "self.state.accept_log_io(IOId::new(vote));"
\* evidence: impl source/openraft/src/core/raft_core.rs:2145 "self.log_store.save_vote(&vote).await.sto_write_vote()?;"
\* evidence: impl source/openraft/src/storage/helper.rs:89 "let vote = log_reader.read_vote().await.sto_read_vote()?;"
\* watch:    source/openraft/src/raft_state/io_state/io_progress.rs:IOProgress::validate; source/openraft/src/engine/handler/vote_handler/mod.rs:VoteHandler::update_vote; source/openraft/src/core/raft_core.rs:RaftCore::run_command (Command::SaveVote); source/openraft/src/engine/engine_impl.rs:Engine::startup; source/openraft/src/storage/helper.rs:StorageHelper::get_initial_state; source/openraft/src/config/config.rs:Config::enable_leader_restore
\* verified: base
\* note:     io_progress.rs:12, log_io_progress.md:17 and io_id.md:19,102 order the shared vote/log I/O cursors (vote first), not RaftState.vote; they reach the in-memory vote only through impl (vote_handler/mod.rs:134-135), so they were not counted for the whole intent. engine/engine_impl.rs:153-162 "Demote the vote in memory only; do not persist it." and f4b5f61d (message) "the committed vote intentionally stays in storage" state that, with leader restore disabled, the in-memory vote is demoted below the stored committed vote and the divergence is safe. History: log -S'flushed <= submitted <= accepted' -> 2666d3d3, ee460f37; log -S'Demote the vote in memory only' -> f4b5f61d; no source requires the in-memory vote to stay at or above the stored one
\* review:   intent rewritten to the formula's stored-vs-in-memory comparison and status requirement -> impl-abstraction, because the cited invariant orders I/O cursors only and engine_impl.rs:153-162 / f4b5f61d (missed by the old note) let the stored vote run ahead of the in-memory one.
DurableVoteNotAhead == \A i \in Server : VoteLE(durableVote[i], vote[i])
\* REQ-EVIDENCE DurableLogNotAhead
\* intent:   on every node, the last log id persisted on disk is never ahead of the node's last log id (`last_log`, the accepted pointer).
\* status:   requirement
\* evidence: doc source/openraft/src/docs/data/log_pointers.md:27 "`flushed` ≤ `submitted` ≤ `accepted`;" -> the last persisted log id never exceeds the accepted one
\* evidence: doc source/openraft/src/docs/data/log_pointers.md:24 "`accepted` is also known as `last_log` in Openraft codebase." -> the accepted pointer is the node's last log id
\* evidence: doc source/openraft/src/docs/data/log_pointers.md:19 "the last log entry that is persisted on disk, inclusive." -> the flushed pointer is the last log entry persisted on disk
\* evidence: comment source/openraft/src/raft_state/io_state/io_progress.rs:12 "Invariant: `flushed <= submitted <= accepted`" -> the same order for log I/O, stated over I/O ids (vote first, then log id)
\* evidence: doc source/openraft/src/docs/data/log_io_progress.md:17 "The invariant maintained is: `flushed <= submitted <= accepted`" -> the same order for log I/O, stated over I/O ids (vote first, then log id)
\* evidence: contract source/openraft/src/storage/v2/raft_log_storage.rs:101 "When the `callback` is called, the entries must be persisted on disk." -> a flush report means the entries are on disk
\* evidence: impl source/openraft/src/core/raft_core.rs:2131 "self.engine.state.log_progress_mut().submit(io_id.clone());"
\* evidence: impl source/openraft/src/core/raft_core.rs:2136 "self.log_store.append(entries, callback).await.sto_write_logs()?;"
\* watch:    source/openraft/src/raft_state/io_state/io_progress.rs:IOProgress::validate; source/openraft/src/core/raft_core.rs:RaftCore::run_command (Command::AppendEntries); source/openraft/src/engine/handler/following_handler/mod.rs:FollowingHandler::truncate_logs; source/openraft/src/storage/v2/raft_log_storage.rs:RaftLogStorage::append; source/openraft/src/storage/helper.rs:StorageHelper::get_initial_state
\* verified: base
\* note:     log_pointers.md:19-27 states the order directly over log entries, with `accepted` named `last_log`; io_progress.rs:12 and log_io_progress.md:17 state it over I/O ids, which io_id.md:102 orders by vote before log id, so they are secondary. raft_log_storage.rs:98 ("When this method returns, the entries must be readable") was dropped: readability on return does not order the persisted log id against `last_log`, and :103 lets the callback come before the return
\* review:   intent rewritten from I/O-id terms to the formula's last-log-id comparison, added log_pointers.md:19/24/27, which states it directly (contradicting the old note's "none found"), and removed raft_log_storage.rs:98, whose arrow :103 contradicts.
DurableLogNotAhead == \A i \in Server : LogLE(durableLastLog[i], lastLog[i])

\* REQ-EVIDENCE VoteRequestAfterDurable
\* intent:   a node sends vote requests only for a vote that is already persisted in its own storage.
\* status:   impl-abstraction
\* evidence: test source/openraft/src/engine/tests/elect_test.rs:58 test_elect_single_node "Command::SaveVote { vote: Vote::new(1, 1) }," -> the save of the new vote is queued ahead of SendVote (queue order only)
\* evidence: contract source/openraft/src/storage/v2/raft_log_storage.rs:62 "The vote must be persisted on disk before returning." -> a completed save_vote means the vote is durable
\* evidence: impl source/openraft/src/core/raft_core.rs:2145 "self.log_store.save_vote(&vote).await.sto_write_vote()?;"
\* evidence: impl source/openraft/src/core/raft_core.rs:2204 "self.spawn_parallel_vote_requests(&vote_req).await;"
\* evidence: impl source/openraft/src/core/raft_core.rs:1112 "let res = self.run_command(cmd).await?;"
\* evidence: impl source/openraft/src/engine/engine_impl.rs:245 "self.output.push_command(Command::SendVote {"
\* watch:    source/openraft/src/core/raft_core.rs:RaftCore::run_engine_commands; source/openraft/src/core/raft_core.rs:RaftCore::run_command (Command::SaveVote, Command::SendVote); source/openraft/src/engine/engine_impl.rs:Engine::do_elect; source/openraft/src/engine/command.rs:Command::condition; source/openraft/src/engine/engine_output.rs:EngineOutput::postpone_command
\* verified: base
\* note:     searched docs/, raft-essentials.md, comments around do_elect and spawn_parallel_vote_requests, and history (log -S'SendVote', -S'spawn_parallel_vote_requests', -S'save_vote(&vote)'; show 4060ba16, 453e80d1, 36d2c115, 88754e09) for a rule that vote requests wait for the vote to be durable; none found. The test and contract lines give queue order and save durability, not that sending waits for the save. 88754e09 (message) says "Command execution can be reordered or batched for performance."; 36d2c115 (message) ties persistence to the voting state and says SaveVote may become callback-based
\* review:   ok
VoteRequestAfterDurable ==
    \A m \in messages : m.kind = "VoteReq" => VoteLE(m.vote, durableVote[m.source])

\* REQ-EVIDENCE GrantedResponseAfterDurable
\* intent:   a granted vote response leaves a node only after the vote it grants is persisted on that node.
\* status:   requirement
\* evidence: history ee460f37 (message) "`Condition` that remains unsatisfied until operations like `SaveVote` or `AppendInputEntries` are flushed to disk" -> a vote-request reply is held until its SaveVote is flushed
\* evidence: history 88754e09 (message) "Sending rpc(vote, append-entries and install-snapshot) response must be after executing the commands generated by Engine." -> a vote reply follows the SaveVote it depends on
\* evidence: history 36d2c115 (message) "The `Voting` state is now updated only after `SaveVote` is successfully persisted on disk." -> the candidate's own grant counts only after its vote is persisted
\* evidence: test source/openraft/src/engine/tests/elect_test.rs:38 test_elect_single_node "single node: still need to wait for Vote to persist" -> the candidate's own grant is not counted before persistence
\* evidence: contract source/openraft/src/storage/v2/raft_log_storage.rs:62 "The vote must be persisted on disk before returning." -> a vote whose save has returned is durable
\* evidence: impl source/openraft/src/core/raft_core.rs:1493 "let condition = Some(Condition::IOFlushed {"
\* evidence: impl source/openraft/src/engine/command.rs:403 "Condition::IOFlushed { io_id } => self.is_satisfied_by(io_id, io_state.log_progress.flushed()),"
\* evidence: impl source/openraft/src/core/raft_core.rs:2161 "resp: VoteResponse::new(vote, None, true),"
\* watch:    source/openraft/src/core/raft_core.rs:RaftCore::handle_vote_request; source/openraft/src/core/raft_core.rs:RaftCore::run_command (Command::SaveVote); source/openraft/src/core/raft_core.rs:RaftCore::send_satisfied_responds; source/openraft/src/engine/command.rs:Condition::is_met; source/openraft/src/engine/engine_output.rs:EngineOutput::postpone_command
\* verified: base
\* note:     no code comment states the rule; it survives in the commit messages above and in the IOFlushed condition. The comment at core/raft_core.rs:2154 ("there may be a candidate waiting for the response") explains why the local reply is sent, not when, so it was counted as impl
\* review:   ok
GrantedResponseAfterDurable ==
    \A m \in messages : m.kind = "VoteResp" /\ m.granted => VoteLE(m.vote, durableVote[m.source])

\* REQ-EVIDENCE LeaderRoleHasCommittedSelfVote
\* intent:   a node in the Leader role holds a committed vote that names itself.
\* status:   requirement
\* evidence: doc source/openraft/src/docs/data/vote.md:61 "is a leader if it is **present** in config, either a voter or non-voter." -> leader only with its own committed vote (row at vote.md:60)
\* evidence: comment source/openraft/src/raft_state/mod.rs:459 "Leadership is granted by a quorum and the vote is committed." -> a leader's vote is committed
\* evidence: doc source/openraft/src/docs/data/vote.md:48 "the `Vote` defines the server state (leader, candidate, follower or learner)." -> the role is determined by the vote
\* evidence: test source/openraft/src/engine/tests/handle_vote_resp_test.rs:194 test_handle_vote_resp_equal_vote "assert_eq!(Vote::new_committed(2, 1), *eng.state.vote_ref(),);" -> on becoming Leader (line 213) the vote is its own committed vote
\* evidence: impl source/openraft/src/raft_state/mod.rs:466 "self.is_leading(id) && self.vote.is_committed()"
\* evidence: impl source/openraft/src/raft_state/mod.rs:429 "if self.is_leader(id) {"
\* evidence: impl source/openraft/src/engine/handler/vote_handler/mod.rs:163 "Enter Leader state(vote.node_id == self.id && vote.committed == true)."
\* watch:    source/openraft/src/raft_state/mod.rs:RaftState::calc_server_state; source/openraft/src/raft_state/mod.rs:RaftState::is_leader; source/openraft/src/engine/handler/server_state_handler/mod.rs:ServerStateHandler::update_server_state_if_changed; source/openraft/src/engine/engine_impl.rs:Engine::startup; source/openraft/src/engine/handler/vote_handler/mod.rs:VoteHandler::update_internal_server_state
\* verified: base
\* note:     vote.md gives a table from (vote, membership) to server state; the leader column appears only in the committed self-vote row, which is read here in the role-to-vote direction. vote_handler/mod.rs:163 is the doc line of become_leader(); it restates the calling condition and what the function does (its lines 165-167 say it is not called on election), so it was counted as impl
\* review:   retyped vote_handler/mod.rs:163 from comment to impl because it narrates become_leader() and its calling condition rather than stating a rule; the status stays requirement on vote.md:61/48, raft_state/mod.rs:459 and the test.
LeaderRoleHasCommittedSelfVote ==
    \A i \in Server : role[i] = "Leader" => vote[i].committed /\ vote[i].node = i

\* REQ-EVIDENCE CandidateRoleHasPendingSelfVote
\* intent:   a node in the Candidate role holds a not-yet-committed vote that names itself.
\* status:   requirement
\* evidence: doc source/openraft/src/docs/data/vote.md:65 "is a candidate if it is **present** in config, either a voter or non-voter." -> candidate only with its own uncommitted vote (row at vote.md:64)
\* evidence: comment source/openraft/src/raft_state/mod.rs:446 "The node is candidate(leadership is not granted by a quorum) or leader" -> a Candidate's leadership is not yet granted by a quorum
\* evidence: test source/openraft/src/engine/tests/elect_test.rs:53 test_elect_single_node "assert_eq!(ServerState::Candidate, eng.state.server_state);" -> after elect() the Candidate holds its own uncommitted vote (line 49)
\* evidence: test source/openraft/src/engine/tests/handle_vote_resp_test.rs:167 test_handle_vote_resp "assert_eq!(ServerState::Candidate, eng.state.server_state);" -> without a quorum it stays Candidate with an uncommitted self vote (line 159)
\* evidence: impl source/openraft/src/raft_state/mod.rs:431 "} else if self.is_leading(id) {"
\* evidence: impl source/openraft/src/raft_state/mod.rs:454 "self.membership_state.contains(id) && self.vote.leader_node_id() == id"
\* watch:    source/openraft/src/raft_state/mod.rs:RaftState::calc_server_state; source/openraft/src/raft_state/mod.rs:RaftState::is_leading; source/openraft/src/engine/handler/server_state_handler/mod.rs:ServerStateHandler::update_server_state_if_changed; source/openraft/src/engine/engine_impl.rs:Engine::do_elect; source/openraft/src/engine/engine_impl.rs:Engine::startup
\* verified: base
\* note:     vote.md gives a table from (vote, membership) to server state; the candidate column appears only in the uncommitted self-vote row, which is read here in the role-to-vote direction
\* review:   narrowed the arrow on raft_state/mod.rs:446 to what it literally says (no quorum grant), because "not committed" is not in the quote; intent and status are unchanged and rest on vote.md:65 and the two tests.
CandidateRoleHasPendingSelfVote ==
    \A i \in Server : role[i] = "Candidate" => ~vote[i].committed /\ vote[i].node = i

\* REQ-EVIDENCE CertifiedLeaderHasFrozenQuorum
\* intent:   a node that became leader by winning its own election had its vote granted by a quorum (a majority of every constituent config) of the membership captured when that election started.
\* status:   mixed
\* evidence: comment source/openraft/src/proposer/candidate.rs:113 "Mark the vote as committed, i.e., being granted and saved by a quorum." -> an elected leader's vote was granted by a quorum
\* evidence: doc source/raft-essentials.md:106 "requires separate majorities from both the old and new configurations" -> election quorum is a majority in each config of a joint config
\* evidence: doc source/raft-essentials.md:53 "a candidate wins an election if it receives votes from a majority" -> winning needs a majority of grants
\* evidence: comment source/openraft/src/raft_state/mod.rs:459 "Leadership is granted by a quorum and the vote is committed." -> leadership is quorum-granted
\* evidence: contract source/openraft/src/quorum/quorum_set_impl.rs:31 "a node set is a quorum iff it is a majority in every config." -> joint quorum means a majority in every constituent config
\* evidence: test source/openraft/src/engine/tests/handle_vote_resp_test.rs:176 test_handle_vote_resp_equal_vote "equal vote, granted, constitute a quorum. become leader" -> leader once grants form a quorum
\* evidence: test source/openraft/src/engine/tests/handle_vote_resp_test.rs:140 test_handle_vote_resp "equal vote, granted, but not constitute a quorum. nothing to do" -> no leader without a quorum
\* evidence: impl source/openraft/src/engine/engine_impl.rs:121 "let membership = self.state.membership_state.effective().membership();"
\* evidence: impl source/openraft/src/proposer/candidate.rs:99 "self.progress.update(target, true)"
\* evidence: impl source/openraft/src/engine/engine_impl.rs:347 "if resp.vote_granted && &resp.vote == candidate.vote_ref() {"
\* watch:    source/openraft/src/proposer/candidate.rs:Candidate::grant_by; source/openraft/src/engine/engine_impl.rs:Engine::new_candidate; source/openraft/src/engine/engine_impl.rs:Engine::handle_vote_resp; source/openraft/src/engine/engine_impl.rs:Engine::establish_leader; source/openraft/src/quorum/quorum_set_impl.rs:QuorumSet for Vec<BTreeSet<NID>>; source/openraft/src/membership/membership_impl_quorum_set.rs:QuorumSet for Membership
\* verified: base
\* clause quorum-granted: requirement — candidate.rs:113, raft_state/mod.rs:459, raft-essentials.md:53 and :106 and quorum_set_impl.rs:31 say an elected leader holds grants from a majority of every constituent config; the two handle_vote_resp tests show this for a uniform config only
\* clause frozen-config: impl-abstraction — only impl (engine_impl.rs:121-127 copies the effective membership into the Candidate when the election starts); nothing found requires counting against that start-of-election copy
\* note:     searched history (log -S'fn new_candidate' on engine_impl.rs and -S'quorum_set' on candidate.rs, both -> 36d2c115) and docs/ for why the candidate keeps its own membership copy; no reason is recorded. raft-essentials.md:103 ("a server always uses the latest configuration in its log") names the latest configuration, not a copy captured at election start, so it was not counted for frozen-config
\* review:   corrected the quorum-granted clause summary (the handle_vote_resp tests use uniform configs only, not joint ones) and recorded raft-essentials.md:103 in the note; the mixed status and both clause statuses are unchanged.
CertifiedLeaderHasFrozenQuorum ==
    \A i \in Server : leaderCertified[i] => IsQuorum(leaderConfig[i], leaderGrants[i])

\* REQ-EVIDENCE MembershipAtMostOneOutstanding
\* intent:   on every node the committed membership config is never newer than the effective one, and at most one config beyond the committed one is outstanding.
\* status:   requirement
\* evidence: comment source/openraft/src/raft_state/membership_state/mod.rs:37 "(2) there is at most one outstanding, uncommitted membership log." -> at most one uncommitted config
\* evidence: comment source/openraft/src/raft_state/membership_state/mod.rs:199 "Openraft allows at most only one non-committed membership config." -> at most one uncommitted config
\* evidence: doc source/openraft/src/docs/data/effective-membership.md:16 "The second-to-last membership log has to be committed." -> at most one uncommitted config
\* evidence: history 3fd1d8aa (message) "(2) there is at most one outstanding, uncommitted membership log." -> at most one uncommitted config
\* evidence: comment source/openraft/src/core/raft_core.rs:533 "But it still has to wait for the previous membership to commit." -> a new config is proposed only after the previous one commits
\* evidence: comment source/openraft/src/raft_state/membership_state/mod.rs:28 "`effective` is the last membership log" -> the committed config is never newer than the effective one
\* evidence: doc source/openraft/src/docs/cluster_control/dynamic-membership.md:45 "After joint config commits, proposes uniform config: `new_config`" -> the uniform config is proposed only after the joint one commits
\* evidence: test source/openraft/src/raft_state/membership_state/change_handler_test.rs:40 test_apply_not_committed "Err(ChangeMembershipError::InProgress(InProgress {" -> a change is rejected while the effective config is uncommitted
\* evidence: test source/openraft/src/raft_state/membership_state/membership_state_test.rs:110 test_membership_state_append "assert_eq!(&Some(log_id(3, 1, 4)), ms.committed().log_id());" -> appending a config makes the previous effective one committed
\* evidence: impl source/openraft/src/raft_state/membership_state/mod.rs:277 "validit::less_equal!(self.committed.log_id(), self.effective.log_id());"
\* evidence: impl source/openraft/src/raft_state/membership_state/mod.rs:201 "self.committed = self.effective.clone();"
\* evidence: impl source/openraft/src/raft_state/membership_state/change_handler.rs:58 "if effective.log_id() == committed.log_id() {"
\* evidence: impl source/openraft/src/raft_state/membership_state/change_handler.rs:50 "Ensures that the latest membership has been committed."
\* watch:    source/openraft/src/raft_state/membership_state/mod.rs:MembershipState::append; source/openraft/src/raft_state/membership_state/mod.rs:MembershipState::commit; source/openraft/src/raft_state/membership_state/mod.rs:MembershipState::truncate; source/openraft/src/raft_state/membership_state/mod.rs:MembershipState::install_membership_snapshot; source/openraft/src/raft_state/membership_state/change_handler.rs:ChangeHandler::ensure_committed; source/openraft/src/core/raft_core.rs:RaftCore::change_membership; source/openraft/src/engine/handler/following_handler/mod.rs:FollowingHandler::append_membership
\* verified: base
\* note:     membership_state/mod.rs:37 and :199, effective-membership.md:16 and 3fd1d8aa state the bound as a number of outstanding uncommitted membership logs. change_handler.rs:50 is the doc line of ensure_committed() and restates what that function checks, so it was counted as impl
\* review:   retyped change_handler.rs:50 from comment to impl because it narrates ensure_committed(), and replaced a note sentence about how the formula's index bound is read with an evidence-only note; intent and status are unchanged.
MembershipAtMostOneOutstanding ==
    \A i \in Server :
        /\ committedConfigIndex[i] <= effectiveConfigIndex[i]
        /\ effectiveConfigIndex[i] <= committedConfigIndex[i] + 1

\* REQ-EVIDENCE NoForgedMessageEndpoints
\* intent:   every in-flight message is sent from and addressed to a node of the modelled server set.
\* status:   model-internal
\* watch:    none
\* verified: base
\* note:     searched the source for "byzantine", "forged", "authenticat" and found no stated assumption about message endpoints; core/raft_core.rs:1374 "target must be in membership" is about RPC targets being cluster members, not about the node universe, so it was not counted
\* review:   ok
NoForgedMessageEndpoints ==
    \A m \in messages : m.source \in Server /\ m.dest \in Server

=============================================================================
