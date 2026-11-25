------------------------------ MODULE base ------------------------------
(***************************************************************************
 * OpenRaft election reference model, updated for the Pre-Vote revision.   *
 *                                                                         *
 * Source boundary: /work/current/.specula-output/artifact (commit         *
 * 3ab6cdd "update"), especially engine/engine_impl.rs,                    *
 * engine/handler/vote_handler/mod.rs, core/raft_core.rs,                  *
 * raft_state/membership_state/mod.rs, and proposer/candidate.rs.          *
 *                                                                         *
 * Prior (V0, exact-old 1adc857 "baseline") semantics are preserved except *
 * where marked UPDATE-MAP (source delta) or REPAIR (model defect found    *
 * while analysing the update; see spec/changelog.md).                     *
 *************************************************************************)

EXTENDS Integers, Naturals, FiniteSets, Sequences, TLC

CONSTANTS Server, NodeOrder, MaxTerm, MaxLogIndex, InitialConfig,
          \* UPDATE-MAP
          \* code: openraft/src/config/runtime_config.rs:11,19 (enable_pre_vote AtomicBool,
          \*       toggled at runtime by raft/runtime_config_handle.rs:51-53)
          \* update: Update.tla section "Environment" (tick mode set)
          TickPreVoteModes

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
       /\ TickPreVoteModes \subseteq BOOLEAN
       /\ TickPreVoteModes /= {}

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

\* REPAIR R-5: Option<LogId>::None == None. NoLog(i) carries the owner id only
\* for field typing; two absent logs compare equal regardless of that id.
\* openraft/src/engine/engine_impl.rs:379 (`req.last_log_id.as_ref() >= self.state.last_log_id()`),
\* engine_impl.rs:434 (`req.last_log_id.as_ref() < self.state.last_log_id()`).
LogLE(a, b) == a = b \/ LogLT(a, b)  \* pre-R5 (V0) definition, control only

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

(***************************************************************************
 * RaftState::calc_server_state: leader, leading(candidate), voter, learner *
 * openraft/src/raft_state/mod.rs:416-467                                  *
 *************************************************************************)
RoleFrom(i, v, cfg) ==
    IF InConfig(i, cfg)
    THEN IF v.node = i
         THEN IF v.committed THEN "Leader" ELSE "Candidate"
         ELSE "Follower"
    ELSE "Learner"

\* UPDATE-MAP
\* code: openraft/src/core/notification.rs:34-44 (PreVoteResponse carries the
\*       pre-candidate vote it answers, used by raft_core.rs:1803-1820,2066-2090)
\* update: Update!HandlePreVoteResponseAffected
\* `round` is the request vote a response answers. Only PreVoteResp consumes
\* it; every other kind sets it to its own vote.
MessageR(kind, source, dest, v, lg, granted, transfer, round) ==
    [kind |-> kind,
     source |-> source,
     dest |-> dest,
     vote |-> v,
     lastLog |-> lg,
     granted |-> granted,
     transfer |-> transfer,
     round |-> round]

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
    \* REPAIR (log submission FIFO behind SaveVote; see changelog R-2)
    appendBehindVote,
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
    \*       engine_impl.rs:148-165 (new_pre_candidate)
    \* update: Update.tla "Update-visible state"
    preActive,
    preVote,
    preConfig,
    preGrants

voteVars == <<vote, durableVote, votePersistPending, replyPending, replyMessage,
              sendVotePending, leaseValid>>
candidateVars == <<candidateActive, candidateVote, candidateConfig, grants, sentVoteReq>>
leaderVars == <<leaderActive, leaderVote, leaderCertified, leaderConfig, leaderGrants>>
logVars == <<lastLog, durableLastLog, logFlushPending, appendBehindVote>>
configVars == <<committedConfig, committedConfigIndex, effectiveConfig,
                effectiveConfigIndex, durableConfig, durableConfigIndex>>
