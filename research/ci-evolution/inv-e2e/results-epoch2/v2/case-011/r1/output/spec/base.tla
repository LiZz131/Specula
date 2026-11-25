------------------------------ MODULE base ------------------------------
(***************************************************************************
 * OpenRaft election reference model, updated for the Pre-Vote revision.   *
 *                                                                         *
 * V0 source boundary: engine/engine_impl.rs,                              *
 * engine/handler/vote_handler/mod.rs, core/raft_core.rs,                  *
 * raft_state/membership_state/mod.rs, and proposer/candidate.rs.          *
 *                                                                         *
 * Update (synthetic commit `update`): an optional Pre-Vote round          *
 * (Engine::pre_elect / handle_pre_vote_req / handle_pre_vote_resp, a      *
 * separate `pre_candidate` tracker, Command::SendPreVote, the RaftNetwork *
 * `pre_vote` RPC with a granting default, tick/external triggers, and     *
 * clearing of `pre_candidate` in do_elect and become_following).          *
 * Line numbers below refer to the updated tree unless marked "old".       *
 *************************************************************************)

EXTENDS Integers, Naturals, FiniteSets, Sequences, TLC

CONSTANTS Server, NodeOrder, MaxTerm, MaxLogIndex, InitialConfig,
          PreVoteTickModes, PreVoteRpcDefaultGrant

ReferenceServer == {"1", "2", "3"}
ReferenceNodeOrder == <<"1", "2", "3">>
ReferenceInitialConfig == {"1", "2", "3"}

\* UPDATE-MAP
\* code: openraft/src/config/config.rs:397-427 (Config::enable_pre_vote, get_enable_pre_vote)
\* code: openraft/src/config/runtime_config.rs:11,19; openraft/src/raft/runtime_config_handle.rs:46-53
\* code: openraft/src/network/v2/network.rs:141-161 (default RaftNetworkV2::pre_vote grants)
\* update: Update!AffectedActions (TickPreVote/TickElect mode split, DefaultPreVoteRpcGrant)
\* PreVoteTickModes is the set of choices the election tick may make: FALSE
\* is the direct election, TRUE is a Pre-Vote round. {FALSE} is the shipped
\* default (enable_pre_vote = None), {TRUE} is Some(true), and {FALSE, TRUE}
\* models the RuntimeConfigHandle::pre_vote toggle. PreVoteRpcDefaultGrant
\* enables the network's default `pre_vote`, which synthesizes a grant.
ASSUME /\ Server /= {}
       /\ Len(NodeOrder) = Cardinality(Server)
       /\ {NodeOrder[k] : k \in 1..Len(NodeOrder)} = Server
       /\ InitialConfig \subseteq Server
       /\ InitialConfig /= {}
       /\ MaxTerm \in Nat \ {0}
       /\ MaxLogIndex \in Nat \ {0}
       /\ PreVoteTickModes \subseteq BOOLEAN
       /\ PreVoteTickModes /= {}
       /\ PreVoteRpcDefaultGrant \in BOOLEAN

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

\* Leader-id equality (term,node), ignoring the committed bit, as used by
\* does_candidate_vote_match / does_pre_candidate_vote_match.
\* openraft/src/core/raft_core.rs:2067-2090
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

\* Repair (V0 defect, both revisions): an absent last log is Option::None, and
\* None == None in Rust's Option ordering regardless of the node tag that
\* NoLog(i) carries for trace mapping. V0 compared NoLog(i) /= NoLog(j) as
\* unordered, so every vote/pre-vote request between nodes with empty logs
\* failed the last-log check. engine_impl.rs:379,434 (old 302) compare
\* Option<&LogId> values (core::option::Option: PartialOrd, None < Some).
LogLE(a, b) == ~a.present \/ a = b \/ LogLT(a, b)

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
\* code: openraft/src/core/notification.rs:34-44 (PreVoteResponse carries candidate_vote)
\* update: Update!PreVoteElectionAtProbedVote, Update!PreVoteGrantFromTrackedVoter
\* Every message carries `reqVote`: the vote of the request it answers. For
\* the V0 kinds it equals `vote`; a PreVoteResp carries the responder's vote
\* in `vote` and the pre-candidate's probed vote in `reqVote`.
MessageR(kind, source, dest, v, lg, granted, transfer, rv) ==
    [kind |-> kind,
     source |-> source,
     dest |-> dest,
     vote |-> v,
     lastLog |-> lg,
     granted |-> granted,
     transfer |-> transfer,
     reqVote |-> rv]

