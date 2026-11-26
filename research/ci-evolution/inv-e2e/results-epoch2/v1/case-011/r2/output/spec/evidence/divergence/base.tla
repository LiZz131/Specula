------------------------------ MODULE base ------------------------------
(***************************************************************************
 * OpenRaft election reference, updated for the Pre-Vote revision.        *
 *                                                                         *
 * Source boundary: the `update` commit of the artifact tree, especially   *
 * engine/engine_impl.rs, engine/handler/vote_handler/mod.rs,              *
 * core/raft_core.rs, raft_state/membership_state/mod.rs, and              *
 * proposer/candidate.rs. Update-specific checking lives in Update.tla.    *
 *************************************************************************)

EXTENDS Integers, Naturals, FiniteSets, Sequences, TLC

CONSTANTS Server, NodeOrder, MaxTerm, MaxLogIndex, InitialConfig,
          TickPreVoteModes

\* UPDATE-MAP
\* code: openraft/src/config/runtime_config.rs:RuntimeConfig.enable_pre_vote,
\*       openraft/src/raft/runtime_config_handle.rs:pre_vote,
\*       openraft/src/core/raft_core.rs:handle_tick_election
\* update: Update!AffectedActions (TickPreElect); the tick reads the runtime
\*         flag on every tick and the flag can be toggled at runtime, so the
\*         tick may observe any value in TickPreVoteModes.

ReferenceServer == {"1", "2", "3"}
ReferenceNodeOrder == <<"1", "2", "3">>
ReferenceInitialConfig == {"1", "2", "3"}
ReferenceTickPreVoteModes == {FALSE, TRUE}

ASSUME /\ Server /= {}
       /\ Len(NodeOrder) = Cardinality(Server)
       /\ {NodeOrder[k] : k \in 1..Len(NodeOrder)} = Server
       /\ InitialConfig \subseteq Server
       /\ InitialConfig /= {}
       /\ MaxTerm \in Nat \ {0}
       /\ MaxLogIndex \in Nat \ {0}
       /\ TickPreVoteModes \subseteq BOOLEAN

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

\* Repair (V0 model defect): an absent log is Option::None for every node;
\* the record keeps the owner's id only as a placeholder, so two absent logs
\* are equal regardless of placeholder (log_id/mod.rs:18-61, Option ord).
\* Without this, a request from an empty log is never "at least as recent"
\* as another empty log and no multi-voter election can ever succeed.
LogEQ(a, b) == IF ~a.present /\ ~b.present THEN TRUE ELSE a = b
LogLE(a, b) == LogEQ(a, b) \/ LogLT(a, b)

IsConfig(c) ==
    /\ c \in Seq(SUBSET Server)
    /\ Len(c) \in 1..2
    /\ \A k \in 1..Len(c) : c[k] /= {}

ConfigVoters(c) == UNION {c[k] : k \in 1..Len(c)}
InConfig(i, c) == i \in ConfigVoters(c)
Majority(ids, oneConfig) == 2 * Cardinality(ids \cap oneConfig) > Cardinality(oneConfig)
VoterCount(c) == Cardinality(ConfigVoters(c))

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
    \* code: openraft/src/engine/engine_impl.rs:Engine.pre_candidate,new_pre_candidate
    \* update: Update!AffectedActions, Update!PreVoteElectionPremiseCurrent
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
vars == <<runtimeVars, voteVars, candidateVars, leaderVars, logVars, configVars, messages,
          preVoteVars>>

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
    /\ preCandidateActive = [i \in Server |-> FALSE]
    /\ preCandidateVote = vote
    /\ preCandidateConfig = [i \in Server |-> <<InitialConfig>>]
    /\ preGrants = [i \in Server |-> {}]