runtimeVars == <<role, crashed, seenGreaterLog>>
preVars == <<preActive, preVote, preConfig, preGrants>>
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
    /\ appendBehindVote = [i \in Server |-> FALSE]
    /\ committedConfig = [i \in Server |-> <<InitialConfig>>]
    /\ committedConfigIndex = [i \in Server |-> 0]
    /\ effectiveConfig = committedConfig
    /\ effectiveConfigIndex = committedConfigIndex
    /\ durableConfig = committedConfig
    /\ durableConfigIndex = committedConfigIndex
    /\ messages = {}
    /\ crashed = [i \in Server |-> FALSE]
    /\ seenGreaterLog = [i \in Server |-> FALSE]
    \* UPDATE-MAP code: engine_impl.rs:117 (pre_candidate: None) update: Update!PreVars
    /\ preActive = [i \in Server |-> FALSE]
    /\ preVote = vote
    /\ preConfig = [i \in Server |-> <<InitialConfig>>]
    /\ preGrants = [i \in Server |-> {}]

(***************************************************************************
 * Engine::do_elect. A real election supersedes any in-flight Pre-Vote     *
 * round. Candidate membership and last log are snapshotted before the      *
 * pending self vote is installed. SaveVote is queued before SendVote.      *
 * openraft/src/engine/engine_impl.rs:262-289                              *
 * openraft/src/engine/engine_impl.rs:124-139 (new_candidate)              *
 * openraft/src/engine/handler/vote_handler/mod.rs:105-149                 *
 * `msgs` is the caller's message-set successor (the pre-vote response      *
 * handler consumes its message in the same atomic engine step).           *
 *************************************************************************)
