------------------------------ MODULE base ------------------------------
(***************************************************************************
 * OpenRaft election reference model, updated for the Pre-Vote revision.  *
 *                                                                         *
 * V0 source boundary (exact-old): engine/engine_impl.rs,                  *
 * engine/handler/vote_handler/mod.rs, core/raft_core.rs,                  *
 * raft_state/membership_state/mod.rs, and proposer/candidate.rs.          *
 *                                                                         *
 * V1 (current) source: /work/current/.specula-output/artifact at the      *
 * synthetic `update` commit.  The update adds an optional Pre-Vote round   *
 * (Engine::pre_elect / handle_pre_vote_req / handle_pre_vote_resp, the     *
 * SendPreVote command, RaftMsg::RequestPreVote, Notification::PreVoteResp, *
 * the runtime enable_pre_vote switch, and ExternalCommand::Elect{pre_vote})*
 * Every changed location carries an UPDATE-MAP comment pointing to the     *
 * matching focus in Update.tla.                                            *
 *************************************************************************)

EXTENDS Integers, Naturals, FiniteSets, Sequences, TLC

\* UPDATE-MAP
\* code: openraft/src/config/config.rs:enable_pre_vote, config/runtime_config.rs:11,19,
\*       raft/runtime_config_handle.rs:pre_vote
\* update: Update!TickPreVoteContext (PreVoteSetting selects the runtime flag
\*         values a tick may observe; {FALSE} is the exact-old behaviour)
CONSTANTS Server, NodeOrder, MaxTerm, MaxLogIndex, InitialConfig, PreVoteSetting

ReferenceServer == {"1", "2", "3"}
ReferenceNodeOrder == <<"1", "2", "3">>
ReferenceInitialConfig == {"1", "2", "3"}
\* The runtime flag is an AtomicBool that RuntimeConfigHandle::pre_vote can
\* flip at any time (raft/runtime_config_handle.rs:46-53), so the reference
\* admits ticks under either value.
ReferencePreVoteSetting == {FALSE, TRUE}

ASSUME /\ Server /= {}
       /\ Len(NodeOrder) = Cardinality(Server)
       /\ {NodeOrder[k] : k \in 1..Len(NodeOrder)} = Server
       /\ InitialConfig \subseteq Server
       /\ InitialConfig /= {}
       /\ MaxTerm \in Nat \ {0}
       /\ MaxLogIndex \in Nat \ {0}
       /\ PreVoteSetting \subseteq BOOLEAN
       /\ PreVoteSetting /= {}

FirstNode == NodeOrder[1]

DefaultVote(i) == [term |-> 0, node |-> i, committed |-> FALSE]
Vote(t, n, c) == [term |-> t, node |-> n, committed |-> c]

NoLog(i) == [present |-> FALSE, term |-> 0, node |-> i, index |-> 0]
Log(t, n, x) == [present |-> TRUE, term |-> t, node |-> n, index |-> x]

NodePos(i) == CHOOSE k \in 1..Len(NodeOrder) : NodeOrder[k] = i

