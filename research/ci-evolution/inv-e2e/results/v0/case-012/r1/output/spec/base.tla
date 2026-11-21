------------------------------ MODULE base ------------------------------
\* Incremental update of the V0 OpenRaft reference (exact-old baseline commit
\* ce863f4) to the updated source (commit aa05a38). The update moves leader
\* commit calculation from LeaderState::calc_commit_log_id (full recomputation
\* over replication matched values) into Engine::update_progress over the
\* leader-owned VecProgress (incremental, cached committed value, quorum set
\* upgraded on effective-membership change). See spec/changelog.md and
\* Update.tla for the update focus.
EXTENDS Naturals, Integers, FiniteSets, Sequences, TLC

CONSTANTS Server, MaxTerm, MaxIndex, AllowedConfigs,
          \* Ascending node-id order. VecProgress::new and upgrade_quorum_set
          \* iterate QuorumSet::ids(), a BTreeSet iterator (ascending ids):
          \* openraft/src/membership/effective_membership.rs:146-158.
          ServerOrder

Nil == -1

ASSUME /\ Server # {}
       /\ MaxTerm \in Nat \ {0}
       /\ MaxIndex \in Nat
       /\ ServerOrder \in Seq(Server)
       /\ \A s \in Server: \E k \in DOMAIN ServerOrder: ServerOrder[k] = s
       /\ \A a, b \in DOMAIN ServerOrder: a # b => ServerOrder[a] # ServerOrder[b]

Role == {"follower", "candidate", "leader", "learner"}
Index == Nil..MaxIndex
Term == 0..MaxTerm
IMax(a, b) == IF a >= b THEN a ELSE b
IMin(a, b) == IF a <= b THEN a ELSE b

ConfigOK(cfg) ==
    /\ cfg \in SUBSET (SUBSET Server)
    /\ cfg # {}
    /\ \A group \in cfg: group # {}

Voters(cfg) == UNION cfg

\* Membership::is_quorum / Joint::is_quorum:
\* openraft/src/quorum/quorum_set_impl.rs:11-22
\* openraft/src/quorum/joint.rs:56-63
Quorum(cfg, granted) ==
    /\ ConfigOK(cfg)
    /\ \A group \in cfg:
          2 * Cardinality(group \intersect granted) > Cardinality(group)

\* ---------------------------------------------------------------------------
\* Log-id values used by the leader progress.
\* A LogId is ordered by (leader_id.term, leader_id.node_id, index)
\* (openraft/src/vote/leader_id.rs:13, raft_types.rs:11). Within every modeled
\* execution each term has at most one appending leader (ElectionSafety), so the
\* (term,index) order coincides with LogId order on existing entries; node_id is
\* not represented in MC and is checked against the vote by Trace.tla.
\* `None` (Option::default) is 0 and every Some(log id) is > 0.
\* ---------------------------------------------------------------------------
LV(t, idx) == IF idx = Nil THEN 0 ELSE t * (MaxIndex + 1) + idx + 1
ValIndex(v) == IF v = 0 THEN Nil ELSE (v - 1) % (MaxIndex + 1)
ValTerm(v) == IF v = 0 THEN 0 ELSE (v - 1) \div (MaxIndex + 1)

\* ---------------------------------------------------------------------------
\* VecProgress (openraft/src/progress/mod.rs). UPDATE-MAP
\* code: openraft/src/progress/mod.rs:41-231 (VecProgress, update,
\*       move_up, upgrade_quorum_set); now on the production commit path via
\*       openraft/src/leader/leader.rs:29 and engine_impl.rs:617-648
\* update: Update!ProgressCommittedSound, Update!ProgressSortedAboveCommitted,
\*         Update!ProgressWithinReplication, Update!ProgressTracksEffective
\* The internal vector order and the cached `committed` are represented
\* explicitly because the commit result depends on them (Chapter 1 decision).
\* ---------------------------------------------------------------------------
NoQS == {}
SortedIds(S) == SelectSeq(ServerOrder, LAMBDA s: s \in S)

\* VecProgress::new: one (id, V::default()) per quorum id, in ids() order.
\* openraft/src/progress/mod.rs:80-89
PNew(qs) ==
    LET ids == SortedIds(Voters(qs))
    IN [vec |-> [k \in 1..Len(ids) |-> [id |-> ids[k], val |-> 0]],
        committed |-> 0,
        qs |-> qs]

\* VecProgress::index: openraft/src/progress/mod.rs:92-102
PIdx(vec, id) ==
    IF \E k \in DOMAIN vec: vec[k].id = id
    THEN CHOOSE k \in DOMAIN vec: vec[k].id = id
    ELSE 0

IdsUpTo(vec, i) == {vec[k].id : k \in 1..i}

\* VecProgress::move_up: swap upward while the predecessor is strictly smaller.
\* openraft/src/progress/mod.rs:104-117 (1-based positions here)
RECURSIVE MoveUp(_, _)
MoveUp(vec, p) ==
    IF p = 1 THEN <<vec, 1>>
    ELSE IF vec[p - 1].val < vec[p].val
         THEN MoveUp([vec EXCEPT ![p - 1] = vec[p], ![p] = vec[p - 1]], p - 1)
         ELSE <<vec, p>>

\* Scan loop of VecProgress::update: from the moved position downward, stop at
\* the first value <= committed, otherwise take the first prefix [0..=i] that
\* forms a quorum and set committed := vector[i].
\* openraft/src/progress/mod.rs:184-201
RECURSIVE Scan(_, _, _, _)
Scan(vec, qs, c, i) ==
    IF i > Len(vec) THEN c
    ELSE IF vec[i].val <= c THEN c
    ELSE IF Quorum(qs, IdsUpTo(vec, i)) THEN vec[i].val
    ELSE Scan(vec, qs, c, i + 1)

\* VecProgress::update: openraft/src/progress/mod.rs:163-205
PUpdate(p, id, value) ==
    LET k == PIdx(p.vec, id)
    IN IF k = 0
       THEN p                                         \* unknown id: ignored (mod.rs:166-171)
       ELSE LET prev == p.vec[k].val
            IN IF prev = value
               THEN p                                 \* mod.rs:176-178
               ELSE LET v1 == [p.vec EXCEPT ![k].val = value]   \* mod.rs:182
                    IN IF prev <= p.committed /\ p.committed < value   \* mod.rs:184
                       THEN LET mu == MoveUp(v1, k)
                            IN [vec |-> mu[1],
                                committed |-> Scan(mu[1], p.qs, p.committed, mu[2]),
                                qs |-> p.qs]
                       ELSE [p EXCEPT !.vec = v1]     \* value raised in place

PGet(p, id) == p.vec[PIdx(p.vec, id)].val

\* VecProgress::upgrade_quorum_set: new progress for the new quorum set, then
\* replay every OLD quorum id's value through update(), in old ids() order.
\* openraft/src/progress/mod.rs:222-232
RECURSIVE UpgradeFrom(_, _, _)
UpgradeFrom(np, old, ids) ==
    IF ids = <<>> THEN np
    ELSE UpgradeFrom(PUpdate(np, Head(ids), PGet(old, Head(ids))), old, Tail(ids))