\* UPDATE-MAP
\* code: openraft/src/engine/engine_impl.rs:262-264 (self.pre_candidate = None)
\* update: Update!AffectedActions (DoElect is reached from StartElection,
\*         PreElect's single-voter branch, and HandlePreVoteResponse)
DoElect(i, msgs) ==
    /\ vote[i].term < MaxTerm
    /\ LET nv == Vote(vote[i].term + 1, i, FALSE) IN
       /\ vote' = [vote EXCEPT ![i] = nv]
       /\ candidateActive' = [candidateActive EXCEPT ![i] = TRUE]
       /\ candidateVote' = [candidateVote EXCEPT ![i] = nv]
       \* server_state_handler().update_server_state_if_changed()
       \* engine_impl.rs:288, raft_state/mod.rs:416-440
       /\ role' = [role EXCEPT ![i] = RoleFrom(i, nv, effectiveConfig[i])]
    /\ candidateConfig' = [candidateConfig EXCEPT ![i] = effectiveConfig[i]]
    /\ grants' = [grants EXCEPT ![i] = {}]
    /\ sentVoteReq' = [sentVoteReq EXCEPT ![i] = {}]
    /\ votePersistPending' = [votePersistPending EXCEPT ![i] = TRUE]
    /\ sendVotePending' = [sendVotePending EXCEPT ![i] = TRUE]
    /\ leaseValid' = [leaseValid EXCEPT ![i] = FALSE]
    /\ preActive' = [preActive EXCEPT ![i] = FALSE]
    /\ preGrants' = [preGrants EXCEPT ![i] = {}]
    /\ messages' = msgs
    /\ UNCHANGED <<durableVote, replyPending, replyMessage, leaderVars,
                    logVars, configVars, crashed, preVote, preConfig>>

(***************************************************************************
 * External / transfer election entry (V0 StartElection): runtime checks   *
 * that this node is a voter, then calls Engine::elect or                  *
 * elect_by_leadership_transfer.                                           *
 * openraft/src/core/raft_core.rs:1683-1696                                *
 * openraft/src/engine/engine_impl.rs:239-260                              *
 *************************************************************************)
StartElection(i, transfer) ==
    /\ ~crashed[i]
    /\ InConfig(i, effectiveConfig[i])
    /\ ~votePersistPending[i]
    /\ ~replyPending[i]
    /\ DoElect(i, messages)
    /\ UNCHANGED seenGreaterLog

(***************************************************************************
 * Engine::pre_elect. Probe a quorum at term + 1 without touching vote,     *
 * role, or persistence. A self-grant that is already a quorum proceeds    *
 * straight to Engine::elect. Otherwise SendPreVote is dispatched; the     *
 * runtime spawns one RPC per other effective voter in the same command    *
 * drain (no SaveVote precedes it).                                        *
 * openraft/src/engine/engine_impl.rs:297-322                              *
 * openraft/src/engine/engine_impl.rs:148-165 (frozen effective config)    *
 * openraft/src/core/raft_core.rs:1385-1478,2342-2344                      *
 *************************************************************************)
\* UPDATE-MAP
\* code: openraft/src/engine/engine_impl.rs:291-322 (pre_elect)
\* update: Update!AffectedActions (PreElectAffected)
PreElectEffect(i) ==
    /\ vote[i].term < MaxTerm
    /\ LET pv == Vote(vote[i].term + 1, i, FALSE)
           cfg == effectiveConfig[i]
       IN
       \* engine_impl.rs:309-315 grant_by(self); quorum -> elect()
       IF IsQuorum(cfg, {i})
       THEN DoElect(i, messages)
       ELSE
          /\ preActive' = [preActive EXCEPT ![i] = TRUE]
          /\ preVote' = [preVote EXCEPT ![i] = pv]
          /\ preConfig' = [preConfig EXCEPT ![i] = cfg]
          /\ preGrants' = [preGrants EXCEPT ![i] = {i}]
          \* engine_impl.rs:319-321 SendPreVote; raft_core.rs:1386-1393 targets
          \* are effective voters other than self.
          /\ messages' = messages \cup
                {MessageR("PreVoteReq", i, j, pv, lastLog[i], FALSE, FALSE, pv) :
                    j \in ConfigVoters(cfg) \ {i}}
          /\ UNCHANGED <<role, voteVars, candidateVars, leaderVars, logVars,
                          configVars, crashed>>

PreElect(i) ==
    /\ ~crashed[i]
    /\ ~votePersistPending[i]
    /\ ~replyPending[i]
    /\ PreElectEffect(i)
    /\ UNCHANGED seenGreaterLog

(***************************************************************************
 * RaftCore::handle_tick_election. Leaders and non-voters skip. With Pre-   *
 * Vote enabled and more than one voter, tick runs pre_elect; otherwise it *
 * runs elect. The in-flight-round rate limit and timeout arithmetic are    *
 * time abstractions: a later tick may restart a round. reset_greater_log  *
 * precedes either call.                                                   *
 * openraft/src/core/raft_core.rs:1958-2036                                *
 *************************************************************************)
\* UPDATE-MAP
\* code: openraft/src/core/raft_core.rs:2010-2035
\* update: Update!AffectedActions (TickElectAffected)
TickElect(i, pv) ==
    /\ ~crashed[i]
    /\ role[i] /= "Leader"
    /\ InConfig(i, effectiveConfig[i])
    \* REPAIR R-3: vote.is_expired(now, election_timeout) cannot hold while the
    \* committed vote's leader lease is still valid (raft_core.rs:2001-2008,
    \* openraft/src/utime.rs:148-152 is_expired = now > last_update + lease + timeout).
    /\ ~leaseValid[i]
    /\ ~votePersistPending[i]
    /\ ~replyPending[i]
    /\ pv \in TickPreVoteModes
    /\ seenGreaterLog' = [seenGreaterLog EXCEPT ![i] = FALSE]
    /\ IF pv /\ Cardinality(ConfigVoters(effectiveConfig[i])) > 1
       THEN PreElectEffect(i)
       ELSE DoElect(i, messages)