Message(kind, source, dest, v, lg, granted, transfer) ==
    MessageR(kind, source, dest, v, lg, granted, transfer, v)

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
    \* code: openraft/src/engine/engine_impl.rs:95-101,149-165 (Engine::pre_candidate)
    \* update: Update!AffectedActions, Update!InteractionActions
    preCandidateActive,
    preCandidateVote,
    preCandidateConfig,
    preGrants,
    \* History variable (no behavioral effect): whether the current Pre-Vote
    \* round was started while the node's cached role was Leader. Used only by
    \* Update!PreVoteRoundNotOutlivedByOwnLeadership.
    preRoundFromLeader

voteVars == <<vote, durableVote, votePersistPending, replyPending, replyMessage,
              sendVotePending, leaseValid>>
candidateVars == <<candidateActive, candidateVote, candidateConfig, grants, sentVoteReq>>
leaderVars == <<leaderActive, leaderVote, leaderCertified, leaderConfig, leaderGrants>>
logVars == <<lastLog, durableLastLog, logFlushPending>>
configVars == <<committedConfig, committedConfigIndex, effectiveConfig,
                effectiveConfigIndex, durableConfig, durableConfigIndex>>
runtimeVars == <<role, crashed, seenGreaterLog>>
preVars == <<preCandidateActive, preCandidateVote, preCandidateConfig, preGrants,
             preRoundFromLeader>>
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
    /\ preGrants = [i \in Server |-> {}]
    /\ preRoundFromLeader = [i \in Server |-> FALSE]

(***************************************************************************
 * Dropping `Engine::pre_candidate` (set to None). Called with cond = TRUE   *
 * by do_elect and by VoteHandler::become_following; every field returns to *
 * its canonical default so absent trackers compare equal.                   *
 * openraft/src/engine/engine_impl.rs:263-264                               *
 * openraft/src/engine/handler/vote_handler/mod.rs:234-249                  *
 *************************************************************************)
\* UPDATE-MAP
\* code: openraft/src/engine/handler/vote_handler/mod.rs:244; engine_impl.rs:263-264
\* update: Update!AffectedActions
PreCleared(i, cond) ==
    /\ preCandidateActive' = [preCandidateActive EXCEPT ![i] = IF cond THEN FALSE ELSE @]
    /\ preCandidateVote' = [preCandidateVote EXCEPT ![i] = IF cond THEN DefaultVote(i) ELSE @]
    /\ preCandidateConfig' = [preCandidateConfig EXCEPT ![i] = IF cond THEN <<InitialConfig>> ELSE @]
    /\ preGrants' = [preGrants EXCEPT ![i] = IF cond THEN {} ELSE @]
    /\ preRoundFromLeader' = [preRoundFromLeader EXCEPT ![i] = IF cond THEN FALSE ELSE @]

VoterCount(i) == Cardinality(ConfigVoters(effectiveConfig[i]))

(***************************************************************************
 * Engine::do_elect. Candidate membership and last log are snapshotted       *
 * before the pending self vote is installed. SaveVote is queued before     *
 * SendVote. The update drops any in-flight Pre-Vote round first.           *
 * do_elect itself has no voter guard: update_vote() ->                     *
 * update_internal_server_state() keeps the new candidate only while the    *
 * node is contained in the effective membership, else become_following()   *
 * clears leader/candidate/pre_candidate. seen_greater_log is not reset     *
 * here; the tick handler resets it before calling the engine.               *
 * The caller supplies messages'.                                            *
 * openraft/src/engine/engine_impl.rs:262-289,125-139                       *
 * openraft/src/engine/handler/vote_handler/mod.rs:106-162,234-249          *
 *************************************************************************)