(***************************************************************************
 * The selected exact-old UTConfig uses leader_id_adv::LeaderId: term,     *
 * then node, then committed status.                                       *
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

\* REPAIR (prior-model defect): Option<LogId>::None compares equal to None
\* (openraft/src/log_id/mod.rs:18-61, derived Option ordering). The record
\* keeps a per-node `node` field for absent logs, so equality of records is
\* not the source ordering; two absent logs are equal. Without this, no
\* remote vote/pre-vote was ever granted from the initial state (V0 MC.cfg
\* never reached a 3-voter Leader: MCAppendJointConfig coverage 0:0).
LogLE(a, b) == a = b \/ (~a.present /\ ~b.present) \/ LogLT(a, b)

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
\* code: core/raft_core.rs:1986-2012 (voter_count; pre-vote only when > 1)
\* update: Update!TickPreVoteContext
MultiVoter(i, cfg) == Cardinality(ConfigVoters(cfg)) > 1

(***************************************************************************
 * Messages.  "PreVoteReq"/"PreVoteResp" are added by the update.  For a    *
 * PreVoteResp the `vote` field carries the pre-candidate vote that the     *
 * response answers (Notification::PreVoteResponse.candidate_vote,          *
 * core/notification.rs:34-44, raft_core.rs:1440-1458); the responder's own *
 * VoteResponse.vote is never read by handle_pre_vote_resp                  *
 * (engine_impl.rs:516-554) and is therefore abstracted away.               *
 *************************************************************************)
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
    \* code: engine/engine_impl.rs:95-101 (Engine.pre_candidate),
    \*       engine/engine_impl.rs:149-165 (new_pre_candidate),
    \*       engine/command.rs:138-142 (Command::SendPreVote)
    \* update: Update!PreVoteState
    preCandidateActive,     \* Engine.pre_candidate.is_some()
    preCandidateVote,       \* pre_candidate.vote_ref(): (term+1, self, uncommitted)
    preCandidateLastLog,    \* pre_candidate.last_log_id()
    preCandidateConfig,     \* frozen effective membership quorum set of the round
    preGrants,              \* pre_candidate.granters()
    sendPreVotePending,     \* queued Command::SendPreVote not yet fully dispatched
    preSentReq,             \* targets already reached by the SendPreVote dispatch
    preStartRole            \* ghost observer: server_state when the round started

voteVars == <<vote, durableVote, votePersistPending, replyPending, replyMessage,
              sendVotePending, leaseValid>>
candidateVars == <<candidateActive, candidateVote, candidateConfig, grants, sentVoteReq>>
leaderVars == <<leaderActive, leaderVote, leaderCertified, leaderConfig, leaderGrants>>
logVars == <<lastLog, durableLastLog, logFlushPending>>
configVars == <<committedConfig, committedConfigIndex, effectiveConfig,
                effectiveConfigIndex, durableConfig, durableConfigIndex>>
runtimeVars == <<role, crashed, seenGreaterLog>>
preVoteVars == <<preCandidateActive, preCandidateVote, preCandidateLastLog,
                 preCandidateConfig, preGrants, sendPreVotePending, preSentReq,
                 preStartRole>>
vars == <<runtimeVars, voteVars, candidateVars, leaderVars, logVars, configVars,
          messages, preVoteVars>>

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
    \* engine/engine_impl.rs:117 (Engine::new: pre_candidate: None)
    /\ preCandidateActive = [i \in Server |-> FALSE]
    /\ preCandidateVote = [i \in Server |-> DefaultVote(i)]
    /\ preCandidateLastLog = [i \in Server |-> NoLog(i)]
    /\ preCandidateConfig = [i \in Server |-> <<InitialConfig>>]
    /\ preGrants = [i \in Server |-> {}]
    /\ sendPreVotePending = [i \in Server |-> FALSE]
    /\ preSentReq = [i \in Server |-> {}]
    /\ preStartRole = [i \in Server |-> "None"]

(***************************************************************************
 * Pre-candidate clearing.  `*pre_candidate = None` occurs only in          *
 * do_elect (engine_impl.rs:263-264), become_following                      *
 * (vote_handler/mod.rs:234-249), and by reconstruction on restart          *
 * (Engine::new, engine_impl.rs:117).  establish_leader/become_leader do    *
 * NOT clear it.  Inactive fields are canonicalised.                        *
 *************************************************************************)
\* UPDATE-MAP
\* code: engine/engine_impl.rs:263-264, engine/handler/vote_handler/mod.rs:244
\* update: Update!PreVoteClearingContext
PreVoteCleared(i) ==
    /\ preCandidateActive' = [preCandidateActive EXCEPT ![i] = FALSE]
    /\ preCandidateVote' = [preCandidateVote EXCEPT ![i] = DefaultVote(i)]
    /\ preCandidateLastLog' = [preCandidateLastLog EXCEPT ![i] = NoLog(i)]
    /\ preCandidateConfig' = [preCandidateConfig EXCEPT ![i] = <<InitialConfig>>]
    /\ preGrants' = [preGrants EXCEPT ![i] = {}]
    /\ sendPreVotePending' = [sendPreVotePending EXCEPT ![i] = FALSE]
    /\ preSentReq' = [preSentReq EXCEPT ![i] = {}]
    /\ preStartRole' = [preStartRole EXCEPT ![i] = "None"]

PreVoteClearedIf(i, cond) ==
    IF cond THEN PreVoteCleared(i) ELSE UNCHANGED preVoteVars

(***************************************************************************
 * Election engine transition (Engine::do_elect).  Candidate membership and *
 * last log are snapshotted before the pending self vote is installed.      *
 * SaveVote is queued before SendVote.  The update makes do_elect discard   *
 * any in-flight Pre-Vote round first.                                       *
 * openraft/src/engine/engine_impl.rs:121-140,262-289                       *
 * openraft/src/engine/handler/vote_handler/mod.rs:106-149                  *
 * A caller that is not contained in its effective membership is moved to   *
 * following state by update_internal_server_state (vote_handler:154-162);  *
 * the guarded tick/external callers always satisfy InConfig, only the      *
 * pre-vote quorum caller (engine_impl.rs:535-539) has no voter check.      *
 *************************************************************************)
\* UPDATE-MAP
\* code: engine/engine_impl.rs:262-289 (do_elect clears pre_candidate)
\* update: Update!AffectedActions (DoElect reached via StartElection and
\*         via HandlePreVoteResponse)
DoElect(i) ==
    LET nv == Vote(vote[i].term + 1, i, FALSE)
        stays == InConfig(i, effectiveConfig[i])
    IN
    /\ vote' = [vote EXCEPT ![i] = nv]
    /\ candidateActive' = [candidateActive EXCEPT ![i] = stays]
    /\ candidateVote' = [candidateVote EXCEPT ![i] = nv]
    /\ candidateConfig' = [candidateConfig EXCEPT ![i] = effectiveConfig[i]]
    /\ grants' = [grants EXCEPT ![i] = {}]
    /\ sentVoteReq' = [sentVoteReq EXCEPT ![i] = {}]
    /\ role' = [role EXCEPT ![i] = RoleFrom(i, nv, effectiveConfig[i])]
    /\ leaderActive' = [leaderActive EXCEPT ![i] = IF stays THEN @ ELSE FALSE]
    /\ votePersistPending' = [votePersistPending EXCEPT ![i] = TRUE]
    /\ sendVotePending' = [sendVotePending EXCEPT ![i] = TRUE]
    /\ leaseValid' = [leaseValid EXCEPT ![i] = FALSE]
    /\ PreVoteCleared(i)

ElectGuard(i) ==
    /\ ~crashed[i]
    /\ InConfig(i, effectiveConfig[i])
    /\ vote[i].term < MaxTerm
    /\ ~votePersistPending[i]
    /\ ~replyPending[i]

\* `resetGreater` models RaftCore::handle_tick_election's reset_greater_log()
\* (core/raft_core.rs:2026-2027); direct engine/external calls do not reset it.
StartElection(i, transfer, resetGreater) ==
    /\ ElectGuard(i)
    /\ DoElect(i)
    /\ seenGreaterLog' = [seenGreaterLog EXCEPT ![i] = IF resetGreater THEN FALSE ELSE @]
    /\ UNCHANGED <<durableVote, replyPending, replyMessage, leaderVote,
                    leaderCertified, leaderConfig, leaderGrants,
                    logVars, configVars, messages, crashed>>

(***************************************************************************
 * Engine::pre_elect (UPDATE).  Builds a pre-candidate for (term+1, self)   *
 * from the effective membership and last log, self-grants, and either     *
 * elects at once when the self grant is a quorum or queues SendPreVote.    *
 * vote, role, lease, and the real candidate are untouched.                  *
 * openraft/src/engine/engine_impl.rs:149-165,298-322                       *
 * The term bound is a model bound for the hypothetical term + 1.           *
 *************************************************************************)
\* UPDATE-MAP
\* code: engine/engine_impl.rs:298-322 (pre_elect), 149-165 (new_pre_candidate)
\* update: Update!AffectedActions (MCTickPreElect, MCExternalPreElect)
PreElect(i, resetGreater) ==
    /\ ElectGuard(i)
    /\ LET pv == Vote(vote[i].term + 1, i, FALSE)
           cfg == effectiveConfig[i]
       IN
       IF IsQuorum(cfg, {i})
       THEN \* engine_impl.rs:308-315: a self quorum calls elect() at once;
            \* do_elect discards the just-created pre-candidate.
            /\ DoElect(i)
            /\ UNCHANGED <<durableVote, replyPending, replyMessage, leaderVote,
                            leaderCertified, leaderConfig, leaderGrants,
                            logVars, configVars, messages, crashed>>
       ELSE \* engine_impl.rs:303-306,317-321: pre-candidate + SendPreVote
            /\ preCandidateActive' = [preCandidateActive EXCEPT ![i] = TRUE]
            /\ preCandidateVote' = [preCandidateVote EXCEPT ![i] = pv]
            /\ preCandidateLastLog' = [preCandidateLastLog EXCEPT ![i] = lastLog[i]]
            /\ preCandidateConfig' = [preCandidateConfig EXCEPT ![i] = cfg]
            /\ preGrants' = [preGrants EXCEPT ![i] = {i}]
            /\ sendPreVotePending' = [sendPreVotePending EXCEPT ![i] = TRUE]
            /\ preSentReq' = [preSentReq EXCEPT ![i] = {}]
            /\ preStartRole' = [preStartRole EXCEPT ![i] = role[i]]
            /\ UNCHANGED <<role, crashed, voteVars, candidateVars, leaderVars,
                            logVars, configVars, messages>>
    /\ seenGreaterLog' = [seenGreaterLog EXCEPT ![i] = IF resetGreater THEN FALSE ELSE @]

(***************************************************************************
 * RaftCore::handle_tick_election.  Skips leaders and non-voters; after the *
 * (abstracted) timeout check, resets seen_greater_log and either pre-votes *
 * (runtime flag set and more than one voter) or elects.  The "round still  *
 * in flight" rate limit (raft_core.rs:2014-2024) is a timing guard and is  *
 * abstracted to nondeterminism: a tick may restart a round at any time.    *
 * openraft/src/core/raft_core.rs:1959-2036                                 *
 *************************************************************************)
\* UPDATE-MAP
\* code: core/raft_core.rs:1981-2035
\* update: Update!AffectedActions (MCTickElect/MCTickPreElect)
TickElect(i) ==
    /\ role[i] /= "Leader"
    /\ (FALSE \in PreVoteSetting \/ ~MultiVoter(i, effectiveConfig[i]))
    /\ StartElection(i, FALSE, TRUE)

TickPreElect(i) ==
    /\ role[i] /= "Leader"
    /\ TRUE \in PreVoteSetting
    /\ MultiVoter(i, effectiveConfig[i])
    /\ PreElect(i, TRUE)

(***************************************************************************
 * ExternalCommand::Elect { pre_vote } (UPDATE adds the flag).  is_voter is  *
 * checked; there is no leader check (TODO at raft_core.rs:1685).           *
 * openraft/src/core/raft_core.rs:1683-1697, raft/trigger.rs:45-63          *
 *************************************************************************)
\* UPDATE-MAP
\* code: core/raft_core.rs:1683-1697, core/raft_msg/external_command.rs:25-37
\* update: Update!AffectedActions (MCExternalPreElect)
ExternalElect(i) == StartElection(i, FALSE, FALSE)
ExternalPreElect(i) == PreElect(i, FALSE)
StartTransferElection(i) == StartElection(i, TRUE, FALSE)

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

(***************************************************************************
 * Runtime dispatch of Command::SendPreVote (UPDATE): the same parallel     *
 * spawner as SendVote, selecting RaftNetworkV2::pre_vote.  No SaveVote     *
 * precedes it, so no durability guard applies.  Transport errors and RPC   *
 * timeouts are not grants (raft_core.rs:1458-1472): in the model they are  *
 * message loss.  The default network impl that synthesizes a grant         *
 * (network/v2/network.rs:141-161) is outside the modelled transport.       *
 * openraft/src/core/raft_core.rs:1385-1478,2342-2344                       *
 *************************************************************************)
\* UPDATE-MAP
\* code: core/raft_core.rs:1385-1478 (spawn_parallel_vote_requests, PreVote kind),
\*       core/raft_core.rs:2342-2344 (Command::SendPreVote)
\* update: Update!AffectedActions (SendPreVoteRequest, FinishPreVoteBroadcast)
SendPreVoteRequest(i, j) ==
    /\ ~crashed[i]
    /\ preCandidateActive[i]
    /\ sendPreVotePending[i]
    /\ j \in ConfigVoters(preCandidateConfig[i]) \ {i}
    /\ j \notin preSentReq[i]
    /\ messages' = messages \cup
          {Message("PreVoteReq", i, j, preCandidateVote[i], preCandidateLastLog[i], FALSE, FALSE)}
    /\ preSentReq' = [preSentReq EXCEPT ![i] = @ \cup {j}]
    /\ UNCHANGED <<runtimeVars, voteVars, candidateVars, leaderVars, logVars,
                    configVars, preCandidateActive, preCandidateVote,
                    preCandidateLastLog, preCandidateConfig, preGrants,
                    sendPreVotePending, preStartRole>>

FinishPreVoteBroadcast(i) ==
    /\ sendPreVotePending[i]
    /\ ConfigVoters(preCandidateConfig[i]) \ {i} \subseteq preSentReq[i]
    /\ sendPreVotePending' = [sendPreVotePending EXCEPT ![i] = FALSE]
    /\ UNCHANGED <<runtimeVars, voteVars, candidateVars, leaderVars, logVars,
                    configVars, messages, preCandidateActive, preCandidateVote,
                    preCandidateLastLog, preCandidateConfig, preGrants,
                    preSentReq, preStartRole>>

RemainingMessages(m, consume) == IF consume THEN messages \ {m} ELSE messages

(***************************************************************************
 * Guard order is lease, then last-log, then vote comparison. Strict vote   *
 * changes defer the response until persistence; equal votes merely touch   *
 * the lease and can reply immediately.  A successful update_vote calls     *
 * update_internal_server_state, whose following branch now also clears the *
 * pre-candidate (UPDATE).                                                  *
 * openraft/src/engine/engine_impl.rs:350-402                               *
 * openraft/src/engine/handler/vote_handler/mod.rs:106-162,234-249          *
 * openraft/src/core/raft_core.rs:1532-1549                                 *
 *************************************************************************)
\* UPDATE-MAP
\* code: engine/handler/vote_handler/mod.rs:244 (become_following clears pre_candidate)
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
       /\ leaderActive' = [leaderActive EXCEPT ![i] = IF follows THEN FALSE
                                                      ELSE IF grant /\ nv.committed /\ nv.node = i
                                                           THEN TRUE ELSE @]
       /\ leaderVote' = [leaderVote EXCEPT ![i] = IF grant /\ nv.committed /\ nv.node = i
                                                  THEN nv ELSE @]
       /\ PreVoteClearedIf(i, follows)
    /\ UNCHANGED <<durableVote, sendVotePending, candidateVote, candidateConfig,
                    grants, sentVoteReq, leaderCertified, leaderConfig,
                    leaderGrants, logVars, configVars, crashed, seenGreaterLog>>