PUpgrade(p, newQS) == UpgradeFrom(PNew(newQS), p, SortedIds(Voters(p.qs)))

VARIABLES
    currentTerm,
    voteFor,
    voteCommitted,
    role,
    voteGranted,
    lastLog,
    logTerm,
    committed,
    matchedIndex,
    matchedTerm,
    committedConfig,
    effectiveConfig,
    committedMembershipIndex,
    committedMembershipTerm,
    effectiveMembershipIndex,
    effectiveMembershipTerm,
    messages,
    crashed,
    witnessIndex,
    witnessNodes,
    witnessConfig,
    witnessTerm,
    \* --- update: Engine.state.leader (Option<Leader>) and its VecProgress ---
    leaderSome,      \* RaftState.leader.is_some()      (raft_state.rs:44)
    progVec,         \* Leader.progress.vector           (progress/mod.rs:56-60)
    progCommitted,   \* Leader.progress.committed        (progress/mod.rs:53)
    progQS,          \* Leader.progress.quorum_set       (progress/mod.rs:50)
    \* --- repair: LeaderState::run writes the blank entry before it handles
    \*     any replication event (core/leader_state.rs:72-97) ---
    blankPending

vars == <<
    currentTerm, voteFor, voteCommitted, role, voteGranted,
    lastLog, logTerm, committed, matchedIndex, matchedTerm,
    committedConfig, effectiveConfig,
    committedMembershipIndex, committedMembershipTerm,
    effectiveMembershipIndex, effectiveMembershipTerm,
    messages, crashed,
    witnessIndex, witnessNodes, witnessConfig, witnessTerm,
    leaderSome, progVec, progCommitted, progQS, blankPending
>>

progressVars == <<leaderSome, progVec, progCommitted, progQS>>

InitialConfig == {Server}
\* Arbitrary total order for stand-alone base.cfg runs (MC/Trace bind a concrete one).
AnyServerOrder ==
    CHOOSE s \in [1..Cardinality(Server) -> Server]:
        \A a, b \in 1..Cardinality(Server): a # b => s[a] # s[b]
BaseAllowedConfigs == {InitialConfig}

\* RaftCore::do_main resets volatile commit while reconstructing stored state:
\* openraft/src/core/raft_core.rs:181-205
Init ==
    /\ currentTerm = [i \in Server |-> 0]
    /\ voteFor = [i \in Server |-> i]
    /\ voteCommitted = [i \in Server |-> FALSE]
    /\ role = [i \in Server |-> "follower"]
    /\ voteGranted = [i \in Server |-> {}]
    /\ lastLog = [i \in Server |-> Nil]
    /\ logTerm = [i \in Server |-> [k \in 0..MaxIndex |-> 0]]
    /\ committed = [i \in Server |-> Nil]
    /\ matchedIndex = [i \in Server |-> [j \in Server |-> Nil]]
    /\ matchedTerm = [i \in Server |-> [j \in Server |-> 0]]
    /\ committedConfig = [i \in Server |-> InitialConfig]
    /\ effectiveConfig = [i \in Server |-> InitialConfig]
    /\ committedMembershipIndex = [i \in Server |-> Nil]
    /\ committedMembershipTerm = [i \in Server |-> 0]
    /\ effectiveMembershipIndex = [i \in Server |-> Nil]
    /\ effectiveMembershipTerm = [i \in Server |-> 0]
    /\ messages = {}
    /\ crashed = {}
    /\ witnessIndex = [i \in Server |-> Nil]
    /\ witnessNodes = [i \in Server |-> {}]
    /\ witnessConfig = [i \in Server |-> InitialConfig]
    /\ witnessTerm = [i \in Server |-> 0]
    /\ leaderSome = [i \in Server |-> FALSE]
    /\ progVec = [i \in Server |-> <<>>]
    /\ progCommitted = [i \in Server |-> 0]
    /\ progQS = [i \in Server |-> NoQS]
    /\ blankPending = [i \in Server |-> FALSE]

\* Engine::calc_server_state: openraft/src/engine/engine_impl.rs:915-945
CalcServerState(i, effCfg, leaderSomeI) ==
    IF i \in Voters(effCfg)
    THEN IF voteFor[i] = i /\ voteCommitted[i] THEN "leader"
         ELSE IF leaderSomeI THEN "candidate" ELSE "follower"
    ELSE "learner"

\* ---------------------------------------------------------------------------
\* Engine-local state transformers (pure). One record carries the node-local
\* engine state that the changed helpers read/write so that several helper
\* calls inside one atomic Engine method compose in code order.
\* ---------------------------------------------------------------------------
Local(i) ==
    [role |-> role[i],
     leaderSome |-> leaderSome[i],
     p |-> [vec |-> progVec[i], committed |-> progCommitted[i], qs |-> progQS[i]],
     committed |-> committed[i],
     effCfg |-> effectiveConfig[i],
     effIdx |-> effectiveMembershipIndex[i],
     effTerm |-> effectiveMembershipTerm[i],
     cmCfg |-> committedConfig[i],
     cmIdx |-> committedMembershipIndex[i],
     cmTerm |-> committedMembershipTerm[i],
     adv |-> FALSE,
     wIdx |-> witnessIndex[i],
     wTerm |-> witnessTerm[i],
     wCfg |-> witnessConfig[i]]

\* RaftState::update_committed: raise committed if greater; then promote the
\* effective membership to committed when covered. UPDATE-MAP
\* code: openraft/src/raft_state.rs:121-136
\* update: Update!AffectedActions (leader commit and follower commit callers)
\* LogId comparison is by index here: both values are ids of the same local log.
UpdateCommitted(L, cIdx, cTerm, qsUsed) ==
    IF cIdx # Nil /\ cIdx > L.committed
    THEN LET promote == cIdx >= L.effIdx
         IN [L EXCEPT !.committed = cIdx,
                      !.cmCfg = IF promote THEN L.effCfg ELSE @,
                      !.cmIdx = IF promote THEN L.effIdx ELSE @,
                      !.cmTerm = IF promote THEN L.effTerm ELSE @,
                      !.adv = TRUE,
                      !.wIdx = cIdx,
                      !.wTerm = cTerm,
                      !.wCfg = qsUsed]
    ELSE L

\* Engine::update_progress. UPDATE-MAP
\* code: openraft/src/engine/engine_impl.rs:617-648
\* update: Update!AffectedActions, Update!ProgressCommittedSound
EngineUpdateProgress(L, target, value, voteTerm) ==
    IF ~L.leaderSome
    THEN L                                              \* engine_impl.rs:622-625
    ELSE LET p2 == PUpdate(L.p, target, value)          \* engine_impl.rs:628
             c == p2.committed
             L2 == [L EXCEPT !.p = p2]
         IN IF c = 0
            THEN L2                                     \* update_committed(None): no-op
            ELSE IF ValTerm(c) # voteTerm
                 THEN L2                                \* not proposed by current leader: engine_impl.rs:631-636
                 ELSE UpdateCommitted(L2, ValIndex(c), ValTerm(c), p2.qs)  \* engine_impl.rs:638-647