\* UPDATE-MAP
\* code: openraft/src/engine/engine_impl.rs:262-289 (do_elect clears pre_candidate)
\* update: Update!AffectedActions (MCTickElect, MCExternalElect, PreVoteElect branch)
DoElect(i, sgl) ==
    LET nv == Vote(vote[i].term + 1, i, FALSE)
        member == InConfig(i, effectiveConfig[i])
    IN
    /\ vote' = [vote EXCEPT ![i] = nv]
    /\ candidateActive' = [candidateActive EXCEPT ![i] = member]
    /\ candidateVote' = [candidateVote EXCEPT ![i] = nv]
    /\ candidateConfig' = [candidateConfig EXCEPT ![i] = effectiveConfig[i]]
    /\ grants' = [grants EXCEPT ![i] = {}]
    /\ sentVoteReq' = [sentVoteReq EXCEPT ![i] = {}]
    /\ role' = [role EXCEPT ![i] = RoleFrom(i, nv, effectiveConfig[i])]
    /\ votePersistPending' = [votePersistPending EXCEPT ![i] = TRUE]
    /\ sendVotePending' = [sendVotePending EXCEPT ![i] = TRUE]
    /\ leaseValid' = [leaseValid EXCEPT ![i] = FALSE]
    /\ seenGreaterLog' = [seenGreaterLog EXCEPT ![i] = sgl]
    \* become_following() (non-member) drops the Leader object; a member keeps it.
    /\ leaderActive' = [leaderActive EXCEPT ![i] = IF member THEN @ ELSE FALSE]
    /\ PreCleared(i, TRUE)
    /\ UNCHANGED <<durableVote, replyPending, replyMessage, leaderVote,
                    leaderCertified, leaderConfig, leaderGrants, logVars,
                    configVars, crashed>>

\* Runtime event serialization: RaftCore drains and awaits the engine
\* commands of one event (including save_vote) before it handles the next
\* event. openraft/src/core/raft_core.rs:1088-1148 (old numbering), 2273-2304
ElectGuard(i) ==
    /\ ~crashed[i]
    /\ InConfig(i, effectiveConfig[i])
    /\ vote[i].term < MaxTerm
    /\ ~votePersistPending[i]
    /\ ~replyPending[i]

(***************************************************************************
 * Engine::elect / elect_by_leadership_transfer reached from a caller that  *
 * checked the voter guard (ExternalCommand::Elect, HandleTransferLeader,   *
 * tick). The engine call leaves seen_greater_log unchanged.                *
 * openraft/src/engine/engine_impl.rs:249-260                               *
 * openraft/src/core/raft_core.rs:1665-1696                                 *
 *************************************************************************)
StartElection(i, transfer) ==
    /\ ElectGuard(i)
    /\ DoElect(i, seenGreaterLog[i])
    /\ UNCHANGED messages

(***************************************************************************
 * handle_tick_election: skip if Leader or not a voter; with Pre-Vote      *
 * enabled and more than one voter the tick runs pre_elect instead of       *
 * elect. The tick resets seen_greater_log before either call.             *
 * openraft/src/core/raft_core.rs:1959-2036                                 *
 *************************************************************************)
\* UPDATE-MAP
\* code: openraft/src/core/raft_core.rs:2010-2036 (pre_vote = enabled && voter_count > 1)
\* update: Update!AffectedActions (MCTickElect)
TickElect(i) ==
    /\ role[i] /= "Leader"
    /\ (FALSE \in PreVoteTickModes \/ VoterCount(i) = 1)
    /\ ElectGuard(i)
    /\ DoElect(i, FALSE)
    /\ UNCHANGED messages

ExternalElect(i) == StartElection(i, FALSE)
StartTransferElection(i) == StartElection(i, TRUE)

(***************************************************************************
 * Engine::pre_elect. The pre-candidate snapshots the effective membership  *
 * and last log, grants itself, and either elects at once (self is already  *
 * a quorum) or queues SendPreVote. It changes neither vote nor role and   *
 * queues no SaveVote. SendPreVote is executed in the same command batch and*
 * spawns one pre_vote RPC per current effective voter except self; the     *
 * broadcast is therefore emitted atomically here.                          *
 * openraft/src/engine/engine_impl.rs:291-322,143-165                       *
 * openraft/src/core/raft_core.rs:1385-1478,2342-2344                       *
 *************************************************************************)