DeliverVoteRequest(m) ==
    /\ m \in messages
    /\ HandleVoteRequest(m.dest, m, TRUE)

(***************************************************************************
 * Engine::handle_pre_vote_req (UPDATE).  Same lease and last-log guards as *
 * handle_vote_req except that the lease is always honoured (no transfer   *
 * bypass); the order check is `req.vote >= local vote`.  Nothing is        *
 * mutated and no command other than an unconditional Respond is emitted.   *
 * The runtime responds without waiting for vote I/O.                       *
 * openraft/src/engine/engine_impl.rs:414-447                               *
 * openraft/src/core/raft_core.rs:1551-1562,1603-1607                       *
 *************************************************************************)
\* UPDATE-MAP
\* code: engine/engine_impl.rs:414-447, core/raft_core.rs:1551-1562
\* update: Update!AffectedActions (DeliverPreVoteRequest), Update!PreVoteRequestPure
HandlePreVoteRequest(i, m, consume) ==
    /\ ~crashed[i]
    /\ m.kind = "PreVoteReq"
    /\ m.dest = i
    /\ ~votePersistPending[i]
    /\ ~replyPending[i]
    /\ LET leaseBlocked == vote[i].committed /\ leaseValid[i]   \* engine_impl.rs:427-432
           logOK == LogLE(lastLog[i], m.lastLog)              \* engine_impl.rs:434-442
           orderOK == VoteLE(vote[i], m.vote)                 \* engine_impl.rs:444-446
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
 * committed vote persistence remains pending.  establish_leader does not   *
 * touch Engine.pre_candidate (engine_impl.rs:855-881); only a rejected    *
 * response adopting another node's vote reaches become_following.         *
 * openraft/src/engine/engine_impl.rs:450-506,855-881                       *
 * openraft/src/proposer/candidate.rs:97-133                                *
 *************************************************************************)