\* Engine::update_effective_membership. UPDATE-MAP
\* code: openraft/src/engine/engine_impl.rs:591-615
\* update: Update!AffectedActions, Update!ProgressTracksEffective
EngineUpdateEffective(i, L, idx, t, cfg) ==
    LET pre == CalcServerState(i, L.effCfg, L.leaderSome)     \* engine_impl.rs:595
        post == CalcServerState(i, cfg, L.leaderSome)
        L2 == [L EXCEPT !.effCfg = cfg, !.effIdx = idx, !.effTerm = t,   \* engine_impl.rs:597-599
                        !.p = IF L.leaderSome THEN PUpgrade(L.p, cfg) ELSE @]  \* engine_impl.rs:602-604
    IN IF pre # "leader" /\ pre # post                         \* engine_impl.rs:610-614
       THEN [L2 EXCEPT !.role = post]
       ELSE L2

\* Nodes whose actually replicated log (leader-owned facts, not VecProgress)
\* reaches the commit index. Evaluated on next-state values.
SupportersNext(i, idx, t) ==
    {j \in Server: matchedIndex'[i][j] >= idx /\ matchedTerm'[i][j] = t}

AssignLocal(i, L) ==
    /\ role' = [role EXCEPT ![i] = L.role]
    /\ progVec' = [progVec EXCEPT ![i] = L.p.vec]
    /\ progCommitted' = [progCommitted EXCEPT ![i] = L.p.committed]
    /\ progQS' = [progQS EXCEPT ![i] = L.p.qs]
    /\ committed' = [committed EXCEPT ![i] = L.committed]
    /\ effectiveConfig' = [effectiveConfig EXCEPT ![i] = L.effCfg]
    /\ effectiveMembershipIndex' = [effectiveMembershipIndex EXCEPT ![i] = L.effIdx]
    /\ effectiveMembershipTerm' = [effectiveMembershipTerm EXCEPT ![i] = L.effTerm]
    /\ committedConfig' = [committedConfig EXCEPT ![i] = L.cmCfg]
    /\ committedMembershipIndex' = [committedMembershipIndex EXCEPT ![i] = L.cmIdx]
    /\ committedMembershipTerm' = [committedMembershipTerm EXCEPT ![i] = L.cmTerm]
    /\ witnessIndex' = [witnessIndex EXCEPT ![i] = L.wIdx]
    /\ witnessTerm' = [witnessTerm EXCEPT ![i] = L.wTerm]
    /\ witnessConfig' = [witnessConfig EXCEPT ![i] = L.wCfg]
    /\ witnessNodes' = [witnessNodes EXCEPT
                           ![i] = IF L.adv THEN SupportersNext(i, L.wIdx, L.wTerm) ELSE @]

ResetProgress(i) ==
    /\ leaderSome' = [leaderSome EXCEPT ![i] = FALSE]
    /\ progVec' = [progVec EXCEPT ![i] = <<>>]
    /\ progCommitted' = [progCommitted EXCEPT ![i] = 0]
    /\ progQS' = [progQS EXCEPT ![i] = NoQS]

LogUpToDate(candidate, voter) ==
    IF lastLog[voter] = Nil
    THEN TRUE
    ELSE IF lastLog[candidate] = Nil
         THEN FALSE
         ELSE \/ logTerm[candidate][lastLog[candidate]] > logTerm[voter][lastLog[voter]]
              \/ /\ logTerm[candidate][lastLog[candidate]] = logTerm[voter][lastLog[voter]]
                 /\ lastLog[candidate] >= lastLog[voter]

\* Engine::elect increments the vote, creates the Leader (with a VecProgress
\* over the effective membership), self-grants, and checks the vote quorum
\* through the progress quorum set. UPDATE-MAP
\* code: openraft/src/engine/engine_impl.rs:100-131, raft_state.rs:114-117,
\*       leader/leader.rs:36-53
\* update: Update!AffectedActions
\* A won election starts LeaderState, which resets per-target replication
\* `matched` (core/replication.rs:26-47) and must write the blank entry first.
StartElection(i) ==
    /\ i \notin crashed
    /\ role[i] \in {"follower", "candidate"}
    /\ currentTerm[i] < MaxTerm
    /\ LET nextTerm == currentTerm[i] + 1
           grants == {i}
           np == PNew(effectiveConfig[i])
           won == Quorum(np.qs, grants)
       IN /\ currentTerm' = [currentTerm EXCEPT ![i] = nextTerm]
          /\ voteFor' = [voteFor EXCEPT ![i] = i]
          /\ voteCommitted' = [voteCommitted EXCEPT ![i] = won]
          /\ voteGranted' = [voteGranted EXCEPT ![i] = grants]
          /\ role' = [role EXCEPT ![i] = IF won THEN "leader" ELSE "candidate"]
          /\ leaderSome' = [leaderSome EXCEPT ![i] = TRUE]
          /\ progVec' = [progVec EXCEPT ![i] = np.vec]
          /\ progCommitted' = [progCommitted EXCEPT ![i] = np.committed]
          /\ progQS' = [progQS EXCEPT ![i] = np.qs]
          /\ blankPending' = [blankPending EXCEPT ![i] = won]
          /\ matchedIndex' = [matchedIndex EXCEPT ![i] = [j \in Server |-> Nil]]
          /\ matchedTerm' = [matchedTerm EXCEPT ![i] = [j \in Server |-> 0]]
          /\ witnessIndex' = [witnessIndex EXCEPT ![i] = Nil]
          /\ witnessNodes' = [witnessNodes EXCEPT ![i] = {}]
          /\ witnessConfig' = [witnessConfig EXCEPT ![i] = effectiveConfig[i]]
          /\ witnessTerm' = [witnessTerm EXCEPT ![i] = 0]
    /\ UNCHANGED <<lastLog, logTerm, committed,
                   committedConfig, effectiveConfig,
                   committedMembershipIndex, committedMembershipTerm,
                   effectiveMembershipIndex, effectiveMembershipTerm,
                   messages, crashed>>