\* UPDATE-MAP
\* code: openraft/src/engine/engine_impl.rs:291-322 (pre_elect)
\* update: Update!AffectedActions (MCTickPreVote, MCExternalPreElect)
PreElect(i, sgl) ==
    LET pv == Vote(vote[i].term + 1, i, FALSE)
        cfg == effectiveConfig[i]
    IN
    IF IsQuorum(cfg, {i})
    THEN /\ DoElect(i, sgl)
         /\ UNCHANGED messages
    ELSE /\ preCandidateActive' = [preCandidateActive EXCEPT ![i] = TRUE]
         /\ preCandidateVote' = [preCandidateVote EXCEPT ![i] = pv]
         /\ preCandidateConfig' = [preCandidateConfig EXCEPT ![i] = cfg]
         /\ preGrants' = [preGrants EXCEPT ![i] = {i}]
         /\ preRoundFromLeader' = [preRoundFromLeader EXCEPT ![i] = (role[i] = "Leader")]
         /\ messages' = messages \cup
               {MessageR("PreVoteReq", i, j, pv, lastLog[i], FALSE, FALSE, pv) :
                    j \in ConfigVoters(cfg) \ {i}}
         /\ seenGreaterLog' = [seenGreaterLog EXCEPT ![i] = sgl]
         /\ UNCHANGED <<role, crashed, voteVars, candidateVars, leaderVars,
                         logVars, configVars>>

PreVoteGuard(i) == ElectGuard(i)

\* Tick with Pre-Vote enabled (multi-voter only). The in-flight-round rate
\* limit (raft_core.rs:2014-2023) is time based; a new round may replace an
\* old one once election_timeout elapsed, so it is left unconstrained here.
TickPreVote(i) ==
    /\ role[i] /= "Leader"
    /\ TRUE \in PreVoteTickModes
    /\ VoterCount(i) > 1
    /\ PreVoteGuard(i)
    /\ PreElect(i, FALSE)

\* ExternalCommand::Elect { pre_vote: true }: voter check only.
\* openraft/src/core/raft_core.rs:1683-1696
ExternalPreElect(i) ==
    /\ PreVoteGuard(i)
    /\ PreElect(i, seenGreaterLog[i])