(***************************************************************************
 * Election engine transition. Candidate membership and last log are       *
 * snapshotted before the pending self vote is installed. SaveVote is       *
 * queued before SendVote.                                                  *
 * openraft/src/engine/engine_impl.rs:113-130,262-289                       *
 * openraft/src/engine/handler/vote_handler/mod.rs:131-147                  *
 *                                                                          *
 * DoElect is Engine::do_elect itself; it has no voter or role guard of its *
 * own (callers guard). The update makes it drop any in-flight Pre-Vote     *
 * round first (engine_impl.rs:263-264). It is shared by StartElection and  *
 * by the Pre-Vote quorum path (handle_pre_vote_resp -> elect()).           *
 *************************************************************************)
\* UPDATE-MAP
\* code: openraft/src/engine/engine_impl.rs:do_elect (pre_candidate = None)
\* update: Update!AffectedActions (StartElection wrappers, PreVoteElect)
DoElect(i) ==
    /\ LET nv == Vote(vote[i].term + 1, i, FALSE) IN
       /\ vote' = [vote EXCEPT ![i] = nv]
       /\ candidateActive' = [candidateActive EXCEPT ![i] = TRUE]
       /\ candidateVote' = [candidateVote EXCEPT ![i] = nv]
       \* server_state_handler().update_server_state_if_changed()
       /\ role' = [role EXCEPT ![i] = RoleFrom(i, nv, effectiveConfig[i])]
    /\ candidateConfig' = [candidateConfig EXCEPT ![i] = effectiveConfig[i]]
    /\ grants' = [grants EXCEPT ![i] = {}]
    /\ sentVoteReq' = [sentVoteReq EXCEPT ![i] = {}]
    /\ votePersistPending' = [votePersistPending EXCEPT ![i] = TRUE]
    /\ sendVotePending' = [sendVotePending EXCEPT ![i] = TRUE]
    \* update_vote(uncommitted) installs a zero leader lease
    /\ leaseValid' = [leaseValid EXCEPT ![i] = FALSE]
    /\ preCandidateActive' = [preCandidateActive EXCEPT ![i] = FALSE]
    /\ UNCHANGED <<durableVote, replyPending, replyMessage, leaderVars,
                    logVars, configVars, crashed, preCandidateVote,
                    preCandidateConfig, preGrants>>

StartElection(i, transfer) ==
    /\ ~crashed[i]
    /\ InConfig(i, effectiveConfig[i])
    /\ vote[i].term < MaxTerm
    /\ ~votePersistPending[i]
    /\ ~replyPending[i]
    /\ DoElect(i)
    /\ seenGreaterLog' = [seenGreaterLog EXCEPT ![i] = FALSE]
    /\ UNCHANGED messages

(***************************************************************************
 * Tick: skip a Leader; a single voter elects directly; with Pre-Vote      *
 * disabled a multi-voter elects directly; with Pre-Vote enabled a          *
 * multi-voter whose vote lease/election timeout has expired starts a       *
 * Pre-Vote round instead (TickPreElect below).                             *
 * openraft/src/core/raft_core.rs:1959-2036                                 *
 *************************************************************************)
\* UPDATE-MAP
\* code: openraft/src/core/raft_core.rs:handle_tick_election (pre_vote branch)
\* update: Update!AffectedActions (MCTickElect is changed by its new guard)
TickElect(i) ==
    /\ role[i] /= "Leader"
    /\ \/ FALSE \in TickPreVoteModes
       \/ VoterCount(effectiveConfig[i]) = 1
    /\ StartElection(i, FALSE)

\* ExternalCommand::Elect { pre_vote: false } and leadership transfer are
\* unchanged (raft_core.rs:1683-1695).
ExternalElect(i) == StartElection(i, FALSE)
StartTransferElection(i) == StartElection(i, TRUE)

