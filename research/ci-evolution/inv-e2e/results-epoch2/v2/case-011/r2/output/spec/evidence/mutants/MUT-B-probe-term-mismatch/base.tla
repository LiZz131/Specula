------------------------------ MODULE base ------------------------------
(***************************************************************************
 * OpenRaft election reference model -- updated revision (pre-vote).       *
 *                                                                         *
 * Source boundary: artifact HEAD (synthetic commit `update`), especially  *
 * engine/engine_impl.rs, engine/handler/vote_handler/mod.rs,              *
 * core/raft_core.rs, raft_state/membership_state/mod.rs, and              *
 * proposer/candidate.rs.  Line numbers refer to the UPDATED source unless *
 * marked "old".                                                           *
 *                                                                         *
 * The update adds an optional Pre-Vote round (Engine::pre_elect,          *
 * handle_pre_vote_req, handle_pre_vote_resp, Command::SendPreVote,        *
 * Notification::PreVoteResponse, Config::enable_pre_vote,                 *
 * ExternalCommand::Elect{pre_vote}).  Every new behaviour is owned here;  *
 * spec/Update.tla is only a checking lens.                                *
 *************************************************************************)

EXTENDS Integers, Naturals, FiniteSets, Sequences, TLC

CONSTANTS Server, NodeOrder, MaxTerm, MaxLogIndex, InitialConfig,
          EnablePreVote,        \* RuntimeConfig::enable_pre_vote (config.rs get_enable_pre_vote)
          PreVoteDefaultGrant   \* a peer network lacking pre_vote() synthesizes a grant

ReferenceServer == {"1", "2", "3"}
ReferenceNodeOrder == <<"1", "2", "3">>
ReferenceInitialConfig == {"1", "2", "3"}
PairServer == {"1", "2"}
PairNodeOrder == <<"1", "2">>

ASSUME /\ Server /= {}
       /\ Len(NodeOrder) = Cardinality(Server)
       /\ {NodeOrder[k] : k \in 1..Len(NodeOrder)} = Server
       /\ InitialConfig \subseteq Server
       /\ InitialConfig /= {}
       /\ MaxTerm \in Nat \ {0}
       /\ MaxLogIndex \in Nat \ {0}
       /\ EnablePreVote \in BOOLEAN
       /\ PreVoteDefaultGrant \in BOOLEAN

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

\* REPAIR (prior-model defect): NoLog(i) carries a node id only as a
\* placeholder; Option<LogId>::None == None regardless of that field
\* (openraft/src/log_id/mod.rs:18-61).  The prior `a = b` made two empty logs
\* incomparable, so no multi-node election from empty logs could succeed.
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

\* voter_ids().count() == 1 in handle_tick_election (core/raft_core.rs:1985-1987)
SingleVoter(c) == Cardinality(ConfigVoters(c)) = 1

RoleFrom(i, v, cfg) ==
    IF InConfig(i, cfg)
    THEN IF v.node = i
         THEN IF v.committed THEN "Leader" ELSE "Candidate"
         ELSE "Follower"
    ELSE "Learner"

(***************************************************************************
 * Messages.  `reqVote` is the vote carried by the originating request.    *
 * For Pre-Vote responses it is the runtime `candidate_vote` correlation    *
 * key (core/raft_core.rs:1443-1457, Notification::PreVoteResponse); for    *
 * the prior message kinds it equals `vote` and is not consulted.           *
 *************************************************************************)
Message(kind, source, dest, v, lg, granted, transfer) ==
    [kind |-> kind,
     source |-> source,
     dest |-> dest,
     vote |-> v,
     lastLog |-> lg,
     granted |-> granted,
     transfer |-> transfer,
     reqVote |-> v]

PreVoteMessage(kind, source, dest, v, lg, granted, rv) ==
    [kind |-> kind,
     source |-> source,
     dest |-> dest,
     vote |-> v,
     lastLog |-> lg,
     granted |-> granted,
     transfer |-> FALSE,
     reqVote |-> rv]

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
    \* code: openraft/src/engine/engine_impl.rs:95-101 (Engine.pre_candidate), :149-165 (new_pre_candidate)
    \* update: Update!AffectedActions, Update!TickPreVoteRoundNotHeldByLeader
    preCandidateActive,   \* Engine.pre_candidate.is_some()
    preCandidateVote,     \* pre_candidate.vote: hypothetical (term+1, self, uncommitted)
    preCandidateConfig,   \* frozen effective membership captured by new_pre_candidate
    preGrants             \* pre_candidate.progress granters

voteVars == <<vote, durableVote, votePersistPending, replyPending, replyMessage,
              sendVotePending, leaseValid>>
candidateVars == <<candidateActive, candidateVote, candidateConfig, grants, sentVoteReq>>
leaderVars == <<leaderActive, leaderVote, leaderCertified, leaderConfig, leaderGrants>>
logVars == <<lastLog, durableLastLog, logFlushPending>>
configVars == <<committedConfig, committedConfigIndex, effectiveConfig,
                effectiveConfigIndex, durableConfig, durableConfigIndex>>
runtimeVars == <<role, crashed, seenGreaterLog>>
preCandidateVars == <<preCandidateActive, preCandidateVote, preCandidateConfig, preGrants>>
vars == <<runtimeVars, voteVars, candidateVars, leaderVars, logVars, configVars,
          messages, preCandidateVars>>

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
    \* Engine::new: pre_candidate: None (engine/engine_impl.rs:117)
    /\ preCandidateActive = [i \in Server |-> FALSE]
    /\ preCandidateVote = [i \in Server |-> DefaultVote(i)]
    /\ preCandidateConfig = [i \in Server |-> <<InitialConfig>>]
    /\ preGrants = [i \in Server |-> {}]