\* Engine::internal_handle_vote_req (voter; clears its Leader) +
\* handle_vote_resp (candidate; Leader::is_vote_granted over progress quorum set)
\* openraft/src/engine/engine_impl.rs:854-912, 167-224. UPDATE-MAP
\* update: Update!AffectedActions
GrantVote(candidate, voter) ==
    /\ candidate # voter
    /\ candidate \notin crashed
    /\ voter \notin crashed
    /\ role[candidate] = "candidate"
    /\ leaderSome[candidate]
    /\ voter \in Voters(progQS[candidate])
    /\ LogUpToDate(candidate, voter)
    /\ \/ currentTerm[voter] < currentTerm[candidate]
       \/ /\ currentTerm[voter] = currentTerm[candidate]
          /\ voteFor[voter] = candidate
    /\ LET grants == voteGranted[candidate] \union {voter}
           won == Quorum(progQS[candidate], grants)
       IN /\ currentTerm' = [currentTerm EXCEPT ![voter] = currentTerm[candidate]]
          /\ voteFor' = [voteFor EXCEPT ![voter] = candidate]
          /\ voteCommitted' = [voteCommitted EXCEPT
                                  ![candidate] = won,
                                  ![voter] = FALSE]
          /\ voteGranted' = [voteGranted EXCEPT ![candidate] = grants, ![voter] = {}]
          /\ role' = [role EXCEPT
                         ![candidate] = IF won THEN "leader" ELSE @,
                         ![voter] = IF voter \in Voters(effectiveConfig[voter])
                                    THEN "follower" ELSE "learner"]
          /\ blankPending' = [blankPending EXCEPT ![candidate] = won, ![voter] = FALSE]
          \* internal_handle_vote_req: "I'm no longer a leader" (engine_impl.rs:896-897)
          /\ leaderSome' = [leaderSome EXCEPT ![voter] = FALSE]
          /\ progVec' = [progVec EXCEPT ![voter] = <<>>]
          /\ progCommitted' = [progCommitted EXCEPT ![voter] = 0]
          /\ progQS' = [progQS EXCEPT ![voter] = NoQS]
    /\ UNCHANGED <<lastLog, logTerm, committed, matchedIndex, matchedTerm,
                   committedConfig, effectiveConfig,
                   committedMembershipIndex, committedMembershipTerm,
                   effectiveMembershipIndex, effectiveMembershipTerm,
                   messages, crashed, witnessIndex, witnessNodes,
                   witnessConfig, witnessTerm>>

\* Vote derives Ord over (term, node_id, committed): openraft/src/vote/vote.rs:7-13.
\* Node ids compare by their position in ServerOrder (ascending ids).
Rank(n) == CHOOSE k \in DOMAIN ServerOrder: ServerOrder[k] = n
VoteLess(t1, n1, c1, t2, n2, c2) ==
    \/ t1 < t2
    \/ t1 = t2 /\ Rank(n1) < Rank(n2)
    \/ t1 = t2 /\ n1 = n2 /\ ~c1 /\ c2

\* Engine::handle_vote_resp, candidate side only (trace form; MC composes it
\* into GrantVote). UPDATE-MAP
\* code: openraft/src/engine/engine_impl.rs:167-224 (is_vote_granted over the
\*       progress quorum set, leader.rs:49-53; Leader cleared on higher vote)
\* update: Update!AffectedActions (MCGrantVote)
HandleVoteResp(i, target, rt, rn, rc, granted) ==
    /\ i \notin crashed
    /\ IF ~leaderSome[i]
       THEN UNCHANGED vars                                       \* engine_impl.rs:177-180
       ELSE IF VoteLess(rt, rn, rc, currentTerm[i], voteFor[i], voteCommitted[i])
       THEN UNCHANGED vars                                       \* engine_impl.rs:183-185
       ELSE IF VoteLess(currentTerm[i], voteFor[i], voteCommitted[i], rt, rn, rc)
       THEN /\ role' = [role EXCEPT ![i] = IF i \in Voters(effectiveConfig[i])
                                             THEN "follower" ELSE "learner"]   \* engine_impl.rs:192-197
            /\ currentTerm' = [currentTerm EXCEPT ![i] = rt]     \* engine_impl.rs:199
            /\ voteFor' = [voteFor EXCEPT ![i] = rn]
            /\ voteCommitted' = [voteCommitted EXCEPT ![i] = rc]
            /\ ResetProgress(i)                                  \* engine_impl.rs:200
            /\ voteGranted' = [voteGranted EXCEPT ![i] = {}]
            /\ blankPending' = [blankPending EXCEPT ![i] = FALSE]
            /\ UNCHANGED <<lastLog, logTerm, committed, matchedIndex, matchedTerm,
                           committedConfig, effectiveConfig,
                           committedMembershipIndex, committedMembershipTerm,
                           effectiveMembershipIndex, effectiveMembershipTerm,
                           messages, crashed, witnessIndex, witnessNodes,
                           witnessConfig, witnessTerm>>
       ELSE IF ~granted
       THEN UNCHANGED vars
       ELSE LET grants == voteGranted[i] \union {target}         \* engine_impl.rs:205-206
                won == Quorum(progQS[i], grants)                 \* engine_impl.rs:208
            IN /\ voteGranted' = [voteGranted EXCEPT ![i] = grants]
               /\ voteCommitted' = [voteCommitted EXCEPT ![i] = IF won THEN TRUE ELSE @]
               /\ role' = [role EXCEPT ![i] = IF won THEN "leader" ELSE @]
               /\ blankPending' = [blankPending EXCEPT ![i] = IF won THEN TRUE ELSE @]
               /\ UNCHANGED <<currentTerm, voteFor, lastLog, logTerm, committed,
                              matchedIndex, matchedTerm,
                              committedConfig, effectiveConfig,
                              committedMembershipIndex, committedMembershipTerm,
                              effectiveMembershipIndex, effectiveMembershipTerm,
                              messages, crashed, witnessIndex, witnessNodes,
                              witnessConfig, witnessTerm,
                              leaderSome, progVec, progCommitted, progQS>>

AppendTerms(i, oldLast, count) ==
    [k \in 0..MaxIndex |->
        IF k > oldLast /\ k <= oldLast + count
        THEN currentTerm[i]
        ELSE logTerm[i][k]]

\* Engine::leader_append_entries. UPDATE-MAP
\* code: openraft/src/engine/engine_impl.rs:234-290 (fast_commit removed;
\*       update_progress(self) before a membership entry, then
\*       update_effective_membership, then update_progress(self, last))
\* update: Update!AffectedActions
LeaderAppendEntries(i, count, membershipPosition, newConfig) ==
    /\ i \notin crashed
    /\ count \in 1..(MaxIndex + 1)
    /\ lastLog[i] + count <= MaxIndex
    /\ \/ membershipPosition = Nil
       \/ /\ membershipPosition \in 1..count
          /\ ConfigOK(newConfig)
    /\ LET newLast == lastLog[i] + count
           t == currentTerm[i]
           newLog == AppendTerms(i, lastLog[i], count)         \* assign_log_ids + extend: engine_impl.rs:242-243
           hasM == membershipPosition # Nil
           mIdx == lastLog[i] + membershipPosition
           L0 == Local(i)
           \* engine_impl.rs:274-279: progress for entries before the membership entry
           L1 == IF hasM /\ mIdx > 0
                 THEN EngineUpdateProgress(L0, i, LV(newLog[mIdx - 1], mIdx - 1), t)
                 ELSE L0
           \* engine_impl.rs:281-282: the commit condition changes from this entry
           L2 == IF hasM THEN EngineUpdateEffective(i, L1, mIdx, t, newConfig) ELSE L1
           \* engine_impl.rs:285-287
           L3 == EngineUpdateProgress(L2, i, LV(t, newLast), t)
       IN /\ lastLog' = [lastLog EXCEPT ![i] = newLast]
          /\ logTerm' = [logTerm EXCEPT ![i] = newLog]
          /\ matchedIndex' = [matchedIndex EXCEPT ![i][i] = newLast]
          /\ matchedTerm' = [matchedTerm EXCEPT ![i][i] = t]
          /\ AssignLocal(i, L3)
    /\ UNCHANGED <<currentTerm, voteFor, voteCommitted, voteGranted,
                   leaderSome, messages, crashed>>