(***************************************************************************
 * save_vote() is awaited. A pending election gets a local granted response;
 * a vote-request reply held on IOFlushed becomes visible here.              *
 * openraft/src/core/raft_core.rs:2276-2304                                 *
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
                    candidateConfig, grants, leaderVars, logVars, configVars, preVars>>

FinishVoteBroadcast(i) ==
    /\ sendVotePending[i]
    /\ ConfigVoters(candidateConfig[i]) \ {i} \subseteq sentVoteReq[i]
    /\ sendVotePending' = [sendVotePending EXCEPT ![i] = FALSE]
    /\ UNCHANGED <<runtimeVars, vote, durableVote, votePersistPending,
                    replyPending, replyMessage, leaseValid, candidateVars,
                    leaderVars, logVars, configVars, messages, preVars>>

RemainingMessages(m, consume) == IF consume THEN messages \ {m} ELSE messages

(***************************************************************************
 * Guard order is lease, then last-log, then vote comparison. Strict vote   *
 * changes defer the response until persistence; equal votes merely touch   *
 * the lease and can reply immediately. A granted vote that names another   *
 * node (or a non-member self) reaches become_following(), which now also   *
 * drops pre_candidate.                                                     *
 * openraft/src/engine/engine_impl.rs:350-404                               *
 * openraft/src/engine/handler/vote_handler/mod.rs:106-162,234-249          *
 * openraft/src/core/raft_core.rs:1532-1549 (handle_vote_request)           *
 *************************************************************************)
VoteGrantable(i, v, lg, transfer) ==
    LET leaseBlocked == vote[i].committed /\ leaseValid[i] /\ ~transfer
    IN ~leaseBlocked /\ LogLE(lastLog[i], lg) /\ VoteLE(vote[i], v)

\* UPDATE-MAP
\* code: openraft/src/engine/handler/vote_handler/mod.rs:244 (become_following drops pre_candidate)
\* update: Update!AffectedActions (DeliverVoteRequest)
HandleVoteRequest(i, m, consume) ==
    /\ ~crashed[i]
    /\ m.kind = "VoteReq"
    /\ m.dest = i
    /\ ~votePersistPending[i]
    /\ ~replyPending[i]
    /\ LET grant == VoteGrantable(i, m.vote, m.lastLog, m.transfer)
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
       /\ PreCleared(i, follows)
    /\ UNCHANGED <<durableVote, sendVotePending, candidateVote, candidateConfig,
                    grants, sentVoteReq, leaderCertified, leaderConfig,
                    leaderGrants, logVars, configVars, crashed, seenGreaterLog>>

DeliverVoteRequest(m) ==
    /\ m \in messages
    /\ HandleVoteRequest(m.dest, m, TRUE)

(***************************************************************************
 * Exact granted vote equality advances the frozen quorum. Establishment    *
 * commits the vote in projected state and projects the leader blank log;   *
 * committed vote persistence remains pending. establish_leader() and       *
 * become_leader() do NOT touch pre_candidate, so an in-flight Pre-Vote      *
 * round survives the node's own election win. A higher rejected vote is    *
 * adopted through update_vote() -> become_following(), which drops it.      *
 * openraft/src/engine/engine_impl.rs:449-510,855-881                       *
 * openraft/src/engine/handler/vote_handler/mod.rs:154-162,173-229          *
 * openraft/src/proposer/candidate.rs:105-133                               *
 *************************************************************************)
\* UPDATE-MAP
\* code: openraft/src/engine/engine_impl.rs:855-881 (establish_leader keeps pre_candidate)
\* update: Update!PreVoteRoundNotOutlivedByOwnLeadership
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
       \* Repair (V0 defect): establish_leader -> update_vote(committed) installs the
       \* leader lease; adopting a stripped (uncommitted) vote installs a zero lease.
       \* openraft/src/engine/handler/vote_handler/mod.rs:126-136 (old: 125-135)
       /\ leaseValid' = [leaseValid EXCEPT ![i] = IF wins THEN TRUE ELSE IF adopt THEN FALSE ELSE @]
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
       /\ lastLog' = [lastLog EXCEPT ![i] = IF wins /\ newIndex <= MaxLogIndex
                                              THEN Log(cv.term, cv.node, newIndex) ELSE @]
       /\ logFlushPending' = [logFlushPending EXCEPT ![i] = IF wins /\ newIndex <= MaxLogIndex
                                                                THEN TRUE ELSE @]
       /\ seenGreaterLog' = [seenGreaterLog EXCEPT ![i] =
                                IF candidateActive[i] /\ ~exact /\ LogLT(lastLog[i], m.lastLog)
                                THEN TRUE ELSE @]
       \* establish_leader keeps pre_candidate; only become_following drops it.
       /\ PreCleared(i, adopt /\ stripped.node /= i)
    /\ UNCHANGED <<durableVote, replyPending, replyMessage,
                    candidateVote, candidateConfig, sentVoteReq, durableLastLog,
                    configVars, crashed>>

DeliverVoteResponse(m) ==
    /\ m \in messages
    /\ HandleVoteResponse(m.dest, m, TRUE)

(***************************************************************************
 * Engine::handle_pre_vote_req, reached from RaftCore::handle_pre_vote_req- *
 * uest. The same lease and last-log checks as a vote request, then        *
 * `req.vote >= local vote`; no state changes and no vote I/O, so the       *
 * response is sent at once (Respond with when: None). A Pre-Vote is never *
 * a leadership transfer.                                                   *
 * openraft/src/engine/engine_impl.rs:406-447                               *
 * openraft/src/core/raft_core.rs:1551-1562,1603-1607                       *
 *************************************************************************)
\* UPDATE-MAP
\* code: openraft/src/engine/engine_impl.rs:406-447 (handle_pre_vote_req)
\* update: Update!AffectedActions (DeliverPreVoteRequest), Update!PreVoteRequestIsPure
HandlePreVoteRequest(i, m, consume) ==
    /\ ~crashed[i]
    /\ m.kind = "PreVoteReq"
    /\ m.dest = i
    /\ ~votePersistPending[i]
    /\ ~replyPending[i]
    /\ LET grant == VoteGrantable(i, m.vote, m.lastLog, FALSE)
           resp == MessageR("PreVoteResp", i, m.source, vote[i], lastLog[i], grant, FALSE, m.vote)
       IN messages' = RemainingMessages(m, consume) \cup {resp}
    /\ UNCHANGED <<runtimeVars, voteVars, candidateVars, leaderVars, logVars,
                    configVars, preVars>>