(***************************************************************************
 * Pre-candidate helpers.  `*self.pre_candidate = None` is executed by      *
 * do_elect (engine_impl.rs:263-264) and VoteHandler::become_following      *
 * (vote_handler/mod.rs:242-244).  Inactive pre-candidate fields are reset  *
 * to canonical values; they are never read while inactive.                 *
 *************************************************************************)
\* UPDATE-MAP
\* code: openraft/src/engine/engine_impl.rs:263-264; openraft/src/engine/handler/vote_handler/mod.rs:242-244
\* update: Update!AffectedActions (all callers of KeepOrClearPre)
KeepOrClearPre(i, clear) ==
    /\ preCandidateActive' = [preCandidateActive EXCEPT ![i] = IF clear THEN FALSE ELSE @]
    /\ preCandidateVote' = [preCandidateVote EXCEPT ![i] = IF clear THEN DefaultVote(i) ELSE @]
    /\ preCandidateConfig' = [preCandidateConfig EXCEPT ![i] = IF clear THEN <<InitialConfig>> ELSE @]
    /\ preGrants' = [preGrants EXCEPT ![i] = IF clear THEN {} ELSE @]

ClearPreCandidate(i) == KeepOrClearPre(i, TRUE)

(***************************************************************************
 * Election engine transition Engine::do_elect (engine_impl.rs:262-289).    *
 * Candidate membership and last log are snapshotted before the pending     *
 * self vote is installed; SaveVote is queued before SendVote.              *
 *                                                                           *
 * UPDATED: do_elect now clears any in-flight Pre-Vote round                 *
 * (engine_impl.rs:263-264).                                                 *
 *                                                                           *
 * The callers that existed in the old revision (tick, external Elect,       *
 * leadership transfer) only call it for a voter.  The NEW caller            *
 * handle_pre_vote_resp -> elect() (engine_impl.rs:535-539) has no voter     *
 * guard, so do_elect is modelled for a non-voter too.  Then is_leading      *
 * (raft_state/mod.rs:453-455) depends on whether the node is still a        *
 * membership member (retained learner) -- a hidden discriminator for this    *
 * voter-set model -- so both outcomes are kept as a nondeterministic union: *
 *   learner member : update_internal_server_state does nothing; Candidate.  *
 *   non-member     : become_following clears leader/candidate/pre_candidate *
 *                    (vote_handler/mod.rs:154-162,234-249); Learner.        *
 * Fields `messages` and `seenGreaterLog` are left to the callers.           *
 *************************************************************************)
\* UPDATE-MAP
\* code: openraft/src/engine/engine_impl.rs:262-289 (do_elect), :535-539 (pre-vote caller)
\* update: Update!AffectedActions, Update!VoteResponseFromFrozenVoter
ElectEffects(i) ==
    /\ vote[i].term < MaxTerm
    /\ ~votePersistPending[i]
    /\ ~replyPending[i]
    /\ LET nv == Vote(vote[i].term + 1, i, FALSE)
           voter == InConfig(i, effectiveConfig[i])
       IN
       \E learnerMember \in (IF voter THEN {TRUE} ELSE BOOLEAN) :
          LET leading == voter \/ learnerMember IN
          /\ vote' = [vote EXCEPT ![i] = nv]
          /\ candidateActive' = [candidateActive EXCEPT ![i] = leading]
          /\ candidateVote' = [candidateVote EXCEPT ![i] = nv]
          /\ candidateConfig' = [candidateConfig EXCEPT ![i] = effectiveConfig[i]]
          /\ grants' = [grants EXCEPT ![i] = {}]
          /\ sentVoteReq' = [sentVoteReq EXCEPT ![i] = {}]
          /\ role' = [role EXCEPT ![i] = IF leading THEN "Candidate" ELSE "Learner"]
          /\ votePersistPending' = [votePersistPending EXCEPT ![i] = TRUE]
          \* A non-member's SendVote targets are not modelled (see analysis-report).
          /\ sendVotePending' = [sendVotePending EXCEPT ![i] = leading]
          /\ leaseValid' = [leaseValid EXCEPT ![i] = FALSE]
          \* The existing Leader object is kept by do_elect (old behaviour);
          \* become_following drops it for a non-member.
          /\ leaderActive' = [leaderActive EXCEPT ![i] = IF leading THEN @ ELSE FALSE]
          /\ ClearPreCandidate(i)
          /\ UNCHANGED <<durableVote, replyPending, replyMessage, leaderVote,
                          leaderCertified, leaderConfig, leaderGrants, logVars,
                          configVars, crashed>>

\* Callers that existed in the old revision check is_voter first:
\* tick (core/raft_core.rs:1971-1974), external Elect (core/raft_core.rs:1683-1684).
StartElection(i, transfer) ==
    /\ ~crashed[i]
    /\ InConfig(i, effectiveConfig[i])
    /\ ElectEffects(i)
    /\ UNCHANGED messages

(***************************************************************************
 * RaftCore::handle_tick_election (core/raft_core.rs:1959-2036).            *
 * Leaders skip (1966-1969); non-voters skip (1971-1974).  The tick resets  *
 * seen_greater_log before electing (2027).  UPDATED: with enable_pre_vote  *
 * and more than one voter, the tick runs pre_elect() instead of elect()    *
 * (2012, 2029-2035).  Timer/lease expiry and the "fresh round in flight"   *
 * rate limit (2014-2022) are time abstractions: modelled as enablement     *
 * nondeterminism.                                                          *
 *************************************************************************)