\* UPDATE-MAP
\* code: engine/engine_impl.rs:855-881 (establish_leader leaves pre_candidate),
\*       engine/handler/vote_handler/mod.rs:244 (adopt -> become_following)
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
       \* REPAIR (prior-model defect): update_vote installs the leader lease for a
       \* committed vote and a zero lease for an uncommitted one
       \* (engine/handler/vote_handler/mod.rs:126-136, engine_impl.rs:872).
       /\ leaseValid' = [leaseValid EXCEPT ![i] = IF wins THEN TRUE ELSE IF adopt THEN FALSE ELSE @]
       /\ lastLog' = [lastLog EXCEPT ![i] = IF wins /\ newIndex <= MaxLogIndex
                                              THEN Log(cv.term, cv.node, newIndex) ELSE @]
       /\ logFlushPending' = [logFlushPending EXCEPT ![i] = IF wins /\ newIndex <= MaxLogIndex
                                                                THEN TRUE ELSE @]
       /\ seenGreaterLog' = [seenGreaterLog EXCEPT ![i] =
                                IF candidateActive[i] /\ ~exact /\ LogLT(lastLog[i], m.lastLog)
                                THEN TRUE ELSE @]
       /\ PreVoteClearedIf(i, adopt /\ stripped.node /= i)
    /\ UNCHANGED <<durableVote, replyPending, replyMessage,
                    candidateVote, candidateConfig, sentVoteReq, durableLastLog,
                    configVars, crashed>>