DeliverPreVoteRequest(m) ==
    /\ m \in messages
    /\ HandlePreVoteRequest(m.dest, m, TRUE)

(***************************************************************************
 * Default RaftNetworkV2::pre_vote: a network that does not implement the   *
 * RPC synthesizes `VoteResponse::new(rpc.vote, None, true)` for the target *
 * without contacting it. Gated by PreVoteRpcDefaultGrant.                  *
 * openraft/src/network/v2/network.rs:141-161; network/vote_trait.rs:28-36  *
 *************************************************************************)
\* UPDATE-MAP
\* code: openraft/src/network/v2/network.rs:158-161
\* update: Update!AffectedActions (DefaultPreVoteRpcGrant)
DefaultPreVoteRpcGrant(m) ==
    /\ PreVoteRpcDefaultGrant
    /\ m \in messages
    /\ m.kind = "PreVoteReq"
    /\ messages' = (messages \ {m}) \cup
          {MessageR("PreVoteResp", m.dest, m.source, m.vote, NoLog(m.dest), TRUE, FALSE, m.vote)}
    /\ UNCHANGED <<runtimeVars, voteVars, candidateVars, leaderVars, logVars,
                    configVars, preVars>>

(***************************************************************************
 * Notification::PreVoteResponse -> Engine::handle_pre_vote_resp, split by  *
 * code path:                                                               *
 *   Ignored: no pre_candidate, or its leader id differs from the notified  *
 *            candidate_vote (raft_core.rs:1803-1820,2067-2090);            *
 *   Grant:   vote_granted, grant_by(target) without quorum;                *
 *   Elect:   vote_granted, grant_by(target) reaches the frozen quorum ->   *
 *            Engine::elect() (do_elect) with no further guard;             *
 *   Reject:  not granted; a greater responder log sets seen_greater_log.   *
 * grant_by() panics if target is not tracked by the frozen progress set   *
 * (proposer/candidate.rs:106-112).                                          *
 * openraft/src/engine/engine_impl.rs:512-554                               *
 *************************************************************************)
PreVoteRespMatches(i, m) ==
    /\ preCandidateActive[i]
    /\ SameLeaderId(m.reqVote, preCandidateVote[i])

PreVoteRespBase(i, m) ==
    /\ ~crashed[i]
    /\ m.kind = "PreVoteResp"
    /\ m.dest = i
    /\ ~votePersistPending[i]
    /\ ~replyPending[i]

HandlePreVoteResponseIgnored(i, m, consume) ==
    /\ PreVoteRespBase(i, m)
    /\ ~PreVoteRespMatches(i, m)
    /\ messages' = RemainingMessages(m, consume)
    /\ UNCHANGED <<runtimeVars, voteVars, candidateVars, leaderVars, logVars,
                    configVars, preVars>>

HandlePreVoteResponseGrant(i, m, consume) ==
    /\ PreVoteRespBase(i, m)
    /\ PreVoteRespMatches(i, m)
    /\ m.granted
    /\ ~IsQuorum(preCandidateConfig[i], preGrants[i] \cup {m.source})
    /\ preGrants' = [preGrants EXCEPT ![i] = @ \cup {m.source}]
    /\ messages' = RemainingMessages(m, consume)
    /\ UNCHANGED <<runtimeVars, voteVars, candidateVars, leaderVars, logVars,
                    configVars, preCandidateActive, preCandidateVote,
                    preCandidateConfig, preRoundFromLeader>>

\* UPDATE-MAP
\* code: openraft/src/engine/engine_impl.rs:534-540 (quorum -> self.elect())
\* update: Update!PreVoteRoundNotOutlivedByOwnLeadership, Update!PreVoteElectionByVoter,
\*         Update!PreVoteElectionAtProbedVote, Update!PreVoteElectionHasPreQuorum
HandlePreVoteResponseElect(i, m, consume) ==
    /\ PreVoteRespBase(i, m)
    /\ PreVoteRespMatches(i, m)
    /\ m.granted
    /\ IsQuorum(preCandidateConfig[i], preGrants[i] \cup {m.source})
    \* Finite-domain bound: the real election increments the term.
    /\ vote[i].term < MaxTerm
    /\ DoElect(i, seenGreaterLog[i])
    /\ messages' = RemainingMessages(m, consume)