\* UPDATE-MAP
\* code: openraft/src/core/raft_core.rs:1959-2036
\* update: Update!AffectedActions (MCTickElect, MCTickPreElect)
TickElect(i) ==
    /\ role[i] /= "Leader"
    /\ (~EnablePreVote \/ SingleVoter(effectiveConfig[i]))
    /\ StartElection(i, FALSE)
    /\ seenGreaterLog' = [seenGreaterLog EXCEPT ![i] = FALSE]

\* ExternalCommand::Elect { pre_vote: false } (core/raft_core.rs:1683-1691):
\* is_voter guard only; seen_greater_log is not reset on this path.
ExternalElect(i) ==
    /\ StartElection(i, FALSE)
    /\ UNCHANGED seenGreaterLog

StartTransferElection(i) ==
    /\ StartElection(i, TRUE)
    /\ UNCHANGED seenGreaterLog

(***************************************************************************
 * NEW: Engine::pre_elect (engine_impl.rs:297-322).  Builds a pre-candidate *
 * at the hypothetical vote (term+1, self, uncommitted) over a frozen copy  *
 * of the effective membership (new_pre_candidate, 149-165), self-grants,   *
 * and either elects at once when that alone is a quorum (single voter,     *
 * 309-314) or emits SendPreVote without touching vote, server state, or    *
 * persistence (316-321).  The runtime executes SendPreVote immediately     *
 * after the event and spawns one RPC per other effective voter             *
 * (core/raft_core.rs:1385-1394, 2342-2344); spawned RPC latency is network *
 * delay, so the requests enter `messages` atomically here.                 *
 *************************************************************************)
\* UPDATE-MAP
\* code: openraft/src/engine/engine_impl.rs:297-322; openraft/src/core/raft_core.rs:1385-1480,2342-2344
\* update: Update!AffectedActions (MCTickPreElect, MCExternalPreElect)
PreElectCore(i) ==
    /\ ~crashed[i]
    /\ vote[i].term < MaxTerm
    /\ ~votePersistPending[i]
    /\ ~replyPending[i]
    /\ vote[i].term + 2 <= MaxTerm
    /\ LET pv == Vote(vote[i].term + 2, i, FALSE)
           cfg == effectiveConfig[i]
       IN
       IF IsQuorum(cfg, {i})
       THEN /\ ElectEffects(i)
            /\ UNCHANGED messages
       ELSE /\ preCandidateActive' = [preCandidateActive EXCEPT ![i] = TRUE]
            /\ preCandidateVote' = [preCandidateVote EXCEPT ![i] = pv]
            /\ preCandidateConfig' = [preCandidateConfig EXCEPT ![i] = cfg]
            /\ preGrants' = [preGrants EXCEPT ![i] = {i}]
            /\ messages' = messages \cup
                  {PreVoteMessage("PreVoteReq", i, j, pv, lastLog[i], FALSE, pv) :
                      j \in ConfigVoters(cfg) \ {i}}
            /\ UNCHANGED <<role, voteVars, candidateVars, leaderVars, logVars,
                            configVars, crashed>>

\* Tick path with enable_pre_vote and >1 voter (core/raft_core.rs:2012-2031).
TickPreElect(i) ==
    /\ role[i] /= "Leader"
    /\ InConfig(i, effectiveConfig[i])
    /\ EnablePreVote
    /\ ~SingleVoter(effectiveConfig[i])
    /\ PreElectCore(i)
    /\ seenGreaterLog' = [seenGreaterLog EXCEPT ![i] = FALSE]

\* ExternalCommand::Elect { pre_vote: true } (core/raft_core.rs:1683-1689):
\* per-call opt-in, independent of Config::enable_pre_vote (raft/trigger.rs:47-62).
ExternalPreElect(i) ==
    /\ InConfig(i, effectiveConfig[i])
    /\ PreElectCore(i)
    /\ UNCHANGED seenGreaterLog