\* LeaderState::run writes the blank entry of the new term before the leader
\* loop handles replication events: openraft/src/core/leader_state.rs:72-97
LeaderWriteBlank(i) ==
    /\ role[i] = "leader"
    /\ voteCommitted[i]
    /\ blankPending[i]
    /\ LeaderAppendEntries(i, 1, Nil, effectiveConfig[i])
    /\ blankPending' = [blankPending EXCEPT ![i] = FALSE]

\* Public client writes reach this internal action only in established leader state:
\* openraft/src/core/leader_state.rs:141-167
ClientAppend(i) ==
    /\ role[i] = "leader"
    /\ voteCommitted[i]
    /\ ~blankPending[i]
    /\ LeaderAppendEntries(i, 1, Nil, effectiveConfig[i])
    /\ UNCHANGED blankPending

\* Membership::next_safe / Joint::find_coherent: openraft/src/membership/
\* membership.rs:288-312, quorum/coherent_impl.rs:62-74. The last child of a
\* joint config is not represented in the set encoding, so either child is
\* admitted (over-approximation, bounded by AllowedConfigs in MC).
NextSafeChoices(cur, goal) ==
    IF goal \in cur THEN {{goal}}
    ELSE IF Cardinality(cur) = 1 THEN {cur \union {goal}}
    ELSE {{x, goal} : x \in cur}

Goals == {g \in UNION AllowedConfigs: {g} \in AllowedConfigs}

\* LeaderState::change_membership rejects a second outstanding change and
\* writes next_safe(goal): openraft/src/core/admin.rs:135-199
ProposeMembership(i, goal) ==
    /\ role[i] = "leader"
    /\ voteCommitted[i]
    /\ ~blankPending[i]
    /\ effectiveMembershipIndex[i] <= committed[i]
    /\ goal \in Goals
    /\ \E cfg \in NextSafeChoices(effectiveConfig[i], goal) \intersect AllowedConfigs:
          LeaderAppendEntries(i, 1, 1, cfg)
    /\ UNCHANGED blankPending

\* ReplicationCore builds a semantic AppendEntries request after loading a
\* consecutive range: openraft/src/replication/mod.rs:264-361
SendAppendEntries(i, j) ==
    /\ i # j
    /\ i \notin crashed
    /\ j \notin crashed
    /\ role[i] = "leader"
    /\ voteCommitted[i]
    /\ LET p == matchedIndex[i][j]
           lt == IF lastLog[i] = Nil THEN 0 ELSE logTerm[i][lastLog[i]]
           msg == [type |-> "append", from |-> i, to |-> j,
                   term |-> currentTerm[i], prev |-> p, last |-> lastLog[i],
                   lastTerm |-> lt, leaderCommit |-> committed[i], ok |-> TRUE]
       IN messages' = messages \union {msg}
    /\ UNCHANGED <<currentTerm, voteFor, voteCommitted, role, voteGranted,
                   lastLog, logTerm, committed, matchedIndex, matchedTerm,
                   committedConfig, effectiveConfig,
                   committedMembershipIndex, committedMembershipTerm,
                   effectiveMembershipIndex, effectiveMembershipTerm,
                   crashed, witnessIndex, witnessNodes, witnessConfig, witnessTerm,
                   leaderSome, progVec, progCommitted, progQS, blankPending>>

CopyLeaderLog(m) ==
    [k \in 0..MaxIndex |->
        IF k <= m.last THEN logTerm[m.from][k] ELSE logTerm[m.to][k]]

\* Engine::handle_append_entries_req accepts a matching prefix and applies the
\* follower commit cap: openraft/src/engine/engine_impl.rs:292-385. UPDATE-MAP
\* update: Update!AffectedActions (internal_handle_vote_req clears the Leader;
\*         follower_commit_entries now promotes membership only via
\*         RaftState::update_committed, i.e. only when committed increases)
DeliverAppendEntries(m) ==
    /\ m \in messages
    /\ m.type = "append"
    /\ m.to \notin crashed
    /\ m.term >= currentTerm[m.to]
    /\ IF m.prev = Nil
       THEN TRUE
       ELSE IF m.prev <= committed[m.to]
            THEN TRUE
            ELSE /\ m.prev <= lastLog[m.to]
                 /\ logTerm[m.to][m.prev] = logTerm[m.from][m.prev]
    /\ LET newCommit == IMax(committed[m.to], IMin(m.leaderCommit, m.last))
           copyMembership == effectiveMembershipIndex[m.from] <= m.last
           newEffectiveIndex == IF copyMembership
                                THEN effectiveMembershipIndex[m.from]
                                ELSE effectiveMembershipIndex[m.to]
           newEffectiveConfig == IF copyMembership
                                 THEN effectiveConfig[m.from]
                                 ELSE effectiveConfig[m.to]
           advanced == newCommit > committed[m.to]          \* raft_state.rs:123
           promoteMembership == advanced /\ newCommit >= newEffectiveIndex
           ack == [type |-> "ack", from |-> m.to, to |-> m.from,
                   term |-> m.term, prev |-> m.prev, last |-> m.last,
                   lastTerm |-> m.lastTerm, leaderCommit |-> newCommit, ok |-> TRUE]
       IN /\ currentTerm' = [currentTerm EXCEPT ![m.to] = m.term]
          /\ voteFor' = [voteFor EXCEPT ![m.to] = m.from]
          /\ voteCommitted' = [voteCommitted EXCEPT ![m.to] = TRUE]
          /\ role' = [role EXCEPT
                         ![m.to] = IF m.to \in Voters(newEffectiveConfig)
                                  THEN "follower" ELSE "learner"]
          /\ lastLog' = [lastLog EXCEPT ![m.to] = IMax(@, m.last)]
          /\ logTerm' = [logTerm EXCEPT ![m.to] = CopyLeaderLog(m)]
          /\ committed' = [committed EXCEPT ![m.to] = newCommit]
          /\ effectiveConfig' = [effectiveConfig EXCEPT ![m.to] = newEffectiveConfig]
          /\ effectiveMembershipIndex' = [effectiveMembershipIndex EXCEPT
                                             ![m.to] = newEffectiveIndex]
          /\ effectiveMembershipTerm' = [effectiveMembershipTerm EXCEPT
                                            ![m.to] = IF copyMembership
                                                  THEN effectiveMembershipTerm[m.from] ELSE @]
          /\ committedConfig' = [committedConfig EXCEPT
                                    ![m.to] = IF promoteMembership
                                              THEN newEffectiveConfig ELSE @]
          /\ committedMembershipIndex' = [committedMembershipIndex EXCEPT
                                             ![m.to] = IF promoteMembership
                                                       THEN newEffectiveIndex ELSE @]
          /\ committedMembershipTerm' = [committedMembershipTerm EXCEPT
                                            ![m.to] = IF promoteMembership
                                                      THEN effectiveMembershipTerm'[m.to] ELSE @]
          /\ messages' = (messages \ {m}) \union {ack}
          /\ ResetProgress(m.to)                             \* engine_impl.rs:896-897
          /\ blankPending' = [blankPending EXCEPT ![m.to] = FALSE]
          /\ voteGranted' = [voteGranted EXCEPT ![m.to] = {}]
    /\ UNCHANGED <<matchedIndex, matchedTerm, crashed,
                   witnessIndex, witnessNodes, witnessConfig, witnessTerm>>