(***************************************************************************
 * Engine::pre_elect. The hypothetical next-term vote is built from the     *
 * current vote; the pre-candidate freezes the effective membership and     *
 * last log and grants itself. A self quorum (single voter) calls elect()   *
 * at once. Otherwise only SendPreVote is queued: no vote change, no        *
 * SaveVote, no server-state change. SendPreVote needs no I/O wait, so the  *
 * runtime spawns one request per current effective voter in the same      *
 * command drain (raft_core.rs:2342-2344, spawn_parallel_vote_requests);    *
 * delivery delay/loss is the network's.                                    *
 * openraft/src/engine/engine_impl.rs:144-165,291-322                       *
 * openraft/src/core/raft_core.rs:1385-1478                                 *
 *************************************************************************)
\* UPDATE-MAP
\* code: openraft/src/engine/engine_impl.rs:pre_elect,new_pre_candidate
\* update: Update!AffectedActions (MCTickPreElect, MCExternalPreElect)
PreVoteReqs(i, pv) ==
    {Message("PreVoteReq", i, j, pv, lastLog[i], FALSE, FALSE) :
        j \in ConfigVoters(effectiveConfig[i]) \ {i}}

PreElect(i, fromTick) ==
    /\ ~crashed[i]
    /\ InConfig(i, effectiveConfig[i])
    /\ vote[i].term < MaxTerm
    /\ ~votePersistPending[i]
    /\ ~replyPending[i]
    /\ LET pv == Vote(vote[i].term + 1, i, FALSE) IN
       IF IsQuorum(effectiveConfig[i], {i})
       THEN \* grant_by(self) reached a quorum: self.elect(); return
            /\ DoElect(i)
            /\ seenGreaterLog' = [seenGreaterLog EXCEPT ![i] = IF fromTick THEN FALSE ELSE @]
            /\ UNCHANGED messages
       ELSE /\ preCandidateActive' = [preCandidateActive EXCEPT ![i] = TRUE]
            /\ preCandidateVote' = [preCandidateVote EXCEPT ![i] = pv]
            /\ preCandidateConfig' = [preCandidateConfig EXCEPT ![i] = effectiveConfig[i]]
            /\ preGrants' = [preGrants EXCEPT ![i] = {i}]
            /\ messages' = messages \cup PreVoteReqs(i, pv)
            \* handle_tick_election resets the greater-log hint before pre_elect
            /\ seenGreaterLog' = [seenGreaterLog EXCEPT ![i] = IF fromTick THEN FALSE ELSE @]
            /\ UNCHANGED <<role, crashed, voteVars, candidateVars, leaderVars,
                            logVars, configVars>>

\* Tick with the runtime enable_pre_vote flag set, multi-voter only, after
\* the local vote's election timeout (which implies an expired lease). The
\* in-flight-round rate limit (raft_core.rs:2014-2024) only delays a tick and
\* is abstracted with time.
TickPreElect(i) ==
    /\ role[i] /= "Leader"
    /\ TRUE \in TickPreVoteModes
    /\ VoterCount(effectiveConfig[i]) > 1
    /\ ~leaseValid[i]
    /\ PreElect(i, TRUE)

\* ExternalCommand::Elect { pre_vote: true } / Trigger::elect(true): only the
\* voter check guards it, for any role (raft_core.rs:1683-1695).
ExternalPreElect(i) == PreElect(i, FALSE)