DeliverVoteResponse(m) ==
    /\ m \in messages
    /\ HandleVoteResponse(m.dest, m, TRUE)

(***************************************************************************
 * Notification::PreVoteResponse + Engine::handle_pre_vote_resp (UPDATE).   *
 * The runtime drops the notification unless a pre-candidate exists whose  *
 * leader id equals the response's candidate_vote leader id.  A grant      *
 * advances the frozen pre-vote quorum; a quorum calls elect().  A          *
 * rejection only records a greater last log.  The local vote is never     *
 * updated from a pre-vote response.                                        *
 * openraft/src/core/raft_core.rs:1803-1820,2066-2090                       *
 * openraft/src/engine/engine_impl.rs:516-554                               *
 *************************************************************************)
\* UPDATE-MAP
\* code: core/raft_core.rs:1803-1820,2066-2090; engine/engine_impl.rs:516-554
\* update: Update!AffectedActions (DeliverPreVoteResponse),
\*         Update!PreVoteNeverDemotesLeader
HandlePreVoteResponse(i, m, consume) ==
    /\ ~crashed[i]
    /\ m.kind = "PreVoteResp"
    /\ m.dest = i
    /\ ~votePersistPending[i]
    /\ ~replyPending[i]
    /\ LET matches == /\ preCandidateActive[i]
                      /\ m.vote.term = preCandidateVote[i].term
                      /\ m.vote.node = preCandidateVote[i].node
           ng == preGrants[i] \cup {m.source}
           wins == matches /\ m.granted /\ IsQuorum(preCandidateConfig[i], ng)
           greater == matches /\ ~m.granted /\ LogLT(lastLog[i], m.lastLog)
       IN
       IF wins
       THEN \* engine_impl.rs:534-539: quorum -> self.elect()
            /\ vote[i].term < MaxTerm
            /\ DoElect(i)
            /\ messages' = RemainingMessages(m, consume)
            /\ UNCHANGED <<durableVote, replyPending, replyMessage, leaderVote,
                            leaderCertified, leaderConfig, leaderGrants,
                            logVars, configVars, crashed, seenGreaterLog>>
       ELSE /\ preGrants' = [preGrants EXCEPT ![i] = IF matches /\ m.granted THEN ng ELSE @]
            /\ seenGreaterLog' = [seenGreaterLog EXCEPT ![i] = IF greater THEN TRUE ELSE @]
            /\ messages' = RemainingMessages(m, consume)
            /\ UNCHANGED <<role, crashed, voteVars, candidateVars, leaderVars,
                            logVars, configVars, preCandidateActive,
                            preCandidateVote, preCandidateLastLog,
                            preCandidateConfig, sendPreVotePending, preSentReq,
                            preStartRole>>

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
 * refresh_server_state -> update_internal_server_state; its following     *
 * branch now clears the pre-candidate (UPDATE).                            *
 * openraft/src/engine/engine_impl.rs:644-673                               *
 *************************************************************************)