\* A conflicting prev-log causes truncation at an existing conflict and a
\* negative response; binary-search cursor details stay internal:
\* openraft/src/engine/engine_impl.rs:323-331
\* openraft/src/replication/mod.rs:431-442
RejectAppendConflict(m) ==
    /\ m \in messages
    /\ m.type = "append"
    /\ m.to \notin crashed
    /\ m.term >= currentTerm[m.to]
    /\ IF m.prev = Nil
       THEN FALSE
       ELSE /\ m.prev > committed[m.to]
            /\ IF m.prev > lastLog[m.to]
               THEN TRUE
               ELSE logTerm[m.to][m.prev] # logTerm[m.from][m.prev]
    /\ LET exists == m.prev <= lastLog[m.to]
           ack == [type |-> "ack", from |-> m.to, to |-> m.from,
                   term |-> m.term, prev |-> m.prev, last |-> m.prev,
                   lastTerm |-> 0, leaderCommit |-> committed[m.to], ok |-> FALSE]
       IN /\ currentTerm' = [currentTerm EXCEPT ![m.to] = m.term]
          /\ voteFor' = [voteFor EXCEPT ![m.to] = m.from]
          /\ voteCommitted' = [voteCommitted EXCEPT ![m.to] = TRUE]
          /\ role' = [role EXCEPT
                         ![m.to] = IF m.to \in Voters(effectiveConfig[m.to])
                                  THEN "follower" ELSE "learner"]
          /\ lastLog' = [lastLog EXCEPT ![m.to] = IF exists THEN m.prev - 1 ELSE @]
          /\ logTerm' = [logTerm EXCEPT
                            ![m.to] = IF exists
                                     THEN [k \in 0..MaxIndex |->
                                             IF k >= m.prev THEN 0 ELSE logTerm[m.to][k]]
                                     ELSE @]
          /\ messages' = (messages \ {m}) \union {ack}
          /\ ResetProgress(m.to)                             \* engine_impl.rs:896-897
          /\ blankPending' = [blankPending EXCEPT ![m.to] = FALSE]
          /\ voteGranted' = [voteGranted EXCEPT ![m.to] = {}]
    /\ UNCHANGED <<committed, matchedIndex, matchedTerm,
                   committedConfig, effectiveConfig,
                   committedMembershipIndex, committedMembershipTerm,
                   effectiveMembershipIndex, effectiveMembershipTerm,
                   crashed, witnessIndex, witnessNodes, witnessConfig, witnessTerm>>

\* LeaderState::handle_update_matched: record the replication state's matched
\* value, return early when it is not above the leader's committed, otherwise
\* Engine::update_progress(target, matched) and run the resulting commands.
\* UPDATE-MAP
\* code: openraft/src/core/replication.rs:96-141
\* update: Update!AffectedActions, Update!ProgressWithinReplication
HandleUpdateMatched(m) ==
    /\ m \in messages
    /\ m.type = "ack"
    /\ m.ok
    /\ m.to \notin crashed
    /\ role[m.to] = "leader"
    /\ ~blankPending[m.to]
    /\ currentTerm[m.to] = m.term
    /\ m.last >= matchedIndex[m.to][m.from]                   \* replication.rs:124 assert
    /\ LET i == m.to
           L0 == Local(i)
           skip == m.last <= committed[i]                       \* replication.rs:134-136
           L1 == IF skip
                 THEN L0
                 ELSE EngineUpdateProgress(L0, m.from, LV(m.lastTerm, m.last),
                                           currentTerm[i])     \* replication.rs:138-139
       IN /\ matchedIndex' = [matchedIndex EXCEPT ![i][m.from] = m.last]   \* replication.rs:126
          /\ matchedTerm' = [matchedTerm EXCEPT ![i][m.from] = m.lastTerm]
          /\ messages' = messages \ {m}
          /\ AssignLocal(i, L1)
    /\ UNCHANGED <<currentTerm, voteFor, voteCommitted, voteGranted,
                   lastLog, logTerm, crashed, leaderSome, blankPending>>

\* Trace-only direct forms of the changed Engine helpers (unit-test fixtures
\* call them directly). Same transformers as the protocol actions above.
UpdateProgressAction(i, target, value) ==
    /\ i \notin crashed
    /\ UNCHANGED <<currentTerm, voteFor, voteCommitted, voteGranted,
                   lastLog, logTerm, matchedIndex, matchedTerm,
                   messages, crashed, leaderSome, blankPending>>
    /\ AssignLocal(i, EngineUpdateProgress(Local(i), target, value, currentTerm[i]))

UpdateEffectiveMembershipAction(i, idx, t, cfg) ==
    /\ i \notin crashed
    /\ ConfigOK(cfg)
    /\ UNCHANGED <<currentTerm, voteFor, voteCommitted, voteGranted,
                   lastLog, logTerm, matchedIndex, matchedTerm,
                   messages, crashed, leaderSome, blankPending>>
    /\ AssignLocal(i, EngineUpdateEffective(i, Local(i), idx, t, cfg))

\* Standalone VecProgress operations (progress::t unit tests). The holder
\* node's progress slots are used as storage; nothing else changes.
ProgressUpdateValue(i, target, value) ==
    LET p2 == PUpdate([vec |-> progVec[i], committed |-> progCommitted[i], qs |-> progQS[i]],
                      target, value)
    IN /\ progVec' = [progVec EXCEPT ![i] = p2.vec]
       /\ progCommitted' = [progCommitted EXCEPT ![i] = p2.committed]
       /\ UNCHANGED <<currentTerm, voteFor, voteCommitted, role, voteGranted,
                      lastLog, logTerm, committed, matchedIndex, matchedTerm,
                      committedConfig, effectiveConfig,
                      committedMembershipIndex, committedMembershipTerm,
                      effectiveMembershipIndex, effectiveMembershipTerm,
                      messages, crashed, witnessIndex, witnessNodes,
                      witnessConfig, witnessTerm, leaderSome, progQS, blankPending>>