\* ExternalCommand::Elect { pre_vote } raft_core.rs:1683-1696: voter check only.
ExternalElect(i) == StartElection(i, FALSE)
ExternalPreElect(i) ==
    /\ InConfig(i, effectiveConfig[i])
    /\ PreElect(i)
StartTransferElection(i) == StartElection(i, TRUE)

(***************************************************************************
 * save_vote() is awaited. A pending election gets a local granted response;
 * a vote-request reply held on IOFlushed becomes visible here. Commands    *
 * queued behind SaveVote (a log append) are submitted afterwards.          *
 * openraft/src/core/raft_core.rs:2274-2305                                 *
 *************************************************************************)
PersistVote(i) ==
    /\ ~crashed[i]
    /\ votePersistPending[i]
    /\ VoteLT(durableVote[i], vote[i])
    /\ durableVote' = [durableVote EXCEPT ![i] = vote[i]]
    /\ votePersistPending' = [votePersistPending EXCEPT ![i] = FALSE]
    /\ appendBehindVote' = [appendBehindVote EXCEPT ![i] = FALSE]
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
                    leaderVars, lastLog, durableLastLog, logFlushPending,
                    configVars, crashed, seenGreaterLog, preVars>>

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
 * the lease and can reply immediately. A successful update_vote calls      *
 * update_internal_server_state: become_following clears leader, candidate,*
 * and (new) pre_candidate.                                                 *
 * openraft/src/engine/engine_impl.rs:350-404                               *
 * openraft/src/engine/handler/vote_handler/mod.rs:105-160,234-249          *
 * openraft/src/core/raft_core.rs:1531-1549                                 *
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
       \* UPDATE-MAP
       \* code: openraft/src/engine/handler/vote_handler/mod.rs:242-244
       \* update: Update!InteractionActions (HandleVoteRequest clears a pre-candidate)
       /\ preActive' = [preActive EXCEPT ![i] = IF follows THEN FALSE ELSE @]
    /\ UNCHANGED <<durableVote, sendVotePending, candidateVote, candidateConfig,
                    grants, sentVoteReq, leaderCertified, leaderConfig,
                    leaderGrants, logVars, configVars, crashed, seenGreaterLog,
                    preVote, preConfig, preGrants>>

DeliverVoteRequest(m) ==
    /\ m \in messages
    /\ HandleVoteRequest(m.dest, m, TRUE)

(***************************************************************************
 * Exact granted vote equality advances the frozen quorum. Establishment    *
 * commits the vote in projected state and projects the leader blank log;   *
 * committed vote persistence remains pending and the blank append is       *
 * queued behind SaveVote. establish_leader -> update_vote(committed) ->    *
 * become_leader does NOT clear pre_candidate. A rejected higher vote is    *
 * adopted stripped of its committed bit; become_following clears          *
 * pre_candidate.                                                          *
 * openraft/src/engine/engine_impl.rs:449-509,855-881                       *
 * openraft/src/engine/handler/vote_handler/mod.rs:154-160,168-230          *
 * openraft/src/proposer/candidate.rs:97-133                                *
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
       \* REPAIR R-4: update_vote(committed) installs the leader lease; a strictly
       \* greater uncommitted vote installs a zero lease.
       \* openraft/src/engine/handler/vote_handler/mod.rs:121-135
       /\ leaseValid' = [leaseValid EXCEPT ![i] = IF wins THEN TRUE ELSE IF adopt THEN FALSE ELSE @]
       /\ lastLog' = [lastLog EXCEPT ![i] = IF wins /\ newIndex <= MaxLogIndex
                                              THEN Log(cv.term, cv.node, newIndex) ELSE @]
       /\ logFlushPending' = [logFlushPending EXCEPT ![i] = IF wins /\ newIndex <= MaxLogIndex
                                                                THEN TRUE ELSE @]
       \* REPAIR R-2: the blank append is submitted after SaveVote(committed).
       /\ appendBehindVote' = [appendBehindVote EXCEPT ![i] = IF wins /\ newIndex <= MaxLogIndex
                                                                  THEN TRUE ELSE @]
       /\ seenGreaterLog' = [seenGreaterLog EXCEPT ![i] =
                                IF candidateActive[i] /\ ~exact /\ LogLT(lastLog[i], m.lastLog)
                                THEN TRUE ELSE @]
       \* UPDATE-MAP
       \* code: vote_handler/mod.rs:242-244 (become_following) vs 168-230 (become_leader keeps it)
       \* update: Update!InteractionActions (HandleVoteResponse)
       /\ preActive' = [preActive EXCEPT ![i] = IF adopt /\ stripped.node /= i THEN FALSE ELSE @]
    /\ UNCHANGED <<durableVote, replyPending, replyMessage,
                    candidateVote, candidateConfig, sentVoteReq, durableLastLog,
                    configVars, crashed, preVote, preConfig, preGrants>>