CommitMembership(i) ==
    /\ ~crashed[i]
    /\ committedConfigIndex[i] < effectiveConfigIndex[i]
    /\ committedConfig' = [committedConfig EXCEPT ![i] = effectiveConfig[i]]
    /\ committedConfigIndex' = [committedConfigIndex EXCEPT ![i] = effectiveConfigIndex[i]]
    /\ UNCHANGED <<runtimeVars, voteVars, candidateVars, leaderVars, logVars,
                    effectiveConfig, effectiveConfigIndex, durableConfig,
                    durableConfigIndex, messages, preVoteVars>>

\* UPDATE-MAP
\* code: engine/engine_impl.rs:660-673 -> vote_handler/mod.rs:154-162,244
\* update: Update!InteractionActions (RefreshServerState)
RefreshServerState(i) ==
    /\ ~crashed[i]
    /\ committedConfigIndex[i] = effectiveConfigIndex[i]
    /\ role' = [role EXCEPT ![i] = RoleFrom(i, vote[i], effectiveConfig[i])]
    /\ leaderActive' = [leaderActive EXCEPT ![i] = IF RoleFrom(i, vote[i], effectiveConfig[i]) = "Leader"
                                                    THEN @ ELSE FALSE]
    /\ candidateActive' = [candidateActive EXCEPT ![i] =
                              IF RoleFrom(i, vote[i], effectiveConfig[i]) = "Candidate" THEN @ ELSE FALSE]
    /\ PreVoteClearedIf(i, RoleFrom(i, vote[i], effectiveConfig[i]) \notin {"Leader", "Candidate"})
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
    /\ UNCHANGED <<runtimeVars, voteVars, candidateVars, leaderVars, lastLog,
                    committedConfig, committedConfigIndex, effectiveConfig,
                    effectiveConfigIndex, messages, preVoteVars>>