ProgressUpgradeAction(i, newQS) ==
    /\ ConfigOK(newQS)
    /\ LET p2 == PUpgrade([vec |-> progVec[i], committed |-> progCommitted[i], qs |-> progQS[i]],
                          newQS)
       IN /\ progVec' = [progVec EXCEPT ![i] = p2.vec]
          /\ progCommitted' = [progCommitted EXCEPT ![i] = p2.committed]
          /\ progQS' = [progQS EXCEPT ![i] = p2.qs]
    /\ UNCHANGED <<currentTerm, voteFor, voteCommitted, role, voteGranted,
                   lastLog, logTerm, committed, matchedIndex, matchedTerm,
                   committedConfig, effectiveConfig,
                   committedMembershipIndex, committedMembershipTerm,
                   effectiveMembershipIndex, effectiveMembershipTerm,
                   messages, crashed, witnessIndex, witnessNodes,
                   witnessConfig, witnessTerm, leaderSome, blankPending>>

DiscardNegativeAck(m) ==
    /\ m \in messages
    /\ m.type = "ack"
    /\ ~m.ok
    /\ messages' = messages \ {m}
    /\ UNCHANGED <<currentTerm, voteFor, voteCommitted, role, voteGranted,
                   lastLog, logTerm, committed, matchedIndex, matchedTerm,
                   committedConfig, effectiveConfig,
                   committedMembershipIndex, committedMembershipTerm,
                   effectiveMembershipIndex, effectiveMembershipTerm,
                   crashed, witnessIndex, witnessNodes, witnessConfig, witnessTerm,
                   leaderSome, progVec, progCommitted, progQS, blankPending>>

\* Follower commit helper used by trace validation directly. UPDATE-MAP
\* code: openraft/src/engine/engine_impl.rs:363-386 (update_committed)
\* update: Update!AffectedActions
FollowerCommitEntries(i, leaderCommitTerm, leaderCommit,
                      prevLogTerm, prevLog, lastEntryTerm, lastEntry) ==
    /\ i \notin crashed
    /\ leaderCommitTerm \in Term
    /\ leaderCommit \in Index
    /\ prevLogTerm \in Term
    /\ prevLog \in Index
    /\ lastEntryTerm \in Term
    /\ lastEntry \in Index
    /\ LET lastIsBoundary == \/ lastEntryTerm > prevLogTerm
                              \/ /\ lastEntryTerm = prevLogTerm
                                 /\ lastEntry >= prevLog
           localBoundary == IF lastIsBoundary THEN lastEntry ELSE prevLog
           localBoundaryTerm == IF lastIsBoundary THEN lastEntryTerm ELSE prevLogTerm
           leaderIsMinimum == \/ leaderCommitTerm < localBoundaryTerm
                              \/ /\ leaderCommitTerm = localBoundaryTerm
                                 /\ leaderCommit <= localBoundary
           cappedCommit == IF leaderIsMinimum THEN leaderCommit ELSE localBoundary
           nextCommit == IMax(committed[i], cappedCommit)
           promote == nextCommit > committed[i] /\ nextCommit >= effectiveMembershipIndex[i]
       IN /\ committed' = [committed EXCEPT ![i] = nextCommit]
          /\ committedConfig' = [committedConfig EXCEPT
                                    ![i] = IF promote THEN effectiveConfig[i] ELSE @]
          /\ committedMembershipIndex' = [committedMembershipIndex EXCEPT
                                             ![i] = IF promote
                                                     THEN effectiveMembershipIndex[i] ELSE @]
          /\ committedMembershipTerm' = [committedMembershipTerm EXCEPT
                                            ![i] = IF promote
                                                    THEN effectiveMembershipTerm[i] ELSE @]
    /\ UNCHANGED <<currentTerm, voteFor, voteCommitted, role, voteGranted,
                   lastLog, logTerm, matchedIndex, matchedTerm, effectiveConfig,
                   effectiveMembershipIndex, effectiveMembershipTerm,
                   messages, crashed, witnessIndex, witnessNodes,
                   witnessConfig, witnessTerm,
                   leaderSome, progVec, progCommitted, progQS, blankPending>>

\* Engine::update_committed_membership compares committed log ids by term/index
\* and effective membership by index: openraft/src/engine/engine_impl.rs:556-589
UpdateCommittedMembership(i, newTerm, newIndex, newConfig) ==
    /\ i \notin crashed
    /\ newTerm \in Term
    /\ newIndex \in Index
    /\ ConfigOK(newConfig)
    /\ LET committedNewer == \/ newTerm > committedMembershipTerm[i]
                                \/ /\ newTerm = committedMembershipTerm[i]
                                   /\ newIndex > committedMembershipIndex[i]
           replaceEffective == effectiveMembershipIndex[i] <= newIndex
       IN /\ committedConfig' = [committedConfig EXCEPT
                                    ![i] = IF committedNewer THEN newConfig ELSE @]
          /\ committedMembershipIndex' = [committedMembershipIndex EXCEPT
                                             ![i] = IF committedNewer THEN newIndex ELSE @]
          /\ committedMembershipTerm' = [committedMembershipTerm EXCEPT
                                            ![i] = IF committedNewer THEN newTerm ELSE @]
          /\ effectiveConfig' = [effectiveConfig EXCEPT
                                    ![i] = IF replaceEffective THEN newConfig ELSE @]
          /\ effectiveMembershipIndex' = [effectiveMembershipIndex EXCEPT
                                             ![i] = IF replaceEffective THEN newIndex ELSE @]
          /\ effectiveMembershipTerm' = [effectiveMembershipTerm EXCEPT
                                            ![i] = IF replaceEffective THEN newTerm ELSE @]
          \* update_server_state_if_changed(calc before): engine_impl.rs:753-760
          /\ LET pre == CalcServerState(i, effectiveConfig[i], leaderSome[i])
                 post == CalcServerState(i, effectiveConfig'[i], leaderSome[i])
             IN role' = [role EXCEPT ![i] = IF pre # post THEN post ELSE @]
    /\ UNCHANGED <<currentTerm, voteFor, voteCommitted, voteGranted,
                   lastLog, logTerm, committed, matchedIndex, matchedTerm,
                   messages, crashed, witnessIndex, witnessNodes,
                   witnessConfig, witnessTerm,
                   leaderSome, progVec, progCommitted, progQS, blankPending>>

\* Message loss occurs outside Engine state. It is bounded in MC only.
LoseMessage(m) ==
    /\ m \in messages
    /\ messages' = messages \ {m}
    /\ UNCHANGED <<currentTerm, voteFor, voteCommitted, role, voteGranted,
                   lastLog, logTerm, committed, matchedIndex, matchedTerm,
                   committedConfig, effectiveConfig,
                   committedMembershipIndex, committedMembershipTerm,
                   effectiveMembershipIndex, effectiveMembershipTerm,
                   crashed, witnessIndex, witnessNodes, witnessConfig, witnessTerm,
                   leaderSome, progVec, progCommitted, progQS, blankPending>>

\* Crash/restart preserves vote/log/membership and clears volatile leader data;
\* a restarted Engine has no Leader (RaftState::leader is None):
\* openraft/src/core/raft_core.rs:181-205
Crash(i) ==
    /\ i \notin crashed
    /\ crashed' = crashed \union {i}
    /\ role' = [role EXCEPT ![i] = IF i \in Voters(effectiveConfig[i])
                                     THEN "follower" ELSE "learner"]
    /\ committed' = [committed EXCEPT ![i] = Nil]
    /\ voteGranted' = [voteGranted EXCEPT ![i] = {}]
    /\ matchedIndex' = [matchedIndex EXCEPT ![i] = [j \in Server |-> Nil]]
    /\ matchedTerm' = [matchedTerm EXCEPT ![i] = [j \in Server |-> 0]]
    /\ witnessIndex' = [witnessIndex EXCEPT ![i] = Nil]
    /\ witnessNodes' = [witnessNodes EXCEPT ![i] = {}]
    /\ witnessConfig' = [witnessConfig EXCEPT ![i] = effectiveConfig[i]]
    /\ witnessTerm' = [witnessTerm EXCEPT ![i] = 0]
    /\ ResetProgress(i)
    /\ blankPending' = [blankPending EXCEPT ![i] = FALSE]
    /\ UNCHANGED <<currentTerm, voteFor, voteCommitted, lastLog, logTerm,
                   committedConfig, effectiveConfig,
                   committedMembershipIndex, committedMembershipTerm,
                   effectiveMembershipIndex, effectiveMembershipTerm, messages>>