(***************************************************************************
 * save_vote() is awaited. A pending election gets a local granted response;
 * a vote-request reply held on IOFlushed becomes visible here.              *
 * openraft/src/core/raft_core.rs:2138-2166                                 *
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
 * openraft/src/core/raft_core.rs:1360-1428,2203-2205                       *
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
 * the lease and can reply immediately.                                     *
 * openraft/src/engine/engine_impl.rs:285-326                               *
 * openraft/src/engine/handler/vote_handler/mod.rs:105-160                  *
 * openraft/src/core/raft_core.rs:1483-1499                                 *
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
       \* UPDATE-MAP
       \* code: openraft/src/engine/handler/vote_handler/mod.rs:become_following
       \* update: Update!InteractionActions (MCDeliverVoteRequest)
       /\ preCandidateActive' = [preCandidateActive EXCEPT ![i] = IF follows THEN FALSE ELSE @]
       /\ leaderActive' = [leaderActive EXCEPT ![i] = IF follows THEN FALSE
                                                      ELSE IF grant /\ nv.committed /\ nv.node = i
                                                           THEN TRUE ELSE @]
       /\ leaderVote' = [leaderVote EXCEPT ![i] = IF grant /\ nv.committed /\ nv.node = i
                                                  THEN nv ELSE @]
    /\ UNCHANGED <<durableVote, sendVotePending, candidateVote, candidateConfig,
                    grants, sentVoteReq, leaderCertified, leaderConfig,
                    leaderGrants, logVars, configVars, crashed, seenGreaterLog,
                    preCandidateVote, preCandidateConfig, preGrants>>

DeliverVoteRequest(m) ==
    /\ m \in messages
    /\ HandleVoteRequest(m.dest, m, TRUE)

(***************************************************************************
 * Exact granted vote equality advances the frozen quorum. Establishment    *
 * commits the vote in projected state and projects the leader blank log;   *
 * committed vote persistence remains pending.                              *
 * openraft/src/engine/engine_impl.rs:329-389,688-716                       *
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
       /\ lastLog' = [lastLog EXCEPT ![i] = IF wins /\ newIndex <= MaxLogIndex
                                              THEN Log(cv.term, cv.node, newIndex) ELSE @]
       /\ logFlushPending' = [logFlushPending EXCEPT ![i] = IF wins /\ newIndex <= MaxLogIndex
                                                                THEN TRUE ELSE @]
       /\ seenGreaterLog' = [seenGreaterLog EXCEPT ![i] =
                                IF candidateActive[i] /\ ~exact /\ LogLT(lastLog[i], m.lastLog)
                                THEN TRUE ELSE @]
       \* Repair (old abstraction): establish_leader's update_vote(committed)
       \* installs config.leader_lease (> 0), adopting an uncommitted vote
       \* installs a zero lease (vote_handler/mod.rs:121-139).
       /\ leaseValid' = [leaseValid EXCEPT ![i] = IF wins THEN TRUE
                                                  ELSE IF adopt THEN FALSE ELSE @]
       \* UPDATE-MAP
       \* code: openraft/src/engine/engine_impl.rs:establish_leader (no
       \*       pre_candidate reset), vote_handler/mod.rs:become_leader /
       \*       become_following (resets pre_candidate only when following)
       \* update: Update!InteractionActions (MCDeliverVoteResponse),
       \*         Update!PreVoteElectionPremiseCurrent
       /\ preCandidateActive' = [preCandidateActive EXCEPT ![i] =
                                    IF adopt /\ RoleFrom(i, stripped, effectiveConfig[i])
                                                \in {"Follower", "Learner"}
                                    THEN FALSE ELSE @]
    /\ UNCHANGED <<durableVote, replyPending, replyMessage,
                    candidateVote, candidateConfig, sentVoteReq, durableLastLog,
                    configVars, crashed, preCandidateVote, preCandidateConfig,
                    preGrants>>

DeliverVoteResponse(m) ==
    /\ m \in messages
    /\ HandleVoteResponse(m.dest, m, TRUE)

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
 * openraft/src/engine/engine_impl.rs:479-508                               *
 *************************************************************************)
CommitMembership(i) ==
    /\ ~crashed[i]
    /\ committedConfigIndex[i] < effectiveConfigIndex[i]
    /\ committedConfig' = [committedConfig EXCEPT ![i] = effectiveConfig[i]]
    /\ committedConfigIndex' = [committedConfigIndex EXCEPT ![i] = effectiveConfigIndex[i]]
    /\ UNCHANGED <<runtimeVars, voteVars, candidateVars, leaderVars, logVars,
                    effectiveConfig, effectiveConfigIndex, durableConfig,
                    durableConfigIndex, messages, preVoteVars>>