DeliverVoteResponse(m) ==
    /\ m \in messages
    /\ HandleVoteResponse(m.dest, m, TRUE)

(***************************************************************************
 * Engine::handle_pre_vote_req. Lease (never a transfer), then last-log,   *
 * then vote order; the local state is left untouched and the runtime      *
 * responds at once (no IOFlushed condition).                              *
 * openraft/src/engine/engine_impl.rs:406-447                               *
 * openraft/src/core/raft_core.rs:1551-1562,1603-1607                       *
 *************************************************************************)
\* UPDATE-MAP
\* code: openraft/src/engine/engine_impl.rs:414-447
\* update: Update!AffectedActions (HandlePreVoteRequestAffected)
HandlePreVoteRequest(i, m, consume) ==
    /\ ~crashed[i]
    /\ m.kind = "PreVoteReq"
    /\ m.dest = i
    /\ ~votePersistPending[i]
    /\ ~replyPending[i]
    /\ LET leaseBlocked == vote[i].committed /\ leaseValid[i]
           logOK == LogLE(lastLog[i], m.lastLog)
           orderOK == VoteLE(vote[i], m.vote)
           grant == ~leaseBlocked /\ logOK /\ orderOK
           resp == MessageR("PreVoteResp", i, m.source, vote[i], lastLog[i], grant, FALSE, m.vote)
       IN messages' = RemainingMessages(m, consume) \cup {resp}
    /\ UNCHANGED <<runtimeVars, voteVars, candidateVars, leaderVars, logVars,
                    configVars, preVars>>

DeliverPreVoteRequest(m) ==
    /\ m \in messages
    /\ HandlePreVoteRequest(m.dest, m, TRUE)

(***************************************************************************
 * RaftCore Notification::PreVoteResponse + Engine::handle_pre_vote_resp.  *
 * The runtime forwards a response only while a pre-candidate exists and   *
 * its leader id equals the answered request vote. A grant is tallied      *
 * against the frozen pre-vote config; a quorum runs Engine::elect at the  *
 * CURRENT vote term + 1 and clears the pre-candidate. A rejection records *
 * a greater log only; the responder's vote is never adopted.              *
 * openraft/src/core/raft_core.rs:1803-1820,2066-2090                       *
 * openraft/src/engine/engine_impl.rs:511-554                               *
 *************************************************************************)