Recover(i) ==
    /\ i \in crashed
    /\ crashed' = crashed \ {i}
    /\ role' = [role EXCEPT ![i] = IF i \in Voters(effectiveConfig[i])
                                     THEN "follower" ELSE "learner"]
    /\ UNCHANGED <<currentTerm, voteFor, voteCommitted, voteGranted,
                   lastLog, logTerm, committed, matchedIndex, matchedTerm,
                   committedConfig, effectiveConfig,
                   committedMembershipIndex, committedMembershipTerm,
                   effectiveMembershipIndex, effectiveMembershipTerm,
                   messages, witnessIndex, witnessNodes, witnessConfig, witnessTerm,
                   leaderSome, progVec, progCommitted, progQS, blankPending>>

Next ==
    \/ \E i \in Server: StartElection(i)
    \/ \E i, j \in Server: GrantVote(i, j)
    \/ \E i \in Server: LeaderWriteBlank(i)
    \/ \E i \in Server: ClientAppend(i)
    \/ \E i \in Server, g \in Goals: ProposeMembership(i, g)
    \/ \E i, j \in Server: SendAppendEntries(i, j)
    \/ \E m \in messages: DeliverAppendEntries(m)
    \/ \E m \in messages: RejectAppendConflict(m)
    \/ \E m \in messages: HandleUpdateMatched(m)
    \/ \E m \in messages: DiscardNegativeAck(m)
    \/ \E m \in messages: LoseMessage(m)
    \/ \E i \in Server: Crash(i)
    \/ \E i \in Server: Recover(i)

MessageUniverse ==
    [type         : {"append", "ack"},
     from         : Server,
     to           : Server,
     term         : Term,
     prev         : Index,
     last         : Index,
     lastTerm     : Term,
     leaderCommit : Index,
     ok           : BOOLEAN]

ProgressVecOK(v) ==
    /\ DOMAIN v = 1..Len(v)
    /\ \A k \in DOMAIN v: v[k].id \in Server /\ v[k].val \in Nat

TypeOK ==
    /\ currentTerm \in [Server -> Term]
    /\ voteFor \in [Server -> Server]
    /\ voteCommitted \in [Server -> BOOLEAN]
    /\ role \in [Server -> Role]
    /\ voteGranted \in [Server -> SUBSET Server]
    /\ lastLog \in [Server -> Index]
    /\ logTerm \in [Server -> [0..MaxIndex -> Term]]
    /\ committed \in [Server -> Index]
    /\ matchedIndex \in [Server -> [Server -> Index]]
    /\ matchedTerm \in [Server -> [Server -> Term]]
    /\ committedConfig \in [Server -> SUBSET (SUBSET Server)]
    /\ effectiveConfig \in [Server -> SUBSET (SUBSET Server)]
    /\ \A i \in Server: ConfigOK(committedConfig[i]) /\ ConfigOK(effectiveConfig[i])
    /\ committedMembershipIndex \in [Server -> Index]
    /\ committedMembershipTerm \in [Server -> Term]
    /\ effectiveMembershipIndex \in [Server -> Index]
    /\ effectiveMembershipTerm \in [Server -> Term]
    /\ messages \in SUBSET MessageUniverse
    /\ crashed \in SUBSET Server
    /\ witnessIndex \in [Server -> Index]
    /\ witnessNodes \in [Server -> SUBSET Server]
    /\ witnessConfig \in [Server -> SUBSET (SUBSET Server)]
    /\ witnessTerm \in [Server -> Term]
    /\ leaderSome \in [Server -> BOOLEAN]
    /\ progCommitted \in [Server -> Nat]
    /\ progQS \in [Server -> SUBSET (SUBSET Server)]
    /\ blankPending \in [Server -> BOOLEAN]
    /\ \A i \in Server:
          /\ ProgressVecOK(progVec[i])
          /\ leaderSome[i] => ConfigOK(progQS[i])
          /\ ~leaderSome[i] => progVec[i] = <<>> /\ progCommitted[i] = 0 /\ progQS[i] = NoQS

ElectionSafety ==
    \A i, j \in Server:
        /\ role[i] = "leader"
        /\ role[j] = "leader"
        /\ currentTerm[i] = currentTerm[j]
        => voteFor[i] = voteFor[j]

ActiveLeaderHasCommittedVote ==
    \A i \in Server: role[i] = "leader" => voteCommitted[i]

CommitWithinLocalLog ==
    \A i \in Server: committed[i] <= lastLog[i]

CommittedLogAgreement ==
    \A i, j \in Server:
      \A idx \in 0..IMin(committed[i], committed[j]):
          logTerm[i][idx] = logTerm[j][idx]

\* Every leader commit decision is backed by the leader's actual replication
\* facts: the nodes whose matched log reaches the committed entry form a quorum
\* of the quorum set used for that decision.
CommitWitnessSound ==
    \A i \in Server:
        witnessIndex[i] = Nil
        \/ /\ witnessIndex[i] <= committed[i]
           /\ witnessIndex[i] <= lastLog[i]
           /\ witnessTerm[i] = logTerm[i][witnessIndex[i]]
           /\ Quorum(witnessConfig[i], witnessNodes[i])
           /\ \A j \in witnessNodes[i]:
                 matchedIndex[i][j] >= witnessIndex[i]
                 /\ matchedTerm[i][j] = witnessTerm[i]

MembershipOrder ==
    \A i \in Server:
        committedMembershipIndex[i] <= effectiveMembershipIndex[i]

OneOutstandingMembership ==
    \A i \in Server:
        effectiveMembershipIndex[i] > committed[i]
        => committedMembershipIndex[i] < effectiveMembershipIndex[i]

ReachLeader == \E i \in Server: role[i] = "leader"
ReachCommitWitness == \E i \in Server: witnessIndex[i] # Nil
ReachOutstandingMembership ==
    \E i \in Server: effectiveMembershipIndex[i] > committedMembershipIndex[i]

=============================================================================