(***************************************************************************
 * save_vote() is awaited.  A pending election gets a local granted response;
 * a vote-request reply held on IOFlushed becomes visible here.              *
 * openraft/src/core/raft_core.rs:2274-2303                                  *
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
                    preCandidateVars>>

(***************************************************************************
 * Remote requests start only after the candidate vote is durable. Runtime  *
 * enumerates the current effective voters; the candidate validates against *
 * its frozen copy. Those are equal at election start.                       *
 * openraft/src/core/raft_core.rs:1385-1480,2339-2341                        *
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
                    preCandidateVars>>

FinishVoteBroadcast(i) ==
    /\ sendVotePending[i]
    /\ ConfigVoters(candidateConfig[i]) \ {i} \subseteq sentVoteReq[i]
    /\ sendVotePending' = [sendVotePending EXCEPT ![i] = FALSE]
    /\ UNCHANGED <<runtimeVars, vote, durableVote, votePersistPending,
                    replyPending, replyMessage, leaseValid, candidateVars,
                    leaderVars, logVars, configVars, messages, preCandidateVars>>

RemainingMessages(m, consume) == IF consume THEN messages \ {m} ELSE messages

(***************************************************************************
 * Guard order is lease, then last-log, then vote comparison. Strict vote   *
 * changes defer the response until persistence; equal votes merely touch   *
 * the lease and can reply immediately.                                     *
 * openraft/src/engine/engine_impl.rs:349-404                               *
 * openraft/src/engine/handler/vote_handler/mod.rs:106-170                  *
 * openraft/src/core/raft_core.rs:1532-1549                                 *
 * UPDATED: a granted vote that is not this node's own leads to             *
 * become_following, which now also drops the pre-candidate                 *
 * (vote_handler/mod.rs:242-244).                                           *
 *************************************************************************)
\* UPDATE-MAP
\* code: openraft/src/engine/handler/vote_handler/mod.rs:154-162,234-249
\* update: Update!AffectedActions (MCDeliverVoteRequest)
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
       /\ KeepOrClearPre(i, follows)
    /\ UNCHANGED <<durableVote, sendVotePending, candidateVote, candidateConfig,
                    grants, sentVoteReq, leaderCertified, leaderConfig,
                    leaderGrants, logVars, configVars, crashed, seenGreaterLog>>

DeliverVoteRequest(m) ==
    /\ m \in messages
    /\ HandleVoteRequest(m.dest, m, TRUE)

(***************************************************************************
 * NEW: Engine::handle_pre_vote_req (engine_impl.rs:413-447) and            *
 * RaftCore::handle_pre_vote_request (core/raft_core.rs:1551-1562).         *
 * Same lease -> last-log -> vote-order judgement as a vote request, but    *
 * the lease is always honoured (no transfer bypass, 433-437), nothing is   *
 * persisted or updated, and the reply is sent at once (`when: None`).      *
 * Every rejection returns the same (vote, last_log_id, false) triple, so   *
 * the rejection order is not observable.                                   *
 *************************************************************************)
\* UPDATE-MAP
\* code: openraft/src/engine/engine_impl.rs:413-447; openraft/src/core/raft_core.rs:1551-1562,1603-1607
\* update: Update!AffectedActions (MCDeliverPreVoteRequest)
HandlePreVoteRequest(i, m, consume) ==
    /\ ~crashed[i]
    /\ m.kind = "PreVoteReq"
    /\ m.dest = i
    /\ ~votePersistPending[i]
    /\ ~replyPending[i]
    /\ LET leaseBlocked == vote[i].committed /\ leaseValid[i]
           logOK == LogLE(lastLog[i], m.lastLog)
           grant == ~leaseBlocked /\ logOK /\ VoteLE(vote[i], m.vote)
           resp == PreVoteMessage("PreVoteResp", i, m.source, vote[i], lastLog[i], grant, m.vote)
       IN messages' = RemainingMessages(m, consume) \cup {resp}
    /\ UNCHANGED <<runtimeVars, voteVars, candidateVars, leaderVars, logVars,
                    configVars, preCandidateVars>>

DeliverPreVoteRequest(m) ==
    /\ m \in messages
    /\ HandlePreVoteRequest(m.dest, m, TRUE)

(***************************************************************************
 * NEW environment option: RaftNetworkV2::pre_vote default implementation   *
 * (network/v2/network.rs:141-161, network/vote_trait.rs:28-36) returns     *
 * Ok(VoteResponse::new(rpc.vote, None, true)) on the SENDER side without   *
 * contacting the target.  Enabled only by PreVoteDefaultGrant.             *
 *************************************************************************)
NetworkDefaultPreVote(m) ==
    /\ PreVoteDefaultGrant
    /\ m \in messages
    /\ m.kind = "PreVoteReq"
    /\ ~crashed[m.source]
    /\ messages' = (messages \ {m}) \cup
          {PreVoteMessage("PreVoteResp", m.dest, m.source, m.vote, NoLog(m.dest), TRUE, m.vote)}
    /\ UNCHANGED <<runtimeVars, voteVars, candidateVars, leaderVars, logVars,
                    configVars, preCandidateVars>>

(***************************************************************************
 * Exact granted vote equality advances the frozen quorum. Establishment    *
 * commits the vote in projected state and projects the leader blank log;   *
 * committed vote persistence remains pending.                              *
 * openraft/src/engine/engine_impl.rs:449-509,855-881                       *
 * openraft/src/proposer/candidate.rs:105-133                               *
 * Interaction with the update: establish_leader takes `candidate` only;    *
 * its update_vote(committed self vote) reaches become_leader, which does   *
 * NOT touch `pre_candidate` (vote_handler/mod.rs:154-162,172-231).  An      *
 * adopted foreign vote reaches become_following, which clears it.          *
 *************************************************************************)
\* UPDATE-MAP
\* code: openraft/src/engine/engine_impl.rs:855-881 (unchanged); vote_handler/mod.rs:242-244 (changed)
\* update: Update!InteractionActions (MCDeliverVoteResponse), Update!TickPreVoteRoundNotHeldByLeader
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
       /\ lastLog' = [lastLog EXCEPT ![i] = IF wins /\ newIndex <= MaxLogIndex
                                              THEN Log(cv.term, cv.node, newIndex) ELSE @]
       /\ logFlushPending' = [logFlushPending EXCEPT ![i] = IF wins /\ newIndex <= MaxLogIndex
                                                                THEN TRUE ELSE @]
       /\ seenGreaterLog' = [seenGreaterLog EXCEPT ![i] =
                                IF candidateActive[i] /\ ~exact /\ LogLT(lastLog[i], m.lastLog)
                                THEN TRUE ELSE @]
       \* REPAIR (prior-model defect, trace stale_pre_vote_after_leader e4):
       \* establish_leader's update_vote(committed) installs the leader lease
       \* (vote_handler/mod.rs:123-135: leader_lease for a committed vote); an
       \* adopted uncommitted vote gets a zero lease.
       /\ leaseValid' = [leaseValid EXCEPT ![i] = IF wins THEN TRUE
                                                  ELSE IF adopt THEN FALSE ELSE @]
       /\ KeepOrClearPre(i, adopt /\ ~(stripped.node = i /\ InConfig(i, effectiveConfig[i])))
    /\ UNCHANGED <<durableVote, replyPending, replyMessage,
                    candidateVote, candidateConfig, sentVoteReq, durableLastLog,
                    configVars, crashed>>