\* UPDATE-MAP
\* code: openraft/src/engine/engine_impl.rs:516-554; raft_core.rs:1803-1820
\* update: Update!AffectedActions (HandlePreVoteResponseAffected)
HandlePreVoteResponse(i, m, consume) ==
    /\ ~crashed[i]
    /\ m.kind = "PreVoteResp"
    /\ m.dest = i
    /\ ~votePersistPending[i]
    /\ ~replyPending[i]
    /\ LET match == /\ preActive[i]
                    /\ m.round.term = preVote[i].term
                    /\ m.round.node = preVote[i].node
           ng == preGrants[i] \cup {m.source}
           wins == match /\ m.granted /\ IsQuorum(preConfig[i], ng)
       IN
       IF wins
       THEN /\ DoElect(i, RemainingMessages(m, consume))
            /\ UNCHANGED seenGreaterLog
       ELSE
          /\ messages' = RemainingMessages(m, consume)
          /\ preGrants' = [preGrants EXCEPT ![i] = IF match /\ m.granted THEN ng ELSE @]
          /\ seenGreaterLog' = [seenGreaterLog EXCEPT ![i] =
                                   IF match /\ ~m.granted /\ LogLT(lastLog[i], m.lastLog)
                                   THEN TRUE ELSE @]
          /\ UNCHANGED <<role, crashed, voteVars, candidateVars, leaderVars,
                          logVars, configVars, preActive, preVote, preConfig>>

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
                    durableLastLog, appendBehindVote, durableConfig,
                    durableConfigIndex, messages, preVars>>

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
                    durableLastLog, appendBehindVote, durableConfig,
                    durableConfigIndex, messages, preVars>>

(***************************************************************************
 * Commit copies effective to committed. Cached role refresh is separate:   *
 * refresh_server_state -> update_internal_server_state; a non-leading      *
 * node goes through become_following, which clears pre_candidate.          *
 * openraft/src/raft_state/membership_state/mod.rs:121-147                  *
 * openraft/src/engine/engine_impl.rs:643-673                               *
 *************************************************************************)
CommitMembership(i) ==
    /\ ~crashed[i]
    /\ committedConfigIndex[i] < effectiveConfigIndex[i]
    /\ committedConfig' = [committedConfig EXCEPT ![i] = effectiveConfig[i]]
    /\ committedConfigIndex' = [committedConfigIndex EXCEPT ![i] = effectiveConfigIndex[i]]
    /\ UNCHANGED <<runtimeVars, voteVars, candidateVars, leaderVars, logVars,
                    effectiveConfig, effectiveConfigIndex, durableConfig,
                    durableConfigIndex, messages, preVars>>

RefreshServerState(i) ==
    /\ ~crashed[i]
    /\ committedConfigIndex[i] = effectiveConfigIndex[i]
    /\ LET r == RoleFrom(i, vote[i], effectiveConfig[i]) IN
       /\ role' = [role EXCEPT ![i] = r]
       /\ leaderActive' = [leaderActive EXCEPT ![i] = IF r = "Leader" THEN @ ELSE FALSE]
       /\ candidateActive' = [candidateActive EXCEPT ![i] = IF r = "Candidate" THEN @ ELSE FALSE]
       \* UPDATE-MAP code: vote_handler/mod.rs:154-160,242-244 update: Update!InteractionActions
       /\ preActive' = [preActive EXCEPT ![i] = IF r \in {"Leader", "Candidate"} THEN @ ELSE FALSE]
    /\ UNCHANGED <<crashed, seenGreaterLog, voteVars, candidateVote,
                    candidateConfig, grants, sentVoteReq, leaderVote,
                    leaderCertified, leaderConfig, leaderGrants, logVars,
                    configVars, messages, preVote, preConfig, preGrants>>

(***************************************************************************
 * Log flush callback. REPAIR R-2: an append queued behind a pending        *
 * SaveVote is not yet submitted (commands drain FIFO and save_vote is     *
 * awaited inline), so it cannot become durable first.                    *
 * openraft/src/core/raft_core.rs:2265-2305                                 *
 *************************************************************************)
FlushLog(i) ==
    /\ ~crashed[i]
    /\ logFlushPending[i]
    /\ ~appendBehindVote[i]
    /\ durableLastLog' = [durableLastLog EXCEPT ![i] = lastLog[i]]
    /\ logFlushPending' = [logFlushPending EXCEPT ![i] = FALSE]
    /\ durableConfig' = [durableConfig EXCEPT ![i] = effectiveConfig[i]]
    /\ durableConfigIndex' = [durableConfigIndex EXCEPT ![i] = effectiveConfigIndex[i]]
    /\ UNCHANGED <<runtimeVars, voteVars, candidateVars, leaderVars, lastLog,
                    appendBehindVote, committedConfig, committedConfigIndex,
                    effectiveConfig, effectiveConfigIndex, messages, preVars>>