HandlePreVoteResponseReject(i, m, consume) ==
    /\ PreVoteRespBase(i, m)
    /\ PreVoteRespMatches(i, m)
    /\ ~m.granted
    /\ seenGreaterLog' = [seenGreaterLog EXCEPT ![i] =
                             IF LogLT(lastLog[i], m.lastLog) THEN TRUE ELSE @]
    /\ messages' = RemainingMessages(m, consume)
    /\ UNCHANGED <<role, crashed, voteVars, candidateVars, leaderVars, logVars,
                    configVars, preVars>>

HandlePreVoteResponse(i, m, consume) ==
    \/ HandlePreVoteResponseIgnored(i, m, consume)
    \/ HandlePreVoteResponseGrant(i, m, consume)
    \/ HandlePreVoteResponseElect(i, m, consume)
    \/ HandlePreVoteResponseReject(i, m, consume)

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
 * openraft/src/engine/engine_impl.rs:644-672                               *
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
\* code: openraft/src/engine/engine_impl.rs:661-672 -> vote_handler/mod.rs:154-162,244
\* update: Update!AffectedActions (RefreshServerState)
RefreshServerState(i) ==
    /\ ~crashed[i]
    /\ committedConfigIndex[i] = effectiveConfigIndex[i]
    \* Repair (V0 defect): update_internal_server_state() does nothing for a
    \* leading-but-uncommitted node (vote names self), so the cached role is not
    \* recomputed in that case. vote_handler/mod.rs:154-162 (old 153-161)
    /\ role' = [role EXCEPT ![i] = IF RoleFrom(i, vote[i], effectiveConfig[i]) = "Candidate"
                                    THEN @ ELSE RoleFrom(i, vote[i], effectiveConfig[i])]
    /\ leaderActive' = [leaderActive EXCEPT ![i] = IF RoleFrom(i, vote[i], effectiveConfig[i]) = "Leader"
                                                    THEN @ ELSE FALSE]
    /\ candidateActive' = [candidateActive EXCEPT ![i] =
                              IF RoleFrom(i, vote[i], effectiveConfig[i]) = "Candidate" THEN @ ELSE FALSE]
    \* become_following() unless leading (Leader/Candidate)
    /\ PreCleared(i, RoleFrom(i, vote[i], effectiveConfig[i]) \notin {"Leader", "Candidate"})
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
                    effectiveConfigIndex, messages, preVars>>