DeliverVoteResponse(m) ==
    /\ m \in messages
    /\ HandleVoteResponse(m.dest, m, TRUE)

(***************************************************************************
 * NEW: Notification::PreVoteResponse (core/raft_core.rs:1803-1820) and     *
 * Engine::handle_pre_vote_resp (engine_impl.rs:515-554).                   *
 *  - runtime gate: pre_candidate.is_some() and its vote's leader_id equals *
 *    the notification's candidate_vote (does_pre_candidate_vote_match,     *
 *    raft_core.rs:2067-2090); otherwise the response is dropped.           *
 *  - granted: grant_by(target) on the frozen pre-candidate quorum; on a    *
 *    quorum, self.elect() (535-539) -- no voter/role re-check.             *
 *  - rejected: a greater responder log sets seen_greater_log (543-551).    *
 *  The local vote is never adopted from a pre-vote response (553).         *
 *************************************************************************)
\* UPDATE-MAP
\* code: openraft/src/engine/engine_impl.rs:515-554; openraft/src/core/raft_core.rs:1803-1820,2067-2090
\* update: Update!AffectedActions (MCDeliverPreVoteResponse), Update!LeaderNotPreemptedByTimerPreVote
HandlePreVoteResponse(i, m, consume) ==
    /\ ~crashed[i]
    /\ m.kind = "PreVoteResp"
    /\ m.dest = i
    /\ ~votePersistPending[i]
    /\ ~replyPending[i]
    /\ LET matched == preCandidateActive[i] /\ m.reqVote = preCandidateVote[i]
           ng == preGrants[i] \cup {m.source}
           wins == matched /\ m.granted /\ IsQuorum(preCandidateConfig[i], ng)
       IN
       IF wins
       THEN /\ ElectEffects(i)
            /\ messages' = RemainingMessages(m, consume)
            /\ UNCHANGED seenGreaterLog
       ELSE /\ messages' = RemainingMessages(m, consume)
            /\ preGrants' = [preGrants EXCEPT ![i] = IF matched /\ m.granted THEN ng ELSE @]
            /\ seenGreaterLog' = [seenGreaterLog EXCEPT ![i] =
                                     IF matched /\ ~m.granted /\ LogLT(lastLog[i], m.lastLog)
                                     THEN TRUE ELSE @]
            /\ UNCHANGED <<role, voteVars, candidateVars, leaderVars, logVars,
                            configVars, crashed, preCandidateActive,
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
                    preCandidateVars>>

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
                    preCandidateVars>>

(***************************************************************************
 * Commit copies effective to committed. Cached role refresh is separate.   *
 * openraft/src/raft_state/membership_state/mod.rs:121-147                  *
 * openraft/src/engine/engine_impl.rs:660-673                               *
 *************************************************************************)
CommitMembership(i) ==
    /\ ~crashed[i]
    /\ committedConfigIndex[i] < effectiveConfigIndex[i]
    /\ committedConfig' = [committedConfig EXCEPT ![i] = effectiveConfig[i]]
    /\ committedConfigIndex' = [committedConfigIndex EXCEPT ![i] = effectiveConfigIndex[i]]
    /\ UNCHANGED <<runtimeVars, voteVars, candidateVars, leaderVars, logVars,
                    effectiveConfig, effectiveConfigIndex, durableConfig,
                    durableConfigIndex, messages, preCandidateVars>>

\* refresh_server_state -> update_internal_server_state (engine_impl.rs:660-673,
\* vote_handler/mod.rs:154-162): become_following (and, UPDATED, dropping the
\* pre-candidate) happens only when the node is neither leader nor leading.
RefreshServerState(i) ==
    /\ ~crashed[i]
    /\ committedConfigIndex[i] = effectiveConfigIndex[i]
    /\ LET r == RoleFrom(i, vote[i], effectiveConfig[i]) IN
       /\ role' = [role EXCEPT ![i] = r]
       /\ leaderActive' = [leaderActive EXCEPT ![i] = IF r = "Leader" THEN @ ELSE FALSE]
       /\ candidateActive' = [candidateActive EXCEPT ![i] = IF r = "Candidate" THEN @ ELSE FALSE]
       /\ KeepOrClearPre(i, r \in {"Follower", "Learner"})
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
                    effectiveConfigIndex, messages, preCandidateVars>>

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
                    configVars, preCandidateVars>>

\* handle_append_entries (engine_impl.rs:560-604) updates the vote first; the
\* resulting update_internal_server_state drops the pre-candidate unless the
\* vote is this node's own (UPDATED become_following, vote_handler/mod.rs:242-244).
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
       /\ KeepOrClearPre(i, ~(m.vote.node = i /\ InConfig(i, effectiveConfig[i])))
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
                    leaderVars, logVars, configVars, messages, preCandidateVars>>

DropMessage(m) ==
    /\ m \in messages
    /\ messages' = messages \ {m}
    /\ UNCHANGED <<runtimeVars, voteVars, candidateVars, leaderVars, logVars,
                    configVars, preCandidateVars>>

(***************************************************************************
 * Crash keeps durable variables. Restart reconstructs vote/log/config and  *
 * clears candidate, pre-candidate (Engine::new, engine_impl.rs:117),       *
 * command, lease, and greater-log transient state.                         *
 * openraft/src/storage/helper.rs:83-223,313-399                            *
 * openraft/src/engine/engine_impl.rs:107-120,167-215                       *
 *************************************************************************)
Crash(i) ==
    /\ ~crashed[i]
    /\ crashed' = [crashed EXCEPT ![i] = TRUE]
    /\ UNCHANGED <<role, seenGreaterLog, voteVars, candidateVars, leaderVars,
                    logVars, configVars, messages, preCandidateVars>>

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
    /\ ClearPreCandidate(i)
    /\ UNCHANGED <<durableVote, durableLastLog, durableConfig, durableConfigIndex, messages>>