(***************************************************************************
 * A leader may dispatch replication after the committed vote is durable.   *
 * Append return makes the log readable before its later flush callback.    *
 * openraft/src/core/raft_core.rs:2265-2273,2361-2364                       *
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

(***************************************************************************
 * Engine::append_entries: update_vote first (become_following clears the  *
 * leader, candidate and pre-candidate), then follower log work.           *
 * REPAIR R-1: the accepted leader log becomes the follower's last log      *
 * when it is greater (conflicting suffixes are truncated; a matching       *
 * shorter segment changes nothing). Payload contents, prev-log            *
 * backtracking and membership payload propagation remain abstracted.      *
 * openraft/src/engine/engine_impl.rs:559-602                               *
 * openraft/src/engine/handler/following_handler/mod.rs:64-125              *
 *************************************************************************)
HandleAppendEntries(i, m, consume) ==
    /\ ~crashed[i]
    /\ m.kind = "Append"
    /\ m.dest = i
    /\ VoteLE(vote[i], m.vote)
    /\ ~votePersistPending[i]
    /\ LET strict == VoteLT(vote[i], m.vote)
           adoptLog == LogLT(lastLog[i], m.lastLog)
       IN
       /\ vote' = [vote EXCEPT ![i] = m.vote]
       /\ votePersistPending' = [votePersistPending EXCEPT ![i] = strict]
       /\ leaseValid' = [leaseValid EXCEPT ![i] = m.vote.committed]
       /\ role' = [role EXCEPT ![i] = RoleFrom(i, m.vote, effectiveConfig[i])]
       /\ candidateActive' = [candidateActive EXCEPT ![i] = IF m.vote.node = i THEN @ ELSE FALSE]
       /\ leaderActive' = [leaderActive EXCEPT ![i] = IF m.vote.node = i /\ m.vote.committed
                                                      THEN TRUE ELSE FALSE]
       /\ leaderVote' = [leaderVote EXCEPT ![i] = IF m.vote.node = i /\ m.vote.committed
                                                  THEN m.vote ELSE @]
       /\ lastLog' = [lastLog EXCEPT ![i] = IF adoptLog THEN m.lastLog ELSE @]
       /\ logFlushPending' = [logFlushPending EXCEPT ![i] = IF adoptLog THEN TRUE ELSE @]
       /\ appendBehindVote' = [appendBehindVote EXCEPT ![i] = IF adoptLog /\ strict THEN TRUE ELSE @]
       \* UPDATE-MAP
       \* code: vote_handler/mod.rs:242-244 via engine_impl.rs:591
       \* update: Update!InteractionActions (HandleAppendEntries clears a pre-candidate)
       /\ preActive' = [preActive EXCEPT ![i] = IF m.vote.node = i THEN @ ELSE FALSE]
    /\ messages' = RemainingMessages(m, consume)
    /\ UNCHANGED <<crashed, seenGreaterLog, durableVote, replyPending,
                    replyMessage, sendVotePending, candidateVote,
                    candidateConfig, grants, sentVoteReq, leaderCertified,
                    leaderConfig, leaderGrants, durableLastLog, configVars,
                    preVote, preConfig, preGrants>>

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
 * openraft/src/engine/engine_impl.rs:105-120,167-210                       *
 *************************************************************************)