RefreshServerState(i) ==
    /\ ~crashed[i]
    /\ committedConfigIndex[i] = effectiveConfigIndex[i]
    /\ role' = [role EXCEPT ![i] = RoleFrom(i, vote[i], effectiveConfig[i])]
    /\ leaderActive' = [leaderActive EXCEPT ![i] = IF RoleFrom(i, vote[i], effectiveConfig[i]) = "Leader"
                                                    THEN @ ELSE FALSE]
    /\ candidateActive' = [candidateActive EXCEPT ![i] =
                              IF RoleFrom(i, vote[i], effectiveConfig[i]) = "Candidate" THEN @ ELSE FALSE]
    \* refresh_server_state -> update_internal_server_state: become_following
    \* (which drops pre_candidate) unless the vote is still self-led.
    \* engine_impl.rs:659-673, vote_handler/mod.rs:153-162,234-251
    /\ preCandidateActive' = [preCandidateActive EXCEPT ![i] =
                              IF RoleFrom(i, vote[i], effectiveConfig[i]) \in {"Leader", "Candidate"}
                              THEN @ ELSE FALSE]
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
 * openraft/src/core/raft_core.rs:2123-2137,2225-2228                       *
 *************************************************************************)
SendAppendEntries(i, j) ==
    /\ ~crashed[i]
    /\ leaderActive[i]
    /\ vote[i].committed /\ vote[i].node = i
    /\ VoteLE(vote[i], durableVote[i])
    /\ j \in ConfigVoters(effectiveConfig[i]) \ {i}
    /\ messages' = messages \cup
          {Message("Append", i, j, vote[i], lastLog[i], FALSE, FALSE)}
    /\ UNCHANGED <<runtimeVars, voteVars, candidateVars, leaderVars, logVars, configVars,
                    preVoteVars>>

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
       \* UPDATE-MAP
       \* code: vote_handler/mod.rs:update_vote -> become_following (also for
       \*       an equal vote: heartbeats from the current leader end a round)
       \* update: Update!InteractionActions (MCDeliverAppendEntries)
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
    /\ UNCHANGED <<runtimeVars, voteVars, candidateVars, leaderVars, logVars, configVars,
                    preVoteVars>>