Next ==
    \/ \E i \in Server : TickElect(i) \/ ExternalElect(i) \/ StartTransferElection(i)
    \/ \E i \in Server : TickPreElect(i) \/ ExternalPreElect(i)
    \/ \E i \in Server : PersistVote(i) \/ FinishVoteBroadcast(i) \/ FlushLog(i)
    \/ \E i \in Server : ExpireLease(i) \/ Restart(i) \/ RefreshServerState(i)
    \/ \E i \in Server, j \in Server : SendVoteRequest(i, j) \/ SendAppendEntries(i, j)
    \/ \E m \in messages : DeliverVoteRequest(m) \/ DeliverVoteResponse(m)
                              \/ DeliverAppendEntries(m) \/ DropMessage(m)
                              \/ DeliverPreVoteRequest(m) \/ DeliverPreVoteResponse(m)
                              \/ NetworkDefaultPreVote(m)
    \/ \E i \in Server, target \in SUBSET Server : AppendJointConfig(i, target)
    \/ \E i \in Server : AppendUniformConfig(i) \/ CommitMembership(i) \/ Crash(i)

Spec == Init /\ [][Next]_vars

VoteDomain == [term : 0..MaxTerm, node : Server, committed : BOOLEAN]

\* REQ-EVIDENCE TypeOK
\* intent:   every model variable except replyMessage, and every field of every in-flight message, stays inside its declared domain.
\* status:   model-internal
\* watch:    none
\* verified: update
\* review:   extended for the pre-candidate variables, the PreVoteReq/PreVoteResp message kinds and the reqVote correlation field introduced by the update.
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
    /\ preCandidateVote \in [Server -> VoteDomain]
    /\ \A i \in Server : IsConfig(preCandidateConfig[i])
    /\ preGrants \in [Server -> SUBSET Server]
    /\ \A m \in messages :
          /\ m.kind \in {"VoteReq", "VoteResp", "Append", "PreVoteReq", "PreVoteResp"}
          /\ m.source \in Server /\ m.dest \in Server
          /\ m.vote \in VoteDomain
          /\ m.reqVote \in VoteDomain
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
\* evidence: impl source/openraft/src/core/raft_core.rs:2281 "self.log_store.save_vote(&vote).await.sto_write_vote()?;"
\* evidence: impl source/openraft/src/storage/helper.rs:89 "let vote = log_reader.read_vote().await.sto_read_vote()?;"
\* watch:    source/openraft/src/raft_state/io_state/io_progress.rs:IOProgress::validate; source/openraft/src/engine/handler/vote_handler/mod.rs:VoteHandler::update_vote; source/openraft/src/core/raft_core.rs:RaftCore::run_command (Command::SaveVote); source/openraft/src/engine/engine_impl.rs:Engine::startup; source/openraft/src/storage/helper.rs:StorageHelper::get_initial_state; source/openraft/src/config/config.rs:Config::enable_leader_restore
\* verified: update
\* note:     unaffected by the update: no watched symbol changed (config.rs gained an unrelated enable_pre_vote field; update_vote/startup/SaveVote are textually unchanged); pre-vote paths persist nothing. Prior note retained: engine_impl.rs startup demotes the in-memory vote below the stored committed vote when leader restore is disabled.
\* review:   ok
DurableVoteNotAhead == \A i \in Server : VoteLE(durableVote[i], vote[i])
\* REQ-EVIDENCE DurableLogNotAhead
\* intent:   on every node, the last log id persisted on disk is never ahead of the node's last log id (`last_log`, the accepted pointer).
\* status:   requirement
\* evidence: doc source/openraft/src/docs/data/log_pointers.md:27 "`flushed` ≤ `submitted` ≤ `accepted`;" -> the last persisted log id never exceeds the accepted one
\* evidence: doc source/openraft/src/docs/data/log_pointers.md:24 "`accepted` is also known as `last_log` in Openraft codebase." -> the accepted pointer is the node's last log id
\* evidence: doc source/openraft/src/docs/data/log_pointers.md:19 "the last log entry that is persisted on disk, inclusive." -> the flushed pointer is the last log entry persisted on disk
\* evidence: contract source/openraft/src/storage/v2/raft_log_storage.rs:101 "When the `callback` is called, the entries must be persisted on disk." -> a flush report means the entries are on disk
\* watch:    source/openraft/src/raft_state/io_state/io_progress.rs:IOProgress::validate; source/openraft/src/core/raft_core.rs:RaftCore::run_command (Command::AppendEntries); source/openraft/src/engine/handler/following_handler/mod.rs:FollowingHandler::truncate_logs; source/openraft/src/storage/v2/raft_log_storage.rs:RaftLogStorage::append; source/openraft/src/storage/helper.rs:StorageHelper::get_initial_state
\* verified: update
\* note:     unaffected by the update (no watched symbol changed; pre-vote appends nothing).
\* review:   ok
DurableLogNotAhead == \A i \in Server : LogLE(durableLastLog[i], lastLog[i])