(***************************************************************************
 * A leader may dispatch replication after the committed vote is durable.   *
 * Append return makes the log readable before its later flush callback.    *
 * openraft/src/core/raft_core.rs:2262-2272                                 *
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
\* code: openraft/src/engine/handler/vote_handler/mod.rs:148,154-162,244 (update_vote -> become_following)
\* update: Update!AffectedActions (DeliverAppendEntries)
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
       /\ PreCleared(i, m.vote.node /= i)
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
                    leaderVars, logVars, configVars, messages, preVars>>

DropMessage(m) ==
    /\ m \in messages
    /\ messages' = messages \ {m}
    /\ UNCHANGED <<runtimeVars, voteVars, candidateVars, leaderVars, logVars,
                    configVars, preVars>>

(***************************************************************************
 * Crash keeps durable variables. Restart reconstructs vote/log/config and  *
 * clears candidate, pre-candidate, command, lease, and greater-log state. *
 * openraft/src/storage/helper.rs:83-223,313-399                            *
 * openraft/src/engine/engine_impl.rs:104-120,167-211                       *
 *************************************************************************)
Crash(i) ==
    /\ ~crashed[i]
    /\ crashed' = [crashed EXCEPT ![i] = TRUE]
    /\ UNCHANGED <<role, seenGreaterLog, voteVars, candidateVars, leaderVars,
                    logVars, configVars, messages, preVars>>

\* UPDATE-MAP
\* code: openraft/src/engine/engine_impl.rs:117 (a reconstructed Engine has pre_candidate: None)
\* update: Update!AffectedActions (Restart)
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
    /\ PreCleared(i, TRUE)
    /\ UNCHANGED <<durableVote, durableLastLog, durableConfig, durableConfigIndex, messages>>

Next ==
    \/ \E i \in Server : TickElect(i) \/ ExternalElect(i) \/ StartTransferElection(i)
    \/ \E i \in Server : TickPreVote(i) \/ ExternalPreElect(i)
    \/ \E i \in Server : PersistVote(i) \/ FinishVoteBroadcast(i) \/ FlushLog(i)
    \/ \E i \in Server : ExpireLease(i) \/ Restart(i) \/ RefreshServerState(i)
    \/ \E i \in Server, j \in Server : SendVoteRequest(i, j) \/ SendAppendEntries(i, j)
    \/ \E m \in messages : DeliverVoteRequest(m) \/ DeliverVoteResponse(m)
                              \/ DeliverAppendEntries(m) \/ DropMessage(m)
                              \/ DeliverPreVoteRequest(m) \/ DeliverPreVoteResponse(m)
                              \/ DefaultPreVoteRpcGrant(m)
    \/ \E i \in Server, target \in SUBSET Server : AppendJointConfig(i, target)
    \/ \E i \in Server : AppendUniformConfig(i) \/ CommitMembership(i) \/ Crash(i)

Spec == Init /\ [][Next]_vars

\* REQ-EVIDENCE TypeOK
\* intent:   every model variable except replyMessage, and every field of every in-flight message (including the Pre-Vote kinds and the reqVote field), stays inside its declared domain.
\* status:   model-internal
\* watch:    none
\* verified: update
\* review:   ok
\* note:     representation change for the update: adds preCandidateActive/Vote/Config, preGrants, preRoundFromLeader, the PreVoteReq/PreVoteResp kinds, and the per-message reqVote field (spec/invariant-evidence.json E-TypeOK).
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
    /\ preGrants \in [Server -> SUBSET Server]
    /\ preRoundFromLeader \in [Server -> BOOLEAN]
    /\ \A m \in messages :
          /\ m.kind \in {"VoteReq", "VoteResp", "Append", "PreVoteReq", "PreVoteResp"}
          /\ m.reqVote.term \in 0..MaxTerm /\ m.reqVote.node \in Server
          /\ m.reqVote.committed \in BOOLEAN
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
\* verified: update
\* note:     update review: watch touched (Engine::do_elect clears pre_candidate; run_command SendVote now passes a VoteRequestKind). The property keeps quantifying only VoteReq: PreVoteReq carries a hypothetical vote that is never persisted by design (pre_vote.md:42-45; command.rs:138-142). Keep evidence E-VRAD (spec/invariant-evidence.json).
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
\* verified: update
\* note:     update review: watch symbols unchanged; new granted kind PreVoteResp is answered with Respond{when: None} (raft_core.rs:1551-1562) and grants nothing, and the default pre_vote RPC returns the probe itself (network/v2/network.rs:158-161). Kept for VoteResp only. Keep evidence E-GRAD.
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
\* verified: update
\* note:     update review: a new elect() caller (handle_pre_vote_resp) can run on a Leader; the post-state is role Candidate with an uncommitted self vote, which the property accepts. Keep evidence E-LRCSV.
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
\* verified: update
\* note:     update review: watch Engine::do_elect touched; the pre-vote elect path yields Candidate with (term+1, self, uncommitted). Keep evidence E-CRPSV.
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
\* verified: update
\* note:     update review: Candidate::grant_by is now also used by pre_candidate (candidate.rs: starting_time added; grant_by unchanged); the leader certificate is retained when a stale Pre-Vote round demotes the Leader (still a valid certificate). Keep evidence E-CLFQ; Pre-Vote quorums are covered by Update properties.
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
\* verified: update
\* note:     update review: quantifies over all messages including PreVoteReq/PreVoteResp; unchanged. Keep evidence E-NFME.
\* note:     searched the source for "byzantine", "forged", "authenticat" and found no stated assumption about message endpoints; core/raft_core.rs:1374 "target must be in membership" is about RPC targets being cluster members, not about the node universe, so it was not counted
\* review:   ok
NoForgedMessageEndpoints ==
    \A m \in messages : m.source \in Server /\ m.dest \in Server

=============================================================================