(***************************************************************************
 * A leader may dispatch replication after the committed vote is durable.   *
 * Append return makes the log readable before its later flush callback.    *
 * openraft/src/core/raft_core.rs:2259-2273,2361-2364                       *
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
 * AppendEntries first runs update_vote; a vote of another node reaches     *
 * become_following, which now also clears the pre-candidate (UPDATE).      *
 * openraft/src/engine/engine_impl.rs:556-600                               *
 * openraft/src/engine/handler/vote_handler/mod.rs:106-162,234-249          *
 *************************************************************************)
\* UPDATE-MAP
\* code: engine/engine_impl.rs:586-600 -> vote_handler/mod.rs:244
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
       /\ leaderActive' = [leaderActive EXCEPT ![i] = IF m.vote.node = i /\ m.vote.committed
                                                      THEN TRUE ELSE FALSE]
       /\ leaderVote' = [leaderVote EXCEPT ![i] = IF m.vote.node = i /\ m.vote.committed
                                                  THEN m.vote ELSE @]
       /\ PreVoteClearedIf(i, m.vote.node /= i)
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

\* UPDATE-MAP
\* code: engine/engine_impl.rs:107-120 (Engine::new: pre_candidate None)
\* update: Update!PreVoteClearingContext
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
    /\ PreVoteCleared(i)
    /\ UNCHANGED <<durableVote, durableLastLog, durableConfig, durableConfigIndex, messages>>