\* REQ-EVIDENCE VoteRequestAfterDurable
\* intent:   a node sends vote requests only for a vote that is already persisted in its own storage.
\* status:   impl-abstraction
\* evidence: test source/openraft/src/engine/tests/elect_test.rs:58 test_elect_single_node "Command::SaveVote { vote: Vote::new(1, 1) }," -> the save of the new vote is queued ahead of SendVote (queue order only)
\* evidence: test source/openraft/src/engine/tests/pre_elect_test.rs:92 test_pre_elect_single_node_starts_real_election "vec![Command::SaveVote { vote: Vote::new(1, 1) }, Command::SendVote {" -> the pre-vote shortcut keeps SaveVote ahead of SendVote (queue order only)
\* evidence: contract source/openraft/src/storage/v2/raft_log_storage.rs:62 "The vote must be persisted on disk before returning." -> a completed save_vote means the vote is durable
\* evidence: impl source/openraft/src/core/raft_core.rs:2281 "self.log_store.save_vote(&vote).await.sto_write_vote()?;"
\* evidence: impl source/openraft/src/core/raft_core.rs:2340 "self.spawn_parallel_vote_requests(&vote_req, VoteRequestKind::Vote).await;"
\* watch:    source/openraft/src/core/raft_core.rs:RaftCore::run_engine_commands; source/openraft/src/core/raft_core.rs:RaftCore::run_command (Command::SaveVote, Command::SendVote); source/openraft/src/engine/engine_impl.rs:Engine::do_elect; source/openraft/src/engine/command.rs:Command::condition; source/openraft/src/engine/engine_output.rs:EngineOutput::postpone_command
\* verified: update
\* note:     affected (watch touched: do_elect gained `pre_candidate = None`; the SendVote arm gained a VoteRequestKind argument and a sibling SendPreVote arm was added). Kept: PreVoteReq messages are intentionally outside the quantifier because pre-vote persists nothing (docs/protocol/pre_vote.md:42-45); see spec/invariant-evidence.json.
\* review:   ok
VoteRequestAfterDurable ==
    \A m \in messages : m.kind = "VoteReq" => VoteLE(m.vote, durableVote[m.source])

\* REQ-EVIDENCE GrantedResponseAfterDurable
\* intent:   a granted vote response leaves a node only after the vote it grants is persisted on that node.
\* status:   requirement
\* evidence: test source/openraft/src/engine/tests/elect_test.rs:38 test_elect_single_node "single node: still need to wait for Vote to persist" -> the candidate's own grant is not counted before persistence
\* evidence: contract source/openraft/src/storage/v2/raft_log_storage.rs:62 "The vote must be persisted on disk before returning." -> a vote whose save has returned is durable
\* evidence: doc source/openraft/src/docs/protocol/pre_vote.md:42 "The crucial difference from a real vote: handling a Pre-Vote request **persists" -> pre-vote responses grant nothing durable and are intentionally outside this property
\* evidence: impl source/openraft/src/core/raft_core.rs:1542 "let condition = Some(Condition::IOFlushed {"
\* evidence: impl source/openraft/src/core/raft_core.rs:1559 "when: None,"
\* watch:    source/openraft/src/core/raft_core.rs:RaftCore::handle_vote_request; source/openraft/src/core/raft_core.rs:RaftCore::run_command (Command::SaveVote); source/openraft/src/core/raft_core.rs:RaftCore::send_satisfied_responds; source/openraft/src/engine/command.rs:Condition::is_met; source/openraft/src/engine/engine_output.rs:EngineOutput::postpone_command
\* verified: update
\* note:     affected because the update adds a new response kind (PreVoteResp, replied with `when: None`). Kept: a pre-vote grant is a query result, not a vote grant, so the durability requirement does not extend to it. Prior history evidence (ee460f37, 88754e09, 36d2c115 commit messages) is not re-checkable in this blind run and is retained only by reference to the prior suite.
\* review:   ok
GrantedResponseAfterDurable ==
    \A m \in messages : m.kind = "VoteResp" /\ m.granted => VoteLE(m.vote, durableVote[m.source])

\* REQ-EVIDENCE LeaderRoleHasCommittedSelfVote
\* intent:   a node in the Leader role holds a committed vote that names itself.
\* status:   requirement
\* evidence: doc source/openraft/src/docs/data/vote.md:61 "is a leader if it is **present** in config, either a voter or non-voter." -> leader only with its own committed vote (row at vote.md:60)
\* evidence: comment source/openraft/src/raft_state/mod.rs:459 "Leadership is granted by a quorum and the vote is committed." -> a leader's vote is committed
\* evidence: test source/openraft/src/engine/tests/handle_vote_resp_test.rs:194 test_handle_vote_resp_equal_vote "assert_eq!(Vote::new_committed(2, 1), *eng.state.vote_ref(),);" -> on becoming Leader the vote is its own committed vote
\* watch:    source/openraft/src/raft_state/mod.rs:RaftState::calc_server_state; source/openraft/src/raft_state/mod.rs:RaftState::is_leader; source/openraft/src/engine/handler/server_state_handler/mod.rs:ServerStateHandler::update_server_state_if_changed; source/openraft/src/engine/engine_impl.rs:Engine::startup; source/openraft/src/engine/handler/vote_handler/mod.rs:VoteHandler::update_internal_server_state
\* verified: update
\* note:     not touched by the diff, but a new election path (pre-vote quorum -> elect) can now start from Leader role; kept and re-evidenced on that path (spec/invariant-evidence.json).
\* review:   ok
LeaderRoleHasCommittedSelfVote ==
    \A i \in Server : role[i] = "Leader" => vote[i].committed /\ vote[i].node = i