(***************************************************************************
 * Crash keeps durable variables. Restart reconstructs vote/log/config and  *
 * clears candidate, command, lease, and greater-log transient state.       *
 * openraft/src/storage/helper.rs:83-223,313-399                            *
 * openraft/src/engine/engine_impl.rs:102-181                               *
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
    \* The engine is rebuilt: Engine::new sets pre_candidate = None
    \* (engine_impl.rs:108-119).
    /\ preCandidateActive' = [preCandidateActive EXCEPT ![i] = FALSE]
    /\ preGrants' = [preGrants EXCEPT ![i] = {}]
    /\ UNCHANGED <<durableVote, durableLastLog, durableConfig, durableConfigIndex, messages,
                    preCandidateVote, preCandidateConfig>>

(***************************************************************************
 * Engine::handle_pre_vote_req: a pure query. Lease (never a transfer),     *
 * then last-log, then the same vote comparison as a real vote; no vote,    *
 * lease, server-state, or command change. RaftCore replies at once with    *
 * `when: None` (no vote I/O to wait for). The reply carries the            *
 * requester's pre-candidate vote as the runtime correlation key            *
 * (raft_core.rs:1438-1458 attaches `candidate_vote`); the responder's own  *
 * vote in the RPC body is not consumed by handle_pre_vote_resp.            *
 * openraft/src/engine/engine_impl.rs:406-447                               *
 * openraft/src/core/raft_core.rs:1551-1562                                 *
 *************************************************************************)
\* UPDATE-MAP
\* code: openraft/src/engine/engine_impl.rs:handle_pre_vote_req,
\*       openraft/src/core/raft_core.rs:handle_pre_vote_request
\* update: Update!AffectedActions (MCDeliverPreVoteRequest)
PreVoteGrant(i, m) ==
    /\ ~(vote[i].committed /\ leaseValid[i])
    /\ LogLE(lastLog[i], m.lastLog)
    /\ VoteLE(vote[i], m.vote)

HandlePreVoteRequest(i, m, consume) ==
    /\ ~crashed[i]
    /\ m.kind = "PreVoteReq"
    /\ m.dest = i
    /\ messages' = RemainingMessages(m, consume) \cup
          {Message("PreVoteResp", i, m.source, m.vote, lastLog[i], PreVoteGrant(i, m), FALSE)}
    /\ UNCHANGED <<runtimeVars, voteVars, candidateVars, leaderVars, logVars,
                    configVars, preVoteVars>>

DeliverPreVoteRequest(m) ==
    /\ m \in messages
    /\ HandlePreVoteRequest(m.dest, m, TRUE)

(***************************************************************************
 * Pre-Vote response. RaftCore drops it unless a pre-candidate exists and   *
 * its vote's leader id equals the response's correlation vote             *
 * (raft_core.rs:1803-1820,2066-2090). Engine::handle_pre_vote_resp then:   *
 *   granted  -> grant_by(target); a quorum calls self.elect();             *
 *   rejected -> only a greater responder log sets seen_greater_log.        *
 * Nothing else changes; in particular the round is not tied to the local   *
 * vote/role it was started from.                                           *
 * openraft/src/engine/engine_impl.rs:511-554                               *
 *************************************************************************)
\* UPDATE-MAP
\* code: openraft/src/engine/engine_impl.rs:handle_pre_vote_resp,
\*       openraft/src/core/raft_core.rs:Notification::PreVoteResponse,
\*       does_pre_candidate_vote_match
\* update: Update!AffectedActions (MCDeliverPreVoteResponse),
\*         Update!PreVoteElectStep
PreVoteMatches(i, m) ==
    /\ preCandidateActive[i]
    /\ m.vote.term = preCandidateVote[i].term
    /\ m.vote.node = preCandidateVote[i].node

PreVoteQuorumWith(i, m) == IsQuorum(preCandidateConfig[i], preGrants[i] \cup {m.source})

\* Candidate::grant_by -> VecProgress::update(target).expect("target not in
\* quorum set"); the progress tracker holds only the round's frozen voters
\* (proposer/candidate.rs:66-82,106-112; progress/vec_progress.rs:177-189).
PreVoteGranterKnown(i, m) == m.source \in ConfigVoters(preCandidateConfig[i])

HandlePreVoteResponseElect(i, m, consume) ==
    /\ ~crashed[i]
    /\ m.kind = "PreVoteResp"
    /\ m.dest = i
    /\ PreVoteMatches(i, m)
    /\ m.granted
    /\ PreVoteGranterKnown(i, m)
    /\ PreVoteQuorumWith(i, m)
    /\ vote[i].term < MaxTerm          \* model bound only
    \* quorum_granted -> self.elect(): do_elect drops the pre-candidate
    /\ DoElect(i)
    /\ messages' = RemainingMessages(m, consume)
    /\ UNCHANGED seenGreaterLog

HandlePreVoteResponseTally(i, m, consume) ==
    /\ ~crashed[i]
    /\ m.kind = "PreVoteResp"
    /\ m.dest = i
    /\ PreVoteMatches(i, m)
    /\ m.granted
    /\ PreVoteGranterKnown(i, m)
    /\ ~PreVoteQuorumWith(i, m)
    /\ preGrants' = [preGrants EXCEPT ![i] = @ \cup {m.source}]
    /\ messages' = RemainingMessages(m, consume)
    /\ UNCHANGED <<runtimeVars, voteVars, candidateVars, leaderVars, logVars,
                    configVars, preCandidateActive, preCandidateVote, preCandidateConfig>>

HandlePreVoteResponseReject(i, m, consume) ==
    /\ ~crashed[i]
    /\ m.kind = "PreVoteResp"
    /\ m.dest = i
    /\ PreVoteMatches(i, m)
    /\ ~m.granted
    /\ seenGreaterLog' = [seenGreaterLog EXCEPT ![i] =
                            IF LogLT(lastLog[i], m.lastLog) THEN TRUE ELSE @]
    /\ messages' = RemainingMessages(m, consume)
    /\ UNCHANGED <<role, crashed, voteVars, candidateVars, leaderVars, logVars,
                    configVars, preVoteVars>>

HandlePreVoteResponseStale(i, m, consume) ==
    /\ ~crashed[i]
    /\ m.kind = "PreVoteResp"
    /\ m.dest = i
    /\ ~PreVoteMatches(i, m)
    /\ messages' = RemainingMessages(m, consume)
    /\ UNCHANGED <<runtimeVars, voteVars, candidateVars, leaderVars, logVars,
                    configVars, preVoteVars>>

\* A granted response that passes the leader-id filter but comes from a node
\* outside the round's frozen voter set reaches grant_by's expect(): the
\* RaftCore task panics. Modeled as the node stopping (as Crash); Restart
\* reconstructs it. Reachable when two rounds share a correlation key (same
\* local vote) but froze different memberships.
\* UPDATE-MAP
\* code: openraft/src/proposer/candidate.rs:grant_by,
\*       openraft/src/engine/engine_impl.rs:534-535
\* update: Update!PreVoteGrantFromRoundMember
HandlePreVoteResponseNonMember(i, m, consume) ==
    /\ ~crashed[i]
    /\ m.kind = "PreVoteResp"
    /\ m.dest = i
    /\ PreVoteMatches(i, m)
    /\ m.granted
    /\ ~PreVoteGranterKnown(i, m)
    /\ crashed' = [crashed EXCEPT ![i] = TRUE]
    /\ messages' = RemainingMessages(m, consume)
    /\ UNCHANGED <<role, seenGreaterLog, voteVars, candidateVars, leaderVars, logVars,
                    configVars, preVoteVars>>

HandlePreVoteResponse(i, m, consume) ==
    \/ HandlePreVoteResponseElect(i, m, consume)
    \/ HandlePreVoteResponseNonMember(i, m, consume)
    \/ HandlePreVoteResponseTally(i, m, consume)
    \/ HandlePreVoteResponseReject(i, m, consume)
    \/ HandlePreVoteResponseStale(i, m, consume)

DeliverPreVoteResponse(m) ==
    /\ m \in messages
    /\ HandlePreVoteResponse(m.dest, m, TRUE)

Next ==
    \/ \E i \in Server : TickElect(i) \/ ExternalElect(i) \/ StartTransferElection(i)
    \/ \E i \in Server : TickPreElect(i) \/ ExternalPreElect(i)
    \/ \E i \in Server : PersistVote(i) \/ FinishVoteBroadcast(i) \/ FlushLog(i)
    \/ \E i \in Server : ExpireLease(i) \/ Restart(i) \/ RefreshServerState(i)
    \/ \E i \in Server, j \in Server : SendVoteRequest(i, j) \/ SendAppendEntries(i, j)
    \/ \E m \in messages : DeliverVoteRequest(m) \/ DeliverVoteResponse(m)
                              \/ DeliverAppendEntries(m) \/ DropMessage(m)
                              \/ DeliverPreVoteRequest(m) \/ DeliverPreVoteResponse(m)
    \/ \E i \in Server, target \in SUBSET Server : AppendJointConfig(i, target)
    \/ \E i \in Server : AppendUniformConfig(i) \/ CommitMembership(i) \/ Crash(i)

Spec == Init /\ [][Next]_vars

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