Crash(i) ==
    /\ ~crashed[i]
    /\ crashed' = [crashed EXCEPT ![i] = TRUE]
    /\ UNCHANGED <<role, seenGreaterLog, voteVars, candidateVars, leaderVars,
                    logVars, configVars, messages, preVars>>

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
    /\ appendBehindVote' = [appendBehindVote EXCEPT ![i] = FALSE]
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
    \* UPDATE-MAP code: engine_impl.rs:117 (fresh Engine has no pre_candidate)
    \* update: Update!InteractionActions (Restart)
    /\ preActive' = [preActive EXCEPT ![i] = FALSE]
    /\ preVote' = [preVote EXCEPT ![i] = durableVote[i]]
    /\ preConfig' = [preConfig EXCEPT ![i] = durableConfig[i]]
    /\ preGrants' = [preGrants EXCEPT ![i] = {}]
    /\ UNCHANGED <<durableVote, durableLastLog, durableConfig, durableConfigIndex, messages>>

Next ==
    \/ \E i \in Server, pv \in BOOLEAN : TickElect(i, pv)
    \/ \E i \in Server : ExternalElect(i) \/ ExternalPreElect(i) \/ StartTransferElection(i)
    \/ \E i \in Server : PersistVote(i) \/ FinishVoteBroadcast(i) \/ FlushLog(i)
    \/ \E i \in Server : ExpireLease(i) \/ Restart(i) \/ RefreshServerState(i)
    \/ \E i \in Server, j \in Server : SendVoteRequest(i, j) \/ SendAppendEntries(i, j)
    \/ \E m \in messages : DeliverVoteRequest(m) \/ DeliverVoteResponse(m)
                              \/ DeliverPreVoteRequest(m) \/ DeliverPreVoteResponse(m)
                              \/ DeliverAppendEntries(m) \/ DropMessage(m)
    \/ \E i \in Server, target \in SUBSET Server : AppendJointConfig(i, target)
    \/ \E i \in Server : AppendUniformConfig(i) \/ CommitMembership(i) \/ Crash(i)

Spec == Init /\ [][Next]_vars

VoteType == [term : 0..MaxTerm, node : Server, committed : BOOLEAN]

TypeOK ==
    /\ role \in [Server -> {"Learner", "Follower", "Candidate", "Leader"}]
    /\ vote \in [Server -> VoteType]
    /\ durableVote \in [Server -> VoteType]
    /\ votePersistPending \in [Server -> BOOLEAN]
    /\ replyPending \in [Server -> BOOLEAN]
    /\ sendVotePending \in [Server -> BOOLEAN]
    /\ leaseValid \in [Server -> BOOLEAN]
    /\ candidateActive \in [Server -> BOOLEAN]
    /\ candidateVote \in [Server -> VoteType]
    /\ \A i \in Server : IsConfig(candidateConfig[i])
    /\ grants \in [Server -> SUBSET Server]
    /\ sentVoteReq \in [Server -> SUBSET Server]
    /\ leaderActive \in [Server -> BOOLEAN]
    /\ leaderVote \in [Server -> VoteType]
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
    /\ appendBehindVote \in [Server -> BOOLEAN]
    /\ \A i \in Server : IsConfig(committedConfig[i]) /\ IsConfig(effectiveConfig[i])
                           /\ IsConfig(durableConfig[i])
    /\ committedConfigIndex \in [Server -> 0..MaxLogIndex]
    /\ effectiveConfigIndex \in [Server -> 0..MaxLogIndex]
    /\ durableConfigIndex \in [Server -> 0..MaxLogIndex]
    /\ crashed \in [Server -> BOOLEAN]
    /\ seenGreaterLog \in [Server -> BOOLEAN]
    /\ preActive \in [Server -> BOOLEAN]
    /\ preVote \in [Server -> VoteType]
    /\ \A i \in Server : IsConfig(preConfig[i])
    /\ preGrants \in [Server -> SUBSET Server]
    /\ \A m \in messages :
          /\ m.kind \in {"VoteReq", "VoteResp", "Append", "PreVoteReq", "PreVoteResp"}
          /\ m.source \in Server /\ m.dest \in Server
          /\ m.vote \in VoteType
          /\ m.round \in VoteType
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