\* REQ-EVIDENCE CandidateRoleHasPendingSelfVote
\* intent:   a node in the Candidate role holds a not-yet-committed vote that names itself.
\* status:   requirement
\* evidence: doc source/openraft/src/docs/data/vote.md:65 "is a candidate if it is **present** in config, either a voter or non-voter." -> candidate only with its own uncommitted vote (row at vote.md:64)
\* evidence: test source/openraft/src/engine/tests/elect_test.rs:53 test_elect_single_node "assert_eq!(ServerState::Candidate, eng.state.server_state);" -> after elect() the Candidate holds its own uncommitted vote
\* evidence: test source/openraft/src/engine/tests/handle_pre_vote_resp_test.rs:61 test_handle_pre_vote_resp_quorum_starts_real_election "assert_eq!(ServerState::Candidate, eng.state.server_state);" -> a pre-vote quorum produces a Candidate with vote (1,1) uncommitted (lines 55-59)
\* watch:    source/openraft/src/raft_state/mod.rs:RaftState::calc_server_state; source/openraft/src/raft_state/mod.rs:RaftState::is_leading; source/openraft/src/engine/handler/server_state_handler/mod.rs:ServerStateHandler::update_server_state_if_changed; source/openraft/src/engine/engine_impl.rs:Engine::do_elect; source/openraft/src/engine/engine_impl.rs:Engine::startup
\* verified: update
\* note:     affected (watch touched: Engine::do_elect; new caller handle_pre_vote_resp). Kept with a trace-backed keep state.
\* review:   ok
CandidateRoleHasPendingSelfVote ==
    \A i \in Server : role[i] = "Candidate" => ~vote[i].committed /\ vote[i].node = i

\* REQ-EVIDENCE CertifiedLeaderHasFrozenQuorum
\* intent:   a node that became leader by winning its own election had its vote granted by a quorum (a majority of every constituent config) of the membership captured when that election started.
\* status:   mixed
\* evidence: comment source/openraft/src/proposer/candidate.rs:121 "Mark the vote as committed, i.e., being granted and saved by a quorum." -> an elected leader's vote was granted by a quorum
\* evidence: doc source/raft-essentials.md:106 "requires separate majorities from both the old and new configurations" -> election quorum is a majority in each config of a joint config
\* evidence: contract source/openraft/src/quorum/quorum_set_impl.rs:31 "a node set is a quorum iff it is a majority in every config." -> joint quorum means a majority in every constituent config
\* watch:    source/openraft/src/proposer/candidate.rs:Candidate::grant_by; source/openraft/src/engine/engine_impl.rs:Engine::new_candidate; source/openraft/src/engine/engine_impl.rs:Engine::handle_vote_resp; source/openraft/src/engine/engine_impl.rs:Engine::establish_leader; source/openraft/src/quorum/quorum_set_impl.rs:QuorumSet for Vec<BTreeSet<NID>>; source/openraft/src/membership/membership_impl_quorum_set.rs:QuorumSet for Membership
\* verified: update
\* clause quorum-granted: requirement — unchanged by the update
\* clause frozen-config: impl-abstraction — unchanged by the update
\* note:     unaffected: watched symbols unchanged (candidate.rs only gained starting_time()); pre-vote quorums do not certify leaders.
\* review:   ok
CertifiedLeaderHasFrozenQuorum ==
    \A i \in Server : leaderCertified[i] => IsQuorum(leaderConfig[i], leaderGrants[i])

\* REQ-EVIDENCE MembershipAtMostOneOutstanding
\* intent:   on every node the committed membership config is never newer than the effective one, and at most one config beyond the committed one is outstanding.
\* status:   requirement
\* evidence: comment source/openraft/src/raft_state/membership_state/mod.rs:37 "(2) there is at most one outstanding, uncommitted membership log." -> at most one uncommitted config
\* evidence: comment source/openraft/src/raft_state/membership_state/mod.rs:199 "Openraft allows at most only one non-committed membership config." -> at most one uncommitted config
\* watch:    source/openraft/src/raft_state/membership_state/mod.rs:MembershipState::append; source/openraft/src/raft_state/membership_state/mod.rs:MembershipState::commit; source/openraft/src/raft_state/membership_state/mod.rs:MembershipState::truncate
\* verified: update
\* note:     unaffected by the update.
\* review:   ok
MembershipAtMostOneOutstanding ==
    \A i \in Server :
        /\ committedConfigIndex[i] <= effectiveConfigIndex[i]
        /\ effectiveConfigIndex[i] <= committedConfigIndex[i] + 1

\* REQ-EVIDENCE NoForgedMessageEndpoints
\* intent:   every in-flight message is sent from and addressed to a node of the modelled server set.
\* status:   model-internal
\* watch:    none
\* verified: update
\* note:     quantifies over all message kinds, including the new PreVoteReq/PreVoteResp kinds.
\* review:   ok
NoForgedMessageEndpoints ==
    \A m \in messages : m.source \in Server /\ m.dest \in Server

\* REQ-EVIDENCE PreCandidateWellFormed
\* intent:   an active pre-vote round carries an uncommitted self-named hypothetical vote and has counted its own grant.
\* status:   model-internal
\* evidence: test source/openraft/src/engine/tests/pre_elect_test.rs:54 test_pre_elect_multi_node_no_mutation "assert_eq!(Vote::new(1, 1), *eng.pre_candidate_ref().unwrap().vote_ref());" -> the pre-candidate vote is the next-term uncommitted self vote
\* evidence: test source/openraft/src/engine/tests/pre_elect_test.rs:55 test_pre_elect_multi_node_no_mutation "assert_eq!(" -> with granters {1} (lines 56-57)
\* watch:    source/openraft/src/engine/engine_impl.rs:Engine::pre_elect; source/openraft/src/engine/engine_impl.rs:Engine::new_pre_candidate
\* verified: update
\* review:   new structural property for the update.
PreCandidateWellFormed ==
    \A i \in Server :
        preCandidateActive[i] =>
            /\ preCandidateVote[i].node = i
            /\ ~preCandidateVote[i].committed
            /\ i \in preGrants[i]

=============================================================================