Next ==
    \/ \E i \in Server : TickElect(i) \/ ExternalElect(i) \/ StartTransferElection(i)
    \/ \E i \in Server : TickPreElect(i) \/ ExternalPreElect(i)
    \/ \E i \in Server : PersistVote(i) \/ FinishVoteBroadcast(i) \/ FlushLog(i)
    \/ \E i \in Server : FinishPreVoteBroadcast(i)
    \/ \E i \in Server : ExpireLease(i) \/ Restart(i) \/ RefreshServerState(i)
    \/ \E i \in Server, j \in Server : SendVoteRequest(i, j) \/ SendAppendEntries(i, j)
    \/ \E i \in Server, j \in Server : SendPreVoteRequest(i, j)
    \/ \E m \in messages : DeliverVoteRequest(m) \/ DeliverVoteResponse(m)
                              \/ DeliverAppendEntries(m) \/ DropMessage(m)
    \/ \E m \in messages : DeliverPreVoteRequest(m) \/ DeliverPreVoteResponse(m)
    \/ \E i \in Server, target \in SUBSET Server : AppendJointConfig(i, target)
    \/ \E i \in Server : AppendUniformConfig(i) \/ CommitMembership(i) \/ Crash(i)

Spec == Init /\ [][Next]_vars

VoteDomain == [term : 0..MaxTerm, node : Server, committed : BOOLEAN]
LogDomainOK(l) ==
    /\ l.present \in BOOLEAN
    /\ l.term \in 0..MaxTerm
    /\ l.node \in Server
    /\ l.index \in 0..MaxLogIndex

\* UPDATE-MAP (TypeOK modified: new pre-vote state and message kinds)
\* code: engine/engine_impl.rs:95-101, core/raft_msg/mod.rs:69-73
\* update: Update!PreVoteState
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
    /\ leaderActive \in [Server -> BOOLEAN]
    /\ leaderVote \in [Server -> VoteDomain]
    /\ leaderCertified \in [Server -> BOOLEAN]
    /\ \A i \in Server : IsConfig(leaderConfig[i])
    /\ leaderGrants \in [Server -> SUBSET Server]
    /\ \A i \in Server : LogDomainOK(lastLog[i]) /\ LogDomainOK(durableLastLog[i])
    /\ logFlushPending \in [Server -> BOOLEAN]
    /\ \A i \in Server : IsConfig(committedConfig[i]) /\ IsConfig(effectiveConfig[i])
                           /\ IsConfig(durableConfig[i])
    /\ committedConfigIndex \in [Server -> 0..MaxLogIndex]
    /\ effectiveConfigIndex \in [Server -> 0..MaxLogIndex]
    /\ durableConfigIndex \in [Server -> 0..MaxLogIndex]
    /\ crashed \in [Server -> BOOLEAN]
    /\ seenGreaterLog \in [Server -> BOOLEAN]
    /\ preCandidateActive \in [Server -> BOOLEAN]
    /\ preCandidateVote \in [Server -> VoteDomain]
    /\ \A i \in Server : LogDomainOK(preCandidateLastLog[i])
    /\ \A i \in Server : IsConfig(preCandidateConfig[i])
    /\ preGrants \in [Server -> SUBSET Server]
    /\ sendPreVotePending \in [Server -> BOOLEAN]
    /\ preSentReq \in [Server -> SUBSET Server]
    /\ preStartRole \in [Server -> {"None", "Learner", "Follower", "Candidate", "Leader"}]
    /\ \A m \in messages :
          /\ m.kind \in {"VoteReq", "VoteResp", "Append", "PreVoteReq", "PreVoteResp"}
          /\ m.source \in Server /\ m.dest \in Server
          /\ m.vote \in VoteDomain
          /\ LogDomainOK(m.lastLog)
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
