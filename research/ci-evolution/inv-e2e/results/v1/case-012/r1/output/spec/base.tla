------------------------------ MODULE base ------------------------------
\* OpenRaft reference model, updated revision (synthetic commit `update`).
\* Prior V0 suite: /work/previous/.specula-output/spec/base.tla (exact-old).
\* Source line references below are to the UPDATED tree unless marked "old".
EXTENDS Naturals, Integers, FiniteSets, Sequences, TLC

\* ServerOrder: the node-id order (`NodeId: Ord`). It is behaviour-relevant in the
\* updated revision because VecProgress builds its vector from the BTreeSet
\* order of `QuorumSet::ids()` (progress/mod.rs:81-89, quorum/joint.rs:89-95).
\* UPDATE-MAP
\* code: openraft/src/progress/mod.rs:81-89; openraft/src/quorum/joint.rs:89-95
\* update: Update!AffectedActions (all progress-driven commit paths)
CONSTANTS Server, MaxTerm, MaxIndex, AllowedConfigs, ServerOrder

Nil == -1

ASSUME /\ Server # {}
       /\ MaxTerm \in Nat \ {0}
       /\ MaxIndex \in Nat
       /\ Len(ServerOrder) = Cardinality(Server)
       /\ {ServerOrder[k] : k \in 1..Len(ServerOrder)} = Server

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

\* Membership::is_quorum / Joint::is_quorum (unchanged by the update):
\* openraft/src/quorum/quorum_set_impl.rs:5-22
\* openraft/src/quorum/joint.rs:73-87
Quorum(cfg, granted) ==
    /\ ConfigOK(cfg)
    /\ \A group \in cfg:
          2 * Cardinality(group \intersect granted) > Cardinality(group)

\* ---------------------------------------------------------------------------
\* Log ids and VecProgress (UPDATED REVISION)
\* ---------------------------------------------------------------------------
\* Option<LogId> is <<term, index>>; None is <<0, Nil>>.  LogId derives Ord over
\* (leader_id, index) (raft_types.rs:11-17).  The node part of leader_id is
\* determined by the term in this model (one self-voted leader per term, see
\* ElectionSafety), so the order is lexicographic on <<term, index>>.
LogIdT == Term \X Index
NoLog == <<0, Nil>>
LogLT(a, b) == \/ a[1] < b[1]
               \/ /\ a[1] = b[1]
                  /\ a[2] < b[2]
LogLE(a, b) == a = b \/ LogLT(a, b)

SeqElems(s) == {s[k] : k \in 1..Len(s)}
SortedIds(S) == SelectSeq(ServerOrder, LAMBDA x: x \in S)
PositionOf(s, x) ==
    IF x \in SeqElems(s) THEN CHOOSE k \in 1..Len(s): s[k] = x ELSE 0

\* A VecProgress value.  `order` is the real vector order; `val` holds the value
\* of every id present in `order` (other entries are NoLog and unused);
\* `committed` is VecProgress.committed (NOT RaftState.committed).
\* openraft/src/progress/mod.rs:40-62
ProgressRec(p) ==
    /\ p.cfg \in SUBSET (SUBSET Server)
    /\ p.order \in [1..Len(p.order) -> Server]
    /\ SeqElems(p.order) = Voters(p.cfg)
    /\ Len(p.order) = Cardinality(Voters(p.cfg))
    /\ p.val \in [Server -> LogIdT]
    /\ p.committed \in LogIdT

\* Absent Engine leader state (`RaftState.leader == None`).  Canonical value.
NoProgress == [cfg |-> {}, order |-> <<>>,
               val |-> [j \in Server |-> NoLog], committed |-> NoLog]

\* VecProgress::new: vector = quorum_set.ids() (sorted), all values default.
\* openraft/src/progress/mod.rs:81-89
\* `d` is V::default(): None for the Engine's Option<LogId>; 0 for u64 test values.
NewProgressD(cfg, d) ==
    [cfg |-> cfg, order |-> SortedIds(Voters(cfg)),
     val |-> [j \in Server |-> IF j \in Voters(cfg) THEN d ELSE NoLog],
     committed |-> d]
NewProgress(cfg) == NewProgressD(cfg, NoLog)

\* VecProgress::move_up: move the element at `pos` up past the contiguous run
\* of strictly smaller predecessors; it stops below the first element >= it.
\* openraft/src/progress/mod.rs:105-117
MoveUpPos(ord, val, pos) ==
    LET v == val[ord[pos]]
        blockers == {q \in 1..(pos - 1) : ~LogLT(val[ord[q]], v)}
    IN IF blockers = {} THEN 1
       ELSE (CHOOSE q \in blockers: \A r \in blockers: r <= q) + 1

MoveTo(ord, from, to) ==
    SubSeq(ord, 1, to - 1) \o <<ord[from]>> \o SubSeq(ord, to, from - 1)
        \o SubSeq(ord, from + 1, Len(ord))

\* The recompute loop of VecProgress::update: from the moved element downwards,
\* stop at the first value <= committed, or take the first prefix
\* vector[0..=i] that is a quorum.  The prefix is ASSUMED to be "ids with value
\* >= vector[i]" (comment at progress/mod.rs:195); it is only that when the
\* vector is sorted.
\* openraft/src/progress/mod.rs:187-202
RECURSIVE RecalcCommitted(_, _, _, _, _)
RecalcCommitted(ord, val, cfg, c, i) ==
    IF i > Len(ord) THEN c
    ELSE IF LogLE(val[ord[i]], c) THEN c
    ELSE IF Quorum(cfg, {ord[k] : k \in 1..i}) THEN val[ord[i]]
    ELSE RecalcCommitted(ord, val, cfg, c, i + 1)

\* VecProgress::update(id, value).  Faithful to the exact control flow:
\*  - unknown id: unchanged (progress/mod.rs:166-171, changed by the update);
\*  - equal value: unchanged (progress/mod.rs:176-178);
\*  - value stored IN PLACE (progress/mod.rs:182);
\*  - only when prev <= committed < value: move_up + recompute
\*    (progress/mod.rs:184-203).  When prev > committed the element is NOT
\*    moved, which can leave larger values below smaller ones.
\* (debug_assert!(value > prev) at progress/mod.rs:180 is release-inert; the
\*  model stores the value as release builds do.)
\* UPDATE-MAP
\* code: openraft/src/progress/mod.rs:163-207 (now on the production commit path)
\* update: Update!AffectedActions, Update!ProgressCommittedSupported
VecUpdate(p, id, v) ==
    LET pos == PositionOf(p.order, id)
    IN IF pos = 0 THEN p
       ELSE LET prev == p.val[id]
            IN IF prev = v THEN p
               ELSE LET val2 == [p.val EXCEPT ![id] = v]
                    IN IF LogLE(prev, p.committed) /\ LogLT(p.committed, v)
                       THEN LET k == MoveUpPos(p.order, val2, pos)
                                ord2 == MoveTo(p.order, pos, k)
                            IN [cfg |-> p.cfg, order |-> ord2, val |-> val2,
                                committed |-> RecalcCommitted(ord2, val2, p.cfg,
                                                              p.committed, k)]
                       ELSE [p EXCEPT !.val = val2]

\* VecProgress::upgrade_quorum_set: build a fresh progress for the new quorum
\* set, then replay `update(id, old.get(id))` for every id of the OLD quorum set
\* in sorted order.  Ids absent from the new set are ignored; new ids stay None.
\* UPDATE-MAP
\* code: openraft/src/progress/mod.rs:222-232
\* update: Update!ProposeMembershipFocus
RECURSIVE ReplayInto(_, _, _)
ReplayInto(q, old, ids) ==
    IF ids = <<>> THEN q
    ELSE ReplayInto(VecUpdate(q, Head(ids), old.val[Head(ids)]), old, Tail(ids))

UpgradeQuorumSetD(p, cfg, d) ==
    ReplayInto(NewProgressD(cfg, d), p, SortedIds(Voters(p.cfg)))
UpgradeQuorumSet(p, cfg) == UpgradeQuorumSetD(p, cfg, NoLog)

\* Greatest value acknowledged by a quorum of progress values (the documented
\* VecProgress contract, used only by properties).
QuorumAt(p, v) == Quorum(p.cfg, {j \in SeqElems(p.order) : LogLE(v, p.val[j])})

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
    \* UPDATE-MAP
    \* code: openraft/src/leader/leader.rs:22-42; openraft/src/raft_state.rs:44,116-119
    \* update: Update!AffectedActions
    leaderActive,   \* RaftState.leader.is_some()
    progress,       \* RaftState.leader.progress (VecProgress)
    \* Repair (model defect exposed by the update): membership payload of each
    \* log entry ({} = not a membership entry), so followers derive membership
    \* from the entries they append (engine_impl.rs:398-421,688-747).
    logConfig

vars == <<
    currentTerm, voteFor, voteCommitted, role, voteGranted,
    lastLog, logTerm, committed, matchedIndex, matchedTerm,
    committedConfig, effectiveConfig,
    committedMembershipIndex, committedMembershipTerm,
    effectiveMembershipIndex, effectiveMembershipTerm,
    messages, crashed,
    witnessIndex, witnessNodes, witnessConfig, witnessTerm,
    leaderActive, progress, logConfig
>>

witnessVars == <<witnessIndex, witnessNodes, witnessConfig, witnessTerm>>
leaderVars == <<leaderActive, progress>>

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

InitialConfig == {Server}
BaseAllowedConfigs == {InitialConfig}
\* A fixed (arbitrary) id order for standalone base.cfg runs.
BaseServerOrder ==
    CHOOSE s \in [1..Cardinality(Server) -> Server]: SeqElems(s) = Server

\* RaftCore::do_main resets volatile commit while reconstructing stored state:
\* openraft/src/core/raft_core.rs:181-205.  Engine::default has leader None.
Init ==
    /\ currentTerm = [i \in Server |-> 0]
    /\ voteFor = [i \in Server |-> i]
    /\ voteCommitted = [i \in Server |-> FALSE]
    \* Servers outside the initial membership start as learners (they never
    \* elect).  For the default InitialConfig = {Server} this is "follower" for all.
    /\ role = [i \in Server |-> IF i \in Voters(InitialConfig) THEN "follower" ELSE "learner"]
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
    /\ leaderActive = [i \in Server |-> FALSE]
    /\ progress = [i \in Server |-> NoProgress]
    /\ logConfig = [i \in Server |-> [k \in 0..MaxIndex |-> {}]]

LogUpToDate(candidate, voter) ==
    IF lastLog[voter] = Nil
    THEN TRUE
    ELSE IF lastLog[candidate] = Nil
         THEN FALSE
         ELSE \/ logTerm[candidate][lastLog[candidate]] > logTerm[voter][lastLog[voter]]
              \/ /\ logTerm[candidate][lastLog[candidate]] = logTerm[voter][lastLog[voter]]
                 /\ lastLog[candidate] >= lastLog[voter]

\* Engine::calc_server_state (unchanged): member -> leader (committed self vote)
\* / candidate (leader state present) / follower; otherwise learner.
\* openraft/src/engine/engine_impl.rs:907-947
CalcRole(i, cfg, active) ==
    IF i \in Voters(cfg)
    THEN IF voteFor[i] = i /\ voteCommitted[i] THEN "leader"
         ELSE IF active THEN "candidate" ELSE "follower"
    ELSE "learner"

\* Ground-truth acknowledgement set used by the commit witness: the leader's
\* own appended log plus the ReplicationState.matched values reported by
\* replication streams (core/replication.rs:126-128).  It is independent of
\* VecProgress, so CommitWitnessSound can observe a wrong VecProgress result.
AckedAt(rowIndex, rowTerm, idx, term) ==
    {j \in Server: rowIndex[j] >= idx /\ rowTerm[j] = term}

\* Engine::update_progress(node, Some(v)) on leader i, as a pure result:
\*   committed = *leader.progress.update(node, v)          (engine_impl.rs:621-629)
\*   if committed is not proposed by the current vote -> return (engine_impl.rs:632-636)
\*   RaftState::update_committed (raft_state.rs:122-137): raise only.
\* Committed log ids and leader progress values are entries of the leader's own
\* log, so the LogId comparison of update_committed equals the index order.
\* UPDATE-MAP
\* code: openraft/src/engine/engine_impl.rs:617-647; openraft/src/raft_state.rs:122-137
\* update: Update!AffectedActions
UpdateProgressResult(i, p, node, v, comm) ==
    LET p2 == VecUpdate(p, node, v)
        c == p2.committed
        termOK == c = NoLog \/ c[1] = currentTerm[i]
        adv == termOK /\ c # NoLog /\ c[2] > comm
    IN [prog |-> p2, adv |-> adv, commit |-> IF adv THEN c[2] ELSE comm]

NoProgressStep(p, comm) == [prog |-> p, adv |-> FALSE, commit |-> comm]

\* Engine::elect: increment vote, create Leader with a fresh VecProgress over the
\* effective membership, self-grant, and test the quorum through the PROGRESS
\* quorum set (leader.rs:50-53).
\* UPDATE-MAP
\* code: openraft/src/engine/engine_impl.rs:100-130; openraft/src/raft_state.rs:116-119
\* update: Update!AffectedActions
\* Repair (independent of the source delta, needed by the update path): the
\* leader's ReplicationState values are per-LeaderState and start at None
\* (core/replication.rs:40-45); the V0 model kept stale matched values across
\* leaderships.  They are reset here together with the commit witness.
StartElection(i) ==
    /\ i \notin crashed
    /\ role[i] \in {"follower", "candidate"}
    /\ currentTerm[i] < MaxTerm
    /\ LET nextTerm == currentTerm[i] + 1
           grants == {i}
           p == NewProgress(effectiveConfig[i])
           won == Quorum(p.cfg, grants)
       IN /\ currentTerm' = [currentTerm EXCEPT ![i] = nextTerm]
          /\ voteFor' = [voteFor EXCEPT ![i] = i]
          /\ voteCommitted' = [voteCommitted EXCEPT ![i] = won]
          /\ voteGranted' = [voteGranted EXCEPT ![i] = grants]
          /\ role' = [role EXCEPT ![i] = IF won THEN "leader" ELSE "candidate"]
          /\ leaderActive' = [leaderActive EXCEPT ![i] = TRUE]
          /\ progress' = [progress EXCEPT ![i] = p]
    /\ matchedIndex' = [matchedIndex EXCEPT ![i] = [j \in Server |-> Nil]]
    /\ matchedTerm' = [matchedTerm EXCEPT ![i] = [j \in Server |-> 0]]
    /\ witnessIndex' = [witnessIndex EXCEPT ![i] = Nil]
    /\ witnessNodes' = [witnessNodes EXCEPT ![i] = {}]
    /\ witnessConfig' = [witnessConfig EXCEPT ![i] = effectiveConfig[i]]
    /\ witnessTerm' = [witnessTerm EXCEPT ![i] = 0]
    /\ UNCHANGED <<logConfig, lastLog, logTerm, committed,
                   committedConfig, effectiveConfig,
                   committedMembershipIndex, committedMembershipTerm,
                   effectiveMembershipIndex, effectiveMembershipTerm,
                   messages, crashed>>

\* Engine::internal_handle_vote_req (voter) + handle_vote_resp (candidate).
\* The voter's accepted request clears its Engine leader state
\* (engine_impl.rs:893-894).  The candidate counts grants against its progress
\* quorum set (engine_impl.rs:205-209, leader.rs:50-53) and ignores responses
\* once its leader state is gone (engine_impl.rs:176-180).
\* openraft/src/engine/engine_impl.rs:854-905,163-227
GrantVote(candidate, voter) ==
    /\ candidate # voter
    /\ candidate \notin crashed
    /\ voter \notin crashed
    /\ role[candidate] = "candidate"
    /\ leaderActive[candidate]
    /\ voter \in Voters(effectiveConfig[candidate])
    /\ LogUpToDate(candidate, voter)
    /\ \/ currentTerm[voter] < currentTerm[candidate]
       \/ /\ currentTerm[voter] = currentTerm[candidate]
          /\ voteFor[voter] = candidate
    /\ LET grants == voteGranted[candidate] \union {voter}
           won == Quorum(progress[candidate].cfg, grants)
       IN /\ currentTerm' = [currentTerm EXCEPT ![voter] = currentTerm[candidate]]
          /\ voteFor' = [voteFor EXCEPT ![voter] = candidate]
          /\ voteCommitted' = [voteCommitted EXCEPT
                                  ![candidate] = won,
                                  ![voter] = FALSE]
          /\ voteGranted' = [voteGranted EXCEPT ![candidate] = grants]
          /\ role' = [role EXCEPT
                         ![candidate] = IF won THEN "leader" ELSE @,
                         ![voter] = IF voter \in Voters(effectiveConfig[voter])
                                    THEN "follower" ELSE "learner"]
          /\ leaderActive' = [leaderActive EXCEPT ![voter] = FALSE]
          /\ progress' = [progress EXCEPT ![voter] = NoProgress]
    /\ UNCHANGED <<logConfig, lastLog, logTerm, committed, matchedIndex, matchedTerm,
                   committedConfig, effectiveConfig,
                   committedMembershipIndex, committedMembershipTerm,
                   effectiveMembershipIndex, effectiveMembershipTerm,
                   messages, crashed, witnessVars>>

\* Vote derives Ord over (term, node_id, committed) (vote/vote.rs:7-13).
Rank(n) == CHOOSE k \in 1..Len(ServerOrder): ServerOrder[k] = n
VoteLT(a, b) ==
    \/ a[1] < b[1]
    \/ /\ a[1] = b[1]
       /\ \/ Rank(a[2]) < Rank(b[2])
          \/ /\ a[2] = b[2]
             /\ ~a[3]
             /\ b[3]

\* Engine::handle_vote_resp, candidate side only (used directly by trace
\* validation; in MC the voter and candidate sides are combined in GrantVote).
\* Ignore without leader state or for a lower vote; revert on a higher vote;
\* otherwise count a grant against the PROGRESS quorum set (changed by the
\* update, leader.rs:50-53).
\* UPDATE-MAP
\* code: openraft/src/engine/engine_impl.rs:163-227; openraft/src/leader/leader.rs:50-53
\* update: Update!ElectionFocus
HandleVoteResp(i, target, rt, rn, rc, granted) ==
    /\ i \notin crashed
    /\ target \in Server
    /\ rn \in Server
    /\ LET mine == <<currentTerm[i], voteFor[i], voteCommitted[i]>>
           resp == <<rt, rn, rc>>
       IN IF ~leaderActive[i] \/ VoteLT(resp, mine)
          THEN UNCHANGED vars
          ELSE IF VoteLT(mine, resp)
          THEN /\ role' = [role EXCEPT ![i] = IF i \in Voters(effectiveConfig[i])
                                              THEN "follower" ELSE "learner"]
               /\ currentTerm' = [currentTerm EXCEPT ![i] = rt]
               /\ voteFor' = [voteFor EXCEPT ![i] = rn]
               /\ voteCommitted' = [voteCommitted EXCEPT ![i] = rc]
               /\ leaderActive' = [leaderActive EXCEPT ![i] = FALSE]
               /\ progress' = [progress EXCEPT ![i] = NoProgress]
               /\ UNCHANGED <<logConfig, voteGranted, lastLog, logTerm, committed, matchedIndex,
                              matchedTerm, committedConfig, effectiveConfig,
                              committedMembershipIndex, committedMembershipTerm,
                              effectiveMembershipIndex, effectiveMembershipTerm,
                              messages, crashed, witnessVars>>
          ELSE IF granted
          THEN LET grants == voteGranted[i] \union {target}
                   won == Quorum(progress[i].cfg, grants)
               IN /\ voteGranted' = [voteGranted EXCEPT ![i] = grants]
                  /\ voteCommitted' = [voteCommitted EXCEPT ![i] = IF won THEN TRUE ELSE @]
                  /\ role' = [role EXCEPT ![i] = IF won THEN "leader" ELSE @]
                  /\ UNCHANGED <<logConfig, currentTerm, voteFor, lastLog, logTerm, committed,
                                 matchedIndex, matchedTerm, committedConfig,
                                 effectiveConfig, committedMembershipIndex,
                                 committedMembershipTerm, effectiveMembershipIndex,
                                 effectiveMembershipTerm, messages, crashed,
                                 witnessVars, leaderVars>>
          ELSE UNCHANGED vars

AppendTerms(i, oldLast, count) ==
    [k \in 0..MaxIndex |->
        IF k > oldLast /\ k <= oldLast + count
        THEN currentTerm[i]
        ELSE logTerm[i][k]]

\* Engine::leader_append_entries, updated revision.  One synchronous Engine call:
\*  1. assign log ids and extend the log (engine_impl.rs:242-245);
\*  2. for the membership entry at index m: update_progress(self, log_id(m-1))
\*     under the OLD quorum set (engine_impl.rs:273-279), then
\*     update_effective_membership (engine_impl.rs:281-283), which upgrades the
\*     progress quorum set (engine_impl.rs:601-604);
\*  3. update_progress(self, last) under the current quorum set
\*     (engine_impl.rs:286-288).
\* The old revision's single-node `fast_commit` (old engine_impl.rs:604-623) is
\* gone: commit is now whatever the leader progress yields.
\* UPDATE-MAP
\* code: openraft/src/engine/engine_impl.rs:236-293
\* update: Update!ClientAppendFocus, Update!ProposeMembershipFocus
LeaderAppendEntries(i, count, membershipPosition, newConfig) ==
    /\ i \notin crashed
    /\ count \in 1..(MaxIndex + 1)
    /\ lastLog[i] + count <= MaxIndex
    /\ \/ membershipPosition = Nil
       \/ /\ membershipPosition \in 1..count
          /\ ConfigOK(newConfig)
    /\ LET newLast == lastLog[i] + count
           newLogTerm == AppendTerms(i, lastLog[i], count)
           active == leaderActive[i]
           hasMem == membershipPosition # Nil
           memIdx == IF hasMem THEN lastLog[i] + membershipPosition ELSE Nil
           \* ground truth: the leader holds every entry it appended
           selfMatched == [matchedIndex[i] EXCEPT ![i] = newLast]
           selfMatchedTerm == [matchedTerm[i] EXCEPT ![i] = currentTerm[i]]
           \* step 1: get_log_id(m-1) exists only for a stored, non-purged entry
           prevExists == hasMem /\ memIdx > 0 /\ newLogTerm[memIdx - 1] > 0
           s1 == IF active /\ prevExists
                 THEN UpdateProgressResult(i, progress[i], i,
                                           <<newLogTerm[memIdx - 1], memIdx - 1>>,
                                           committed[i])
                 ELSE NoProgressStep(progress[i], committed[i])
           promote1 == s1.adv /\ s1.commit >= effectiveMembershipIndex[i]
           ccfg1 == IF promote1 THEN effectiveConfig[i] ELSE committedConfig[i]
           cidx1 == IF promote1 THEN effectiveMembershipIndex[i] ELSE committedMembershipIndex[i]
           cterm1 == IF promote1 THEN effectiveMembershipTerm[i] ELSE committedMembershipTerm[i]
           \* step 2: update_effective_membership
           eff2 == IF hasMem THEN newConfig ELSE effectiveConfig[i]
           effIdx2 == IF hasMem THEN memIdx ELSE effectiveMembershipIndex[i]
           effTerm2 == IF hasMem THEN currentTerm[i] ELSE effectiveMembershipTerm[i]
           prog2 == IF hasMem /\ active THEN UpgradeQuorumSet(s1.prog, newConfig)
                    ELSE s1.prog
           roleBefore == CalcRole(i, effectiveConfig[i], active)
           roleAfter == CalcRole(i, eff2, active)
           role2 == IF hasMem /\ roleBefore # "leader" /\ roleBefore # roleAfter
                    THEN roleAfter ELSE role[i]
           \* step 3: update_progress(self, last)
           s3 == IF active
                 THEN UpdateProgressResult(i, prog2, i, <<currentTerm[i], newLast>>,
                                           s1.commit)
                 ELSE NoProgressStep(prog2, s1.commit)
           promote3 == s3.adv /\ s3.commit >= effIdx2
           wIdx == IF s3.adv THEN s3.commit ELSE s1.commit
           wCfg == IF s3.adv THEN prog2.cfg ELSE s1.prog.cfg
           anyAdv == s1.adv \/ s3.adv
       IN /\ lastLog' = [lastLog EXCEPT ![i] = newLast]
          /\ logTerm' = [logTerm EXCEPT ![i] = newLogTerm]
          /\ logConfig' = [logConfig EXCEPT
                              ![i] = [k \in 0..MaxIndex |->
                                        IF k > lastLog[i] /\ k <= newLast
                                        THEN IF k = memIdx THEN newConfig ELSE {}
                                        ELSE logConfig[i][k]]]
          /\ effectiveConfig' = [effectiveConfig EXCEPT ![i] = eff2]
          /\ effectiveMembershipIndex' = [effectiveMembershipIndex EXCEPT ![i] = effIdx2]
          /\ effectiveMembershipTerm' = [effectiveMembershipTerm EXCEPT ![i] = effTerm2]
          /\ committed' = [committed EXCEPT ![i] = s3.commit]
          /\ committedConfig' = [committedConfig EXCEPT
                                    ![i] = IF promote3 THEN eff2 ELSE ccfg1]
          /\ committedMembershipIndex' = [committedMembershipIndex EXCEPT
                                             ![i] = IF promote3 THEN effIdx2 ELSE cidx1]
          /\ committedMembershipTerm' = [committedMembershipTerm EXCEPT
                                            ![i] = IF promote3 THEN effTerm2 ELSE cterm1]
          /\ role' = [role EXCEPT ![i] = role2]
          /\ progress' = [progress EXCEPT ![i] = s3.prog]
          /\ matchedIndex' = [matchedIndex EXCEPT ![i] = selfMatched]
          /\ matchedTerm' = [matchedTerm EXCEPT ![i] = selfMatchedTerm]
          /\ witnessIndex' = [witnessIndex EXCEPT ![i] = IF anyAdv THEN wIdx ELSE @]
          /\ witnessNodes' = [witnessNodes EXCEPT
                                 ![i] = IF anyAdv
                                        THEN AckedAt(selfMatched, selfMatchedTerm,
                                                     wIdx, currentTerm[i])
                                        ELSE @]
          /\ witnessConfig' = [witnessConfig EXCEPT ![i] = IF anyAdv THEN wCfg ELSE @]
          /\ witnessTerm' = [witnessTerm EXCEPT
                                ![i] = IF anyAdv THEN currentTerm[i] ELSE @]
    /\ UNCHANGED <<currentTerm, voteFor, voteCommitted, voteGranted,
                   messages, crashed, leaderActive>>

\* Public client writes reach this action only in established leader state:
\* openraft/src/core/leader_state.rs:141-167, core/admin.rs:257-275
ClientAppend(i) ==
    /\ role[i] = "leader"
    /\ voteCommitted[i]
    /\ LeaderAppendEntries(i, 1, Nil, effectiveConfig[i])

\* Membership::next_safe via Joint::find_coherent (unchanged): the goal itself if
\* it is one of the current groups, otherwise [last group, goal].  The model keeps
\* configs as sets, so for a joint current config any group may play "last";
\* AllowedConfigs bounds the result.
\* openraft/src/membership/membership.rs:288-309; quorum/coherent_impl.rs:62-74
SafeNext(cur) ==
    {{g} : g \in cur}
    \union {{g, goal} : g \in cur,
                        goal \in (SUBSET Server) \ ({{}} \union cur)}

\* LeaderState::change_membership rejects a second outstanding change
\* (has_pending_config, core/admin.rs:136-140) and writes next_safe(goal)
\* (core/admin.rs:146-201).  Repair of V0: the V0 model allowed any allowed
\* config directly (e.g. uniform -> different uniform), which next_safe never
\* produces.
ProposeMembership(i, cfg) ==
    /\ role[i] = "leader"
    /\ voteCommitted[i]
    /\ effectiveMembershipIndex[i] <= committed[i]
    /\ cfg \in AllowedConfigs
    /\ cfg \in SafeNext(effectiveConfig[i])
    /\ LeaderAppendEntries(i, 1, 1, cfg)

\* ReplicationCore builds a semantic AppendEntries request (unchanged):
\* openraft/src/replication/mod.rs:264-361
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
    /\ UNCHANGED <<logConfig, currentTerm, voteFor, voteCommitted, role, voteGranted,
                   lastLog, logTerm, committed, matchedIndex, matchedTerm,
                   committedConfig, effectiveConfig,
                   committedMembershipIndex, committedMembershipTerm,
                   effectiveMembershipIndex, effectiveMembershipTerm,
                   crashed, witnessVars, leaderVars>>

\* Engine::handle_append_entries_req, accepted branch (engine_impl.rs:299-357):
\*  - vote accepted -> Engine leader state cleared (engine_impl.rs:893-894);
\*  - first_conflicting_index over the sent entries using has_log_id, which
\*    treats every index <= committed as present (raft_state.rs:85-97);
\*  - truncate_logs(since) when that index exists locally: drop the tail and
\*    revert an effective membership from the dropped range to the committed
\*    one (engine_impl.rs:428-488);
\*  - follower_do_append_entries + follower_update_membership over the appended
\*    suffix: one membership entry -> committed := old effective, effective :=
\*    it; two or more -> the last two (engine_impl.rs:398-421,703-747);
\*  - follower_commit_entries with promotion only on commit advance
\*    (engine_impl.rs:363-386, raft_state.rs:122-137; changed by the update).
\* Entry payloads (terms, membership) are read from the sender's log, as in V0.
\* Repair of the V0 abstraction, which copied the SENDER's current effective
\* membership and kept a stale tail after a conflict; that abstraction was
\* masked by the old unconditional promotion and exposed by the update
\* (spec/output/mc-upd-hunt-u1deep-sim1.log).
\* UPDATE-MAP
\* code: openraft/src/engine/engine_impl.rs:299-386; openraft/src/raft_state.rs:122-137
\* update: Update!FollowerFocus
HasEntry(f, L, k) ==
    \/ k <= committed[f]
    \/ /\ k <= lastLog[f]
       /\ logTerm[f][k] = logTerm[L][k]

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
    /\ LET f == m.to
           L == m.from
           missing == {k \in (m.prev + 1)..m.last : ~HasEntry(f, L, k)}
           since == IF missing = {} THEN Nil
                    ELSE CHOOSE k \in missing: \A k2 \in missing: k <= k2
           appending == since # Nil
           truncating == appending /\ since <= lastLog[f]
           revert == truncating /\ effectiveMembershipIndex[f] >= since
           effCfgA == IF revert THEN committedConfig[f] ELSE effectiveConfig[f]
           effIdxA == IF revert THEN committedMembershipIndex[f] ELSE effectiveMembershipIndex[f]
           effTermA == IF revert THEN committedMembershipTerm[f] ELSE effectiveMembershipTerm[f]
           mems == IF appending
                   THEN {k \in since..m.last : logConfig[L][k] # {}}
                   ELSE {}
           memLast == IF mems = {} THEN Nil
                      ELSE CHOOSE k \in mems: \A k2 \in mems: k2 <= k
           memsBefore == mems \ {memLast}
           memPrev == IF memsBefore = {} THEN Nil
                      ELSE CHOOSE k \in memsBefore: \A k2 \in memsBefore: k2 <= k
           effCfgB == IF memLast = Nil THEN effCfgA ELSE logConfig[L][memLast]
           effIdxB == IF memLast = Nil THEN effIdxA ELSE memLast
           effTermB == IF memLast = Nil THEN effTermA ELSE logTerm[L][memLast]
           cCfgB == IF memLast = Nil THEN committedConfig[f]
                    ELSE IF memPrev = Nil THEN effCfgA ELSE logConfig[L][memPrev]
           cIdxB == IF memLast = Nil THEN committedMembershipIndex[f]
                    ELSE IF memPrev = Nil THEN effIdxA ELSE memPrev
           cTermB == IF memLast = Nil THEN committedMembershipTerm[f]
                     ELSE IF memPrev = Nil THEN effTermA ELSE logTerm[L][memPrev]
           newCommit == IMax(committed[f], IMin(m.leaderCommit, m.last))
           advanced == newCommit > committed[f]
           promote == advanced /\ newCommit >= effIdxB
           ack == [type |-> "ack", from |-> f, to |-> L,
                   term |-> m.term, prev |-> m.prev, last |-> m.last,
                   lastTerm |-> m.lastTerm, leaderCommit |-> newCommit, ok |-> TRUE]
       IN /\ currentTerm' = [currentTerm EXCEPT ![f] = m.term]
          /\ voteFor' = [voteFor EXCEPT ![f] = L]
          /\ voteCommitted' = [voteCommitted EXCEPT ![f] = TRUE]
          /\ role' = [role EXCEPT
                         ![f] = IF f \in Voters(effCfgB) THEN "follower" ELSE "learner"]
          /\ lastLog' = [lastLog EXCEPT ![f] = IF appending THEN m.last ELSE @]
          /\ logTerm' = [logTerm EXCEPT
                            ![f] = IF appending
                                   THEN [k \in 0..MaxIndex |->
                                           IF k < since THEN logTerm[f][k]
                                           ELSE IF k <= m.last THEN logTerm[L][k] ELSE 0]
                                   ELSE @]
          /\ logConfig' = [logConfig EXCEPT
                              ![f] = IF appending
                                     THEN [k \in 0..MaxIndex |->
                                             IF k < since THEN logConfig[f][k]
                                             ELSE IF k <= m.last THEN logConfig[L][k] ELSE {}]
                                     ELSE @]
          /\ committed' = [committed EXCEPT ![f] = newCommit]
          /\ effectiveConfig' = [effectiveConfig EXCEPT ![f] = effCfgB]
          /\ effectiveMembershipIndex' = [effectiveMembershipIndex EXCEPT ![f] = effIdxB]
          /\ effectiveMembershipTerm' = [effectiveMembershipTerm EXCEPT ![f] = effTermB]
          /\ committedConfig' = [committedConfig EXCEPT ![f] = IF promote THEN effCfgB ELSE cCfgB]
          /\ committedMembershipIndex' = [committedMembershipIndex EXCEPT
                                             ![f] = IF promote THEN effIdxB ELSE cIdxB]
          /\ committedMembershipTerm' = [committedMembershipTerm EXCEPT
                                            ![f] = IF promote THEN effTermB ELSE cTermB]
          /\ messages' = (messages \ {m}) \union {ack}
          /\ leaderActive' = [leaderActive EXCEPT ![f] = FALSE]
          /\ progress' = [progress EXCEPT ![f] = NoProgress]
    /\ UNCHANGED <<voteGranted, matchedIndex, matchedTerm, crashed, witnessVars>>

\* A conflicting prev-log causes truncation at an existing conflict and a
\* negative response (unchanged): openraft/src/engine/engine_impl.rs:322-333,
\* openraft/src/replication/mod.rs:431-442.  The accepted vote clears Engine
\* leader state (engine_impl.rs:893-894).
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
    /\ LET f == m.to
           exists == m.prev <= lastLog[f]
           \* truncate_logs reverts an effective membership from the dropped
           \* range to the committed one (engine_impl.rs:459-486); repair of V0.
           revert == exists /\ effectiveMembershipIndex[f] >= m.prev
           effCfg == IF revert THEN committedConfig[f] ELSE effectiveConfig[f]
           ack == [type |-> "ack", from |-> f, to |-> m.from,
                   term |-> m.term, prev |-> m.prev, last |-> m.prev,
                   lastTerm |-> 0, leaderCommit |-> committed[f], ok |-> FALSE]
       IN /\ currentTerm' = [currentTerm EXCEPT ![f] = m.term]
          /\ voteFor' = [voteFor EXCEPT ![f] = m.from]
          /\ voteCommitted' = [voteCommitted EXCEPT ![f] = TRUE]
          /\ role' = [role EXCEPT
                         ![f] = IF f \in Voters(effCfg) THEN "follower" ELSE "learner"]
          /\ lastLog' = [lastLog EXCEPT ![f] = IF exists THEN m.prev - 1 ELSE @]
          /\ logTerm' = [logTerm EXCEPT
                            ![f] = IF exists
                                   THEN [k \in 0..MaxIndex |->
                                           IF k >= m.prev THEN 0 ELSE logTerm[f][k]]
                                   ELSE @]
          /\ logConfig' = [logConfig EXCEPT
                              ![f] = IF exists
                                     THEN [k \in 0..MaxIndex |->
                                             IF k >= m.prev THEN {} ELSE logConfig[f][k]]
                                     ELSE @]
          /\ effectiveConfig' = [effectiveConfig EXCEPT ![f] = effCfg]
          /\ effectiveMembershipIndex' = [effectiveMembershipIndex EXCEPT
                                             ![f] = IF revert THEN committedMembershipIndex[f] ELSE @]
          /\ effectiveMembershipTerm' = [effectiveMembershipTerm EXCEPT
                                            ![f] = IF revert THEN committedMembershipTerm[f] ELSE @]
          /\ messages' = (messages \ {m}) \union {ack}
          /\ leaderActive' = [leaderActive EXCEPT ![f] = FALSE]
          /\ progress' = [progress EXCEPT ![f] = NoProgress]
    /\ UNCHANGED <<voteGranted, committed, matchedIndex, matchedTerm,
                   committedConfig, committedMembershipIndex, committedMembershipTerm,
                   crashed, witnessVars>>

\* LeaderState::handle_update_matched, updated revision: raise
\* ReplicationState.matched (monotonic assertion, core/replication.rs:124-126),
\* return early when matched <= committed (core/replication.rs:133-135), else
\* Engine::update_progress(target, matched) (core/replication.rs:137-138).
\* The old revision recomputed commit from all matched values with
\* greatest_majority_value (old core/replication.rs:141-220).
\* UPDATE-MAP
\* code: openraft/src/core/replication.rs:92-141
\* update: Update!HandleUpdateMatchedFocus
HandleUpdateMatched(m) ==
    /\ m \in messages
    /\ m.type = "ack"
    /\ m.ok
    /\ m.to \notin crashed
    /\ role[m.to] = "leader"
    /\ currentTerm[m.to] = m.term
    /\ m.last >= matchedIndex[m.to][m.from]
    /\ LET i == m.to
           nextMatched == [matchedIndex[i] EXCEPT ![m.from] = m.last]
           nextMatchedTerm == [matchedTerm[i] EXCEPT ![m.from] = m.lastTerm]
           skip == m.last <= committed[i]
           r == IF ~skip /\ leaderActive[i]
                THEN UpdateProgressResult(i, progress[i], m.from,
                                          <<m.lastTerm, m.last>>, committed[i])
                ELSE NoProgressStep(progress[i], committed[i])
           promote == r.adv /\ r.commit >= effectiveMembershipIndex[i]
       IN /\ matchedIndex' = [matchedIndex EXCEPT ![i] = nextMatched]
          /\ matchedTerm' = [matchedTerm EXCEPT ![i] = nextMatchedTerm]
          /\ progress' = [progress EXCEPT ![i] = r.prog]
          /\ committed' = [committed EXCEPT ![i] = r.commit]
          /\ committedConfig' = [committedConfig EXCEPT
                                    ![i] = IF promote THEN effectiveConfig[i] ELSE @]
          /\ committedMembershipIndex' = [committedMembershipIndex EXCEPT
                                             ![i] = IF promote
                                                    THEN effectiveMembershipIndex[i] ELSE @]
          /\ committedMembershipTerm' = [committedMembershipTerm EXCEPT
                                            ![i] = IF promote
                                                   THEN effectiveMembershipTerm[i] ELSE @]
          /\ witnessIndex' = [witnessIndex EXCEPT ![i] = IF r.adv THEN r.commit ELSE @]
          /\ witnessNodes' = [witnessNodes EXCEPT
                                 ![i] = IF r.adv
                                        THEN AckedAt(nextMatched, nextMatchedTerm,
                                                     r.commit, currentTerm[i])
                                        ELSE @]
          /\ witnessConfig' = [witnessConfig EXCEPT ![i] = IF r.adv THEN r.prog.cfg ELSE @]
          /\ witnessTerm' = [witnessTerm EXCEPT ![i] = IF r.adv THEN currentTerm[i] ELSE @]
          /\ messages' = messages \ {m}
    /\ UNCHANGED <<logConfig, currentTerm, voteFor, voteCommitted, role, voteGranted,
                   lastLog, logTerm, effectiveConfig,
                   effectiveMembershipIndex, effectiveMembershipTerm, crashed,
                   leaderActive>>

DiscardNegativeAck(m) ==
    /\ m \in messages
    /\ m.type = "ack"
    /\ ~m.ok
    /\ messages' = messages \ {m}
    /\ UNCHANGED <<logConfig, currentTerm, voteFor, voteCommitted, role, voteGranted,
                   lastLog, logTerm, committed, matchedIndex, matchedTerm,
                   committedConfig, effectiveConfig,
                   committedMembershipIndex, committedMembershipTerm,
                   effectiveMembershipIndex, effectiveMembershipTerm,
                   crashed, witnessVars, leaderVars>>

\* ---------------------------------------------------------------------------
\* Engine helper actions used directly by trace validation (unit fixtures).
\* ---------------------------------------------------------------------------

\* Engine::update_progress as a standalone Engine call (unit tests call it).
\* engine_impl.rs:617-647
UpdateProgress(i, node, v) ==
    /\ i \notin crashed
    /\ node \in Server
    /\ v \in LogIdT
    /\ LET r == IF leaderActive[i]
                THEN UpdateProgressResult(i, progress[i], node, v, committed[i])
                ELSE NoProgressStep(progress[i], committed[i])
           promote == r.adv /\ r.commit >= effectiveMembershipIndex[i]
       IN /\ progress' = [progress EXCEPT ![i] = r.prog]
          /\ committed' = [committed EXCEPT ![i] = r.commit]
          /\ committedConfig' = [committedConfig EXCEPT
                                    ![i] = IF promote THEN effectiveConfig[i] ELSE @]
          /\ committedMembershipIndex' = [committedMembershipIndex EXCEPT
                                             ![i] = IF promote
                                                    THEN effectiveMembershipIndex[i] ELSE @]
          /\ committedMembershipTerm' = [committedMembershipTerm EXCEPT
                                            ![i] = IF promote
                                                   THEN effectiveMembershipTerm[i] ELSE @]
    /\ UNCHANGED <<logConfig, currentTerm, voteFor, voteCommitted, role, voteGranted,
                   lastLog, logTerm, matchedIndex, matchedTerm, effectiveConfig,
                   effectiveMembershipIndex, effectiveMembershipTerm,
                   messages, crashed, witnessVars, leaderActive>>

\* Engine::update_effective_membership (new in the update): replace effective
\* membership, upgrade the leader progress quorum set if a leader state exists,
\* and recompute the server state unless the node was calculated as Leader
\* before the change ("Leader should not quit at once").
\* UPDATE-MAP
\* code: openraft/src/engine/engine_impl.rs:591-615
\* update: Update!ProposeMembershipFocus
UpdateEffectiveMembership(i, t, idx, cfg) ==
    /\ i \notin crashed
    /\ t \in Term
    /\ idx \in Index
    /\ ConfigOK(cfg)
    /\ LET active == leaderActive[i]
           before == CalcRole(i, effectiveConfig[i], active)
           after == CalcRole(i, cfg, active)
       IN /\ effectiveConfig' = [effectiveConfig EXCEPT ![i] = cfg]
          /\ effectiveMembershipIndex' = [effectiveMembershipIndex EXCEPT ![i] = idx]
          /\ effectiveMembershipTerm' = [effectiveMembershipTerm EXCEPT ![i] = t]
          /\ progress' = [progress EXCEPT
                             ![i] = IF active THEN UpgradeQuorumSet(@, cfg) ELSE @]
          /\ role' = [role EXCEPT
                         ![i] = IF before # "leader" /\ before # after
                                THEN after ELSE @]
    /\ UNCHANGED <<logConfig, currentTerm, voteFor, voteCommitted, voteGranted,
                   lastLog, logTerm, committed, matchedIndex, matchedTerm,
                   committedConfig, committedMembershipIndex, committedMembershipTerm,
                   messages, crashed, witnessVars, leaderActive>>

\* Engine::follower_commit_entries, updated revision: same min/max cap, but
\* committed membership is promoted only when commit advances
\* (RaftState::update_committed).
\* UPDATE-MAP
\* code: openraft/src/engine/engine_impl.rs:363-386; openraft/src/raft_state.rs:122-137
\* update: Update!AffectedActions (via DeliverAppendEntries)
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
           advanced == cappedCommit > committed[i]
           nextCommit == IMax(committed[i], cappedCommit)
           promote == advanced /\ nextCommit >= effectiveMembershipIndex[i]
       IN /\ committed' = [committed EXCEPT ![i] = nextCommit]
          /\ committedConfig' = [committedConfig EXCEPT
                                    ![i] = IF promote THEN effectiveConfig[i] ELSE @]
          /\ committedMembershipIndex' = [committedMembershipIndex EXCEPT
                                             ![i] = IF promote
                                                     THEN effectiveMembershipIndex[i] ELSE @]
          /\ committedMembershipTerm' = [committedMembershipTerm EXCEPT
                                            ![i] = IF promote
                                                    THEN effectiveMembershipTerm[i] ELSE @]
    /\ UNCHANGED <<logConfig, currentTerm, voteFor, voteCommitted, role, voteGranted,
                   lastLog, logTerm, matchedIndex, matchedTerm, effectiveConfig,
                   effectiveMembershipIndex, effectiveMembershipTerm,
                   messages, crashed, witnessVars, leaderVars>>

\* Engine::update_committed_membership (unchanged): compares committed log ids by
\* term/index and effective membership by index; server state is recomputed
\* with calc_server_state before/after (engine_impl.rs:555-589).  Repair of the
\* V0 role abstraction to the exact calc_server_state comparison.
UpdateCommittedMembership(i, newTerm, newIndex, newConfig) ==
    /\ i \notin crashed
    /\ newTerm \in Term
    /\ newIndex \in Index
    /\ ConfigOK(newConfig)
    /\ LET committedNewer == \/ newTerm > committedMembershipTerm[i]
                                \/ /\ newTerm = committedMembershipTerm[i]
                                   /\ newIndex > committedMembershipIndex[i]
           replaceEffective == effectiveMembershipIndex[i] <= newIndex
           eff2 == IF replaceEffective THEN newConfig ELSE effectiveConfig[i]
           before == CalcRole(i, effectiveConfig[i], leaderActive[i])
           after == CalcRole(i, eff2, leaderActive[i])
       IN /\ committedConfig' = [committedConfig EXCEPT
                                    ![i] = IF committedNewer THEN newConfig ELSE @]
          /\ committedMembershipIndex' = [committedMembershipIndex EXCEPT
                                             ![i] = IF committedNewer THEN newIndex ELSE @]
          /\ committedMembershipTerm' = [committedMembershipTerm EXCEPT
                                            ![i] = IF committedNewer THEN newTerm ELSE @]
          /\ effectiveConfig' = [effectiveConfig EXCEPT ![i] = eff2]
          /\ effectiveMembershipIndex' = [effectiveMembershipIndex EXCEPT
                                             ![i] = IF replaceEffective THEN newIndex ELSE @]
          /\ effectiveMembershipTerm' = [effectiveMembershipTerm EXCEPT
                                            ![i] = IF replaceEffective THEN newTerm ELSE @]
          /\ role' = [role EXCEPT ![i] = IF before # after THEN after ELSE @]
    /\ UNCHANGED <<logConfig, currentTerm, voteFor, voteCommitted, voteGranted,
                   lastLog, logTerm, committed, matchedIndex, matchedTerm,
                   messages, crashed, witnessVars, leaderVars>>

\* Message loss occurs outside Engine state. It is bounded in MC only.
LoseMessage(m) ==
    /\ m \in messages
    /\ messages' = messages \ {m}
    /\ UNCHANGED <<logConfig, currentTerm, voteFor, voteCommitted, role, voteGranted,
                   lastLog, logTerm, committed, matchedIndex, matchedTerm,
                   committedConfig, effectiveConfig,
                   committedMembershipIndex, committedMembershipTerm,
                   effectiveMembershipIndex, effectiveMembershipTerm,
                   crashed, witnessVars, leaderVars>>

\* Crash/restart preserves vote/log/membership and clears volatile leader data;
\* the Engine is rebuilt with `leader: None` (raft_core.rs:181-205,
\* engine_impl.rs:55-62).
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
    /\ leaderActive' = [leaderActive EXCEPT ![i] = FALSE]
    /\ progress' = [progress EXCEPT ![i] = NoProgress]
    /\ UNCHANGED <<logConfig, currentTerm, voteFor, voteCommitted, lastLog, logTerm,
                   committedConfig, effectiveConfig,
                   committedMembershipIndex, committedMembershipTerm,
                   effectiveMembershipIndex, effectiveMembershipTerm, messages>>

Recover(i) ==
    /\ i \in crashed
    /\ crashed' = crashed \ {i}
    /\ role' = [role EXCEPT ![i] = IF i \in Voters(effectiveConfig[i])
                                     THEN "follower" ELSE "learner"]
    /\ UNCHANGED <<logConfig, currentTerm, voteFor, voteCommitted, voteGranted,
                   lastLog, logTerm, committed, matchedIndex, matchedTerm,
                   committedConfig, effectiveConfig,
                   committedMembershipIndex, committedMembershipTerm,
                   effectiveMembershipIndex, effectiveMembershipTerm,
                   messages, witnessVars, leaderVars>>

Next ==
    \/ \E i \in Server: StartElection(i)
    \/ \E i, j \in Server: GrantVote(i, j)
    \/ \E i \in Server: ClientAppend(i)
    \/ \E i \in Server, cfg \in AllowedConfigs: ProposeMembership(i, cfg)
    \/ \E i, j \in Server: SendAppendEntries(i, j)
    \/ \E m \in messages: DeliverAppendEntries(m)
    \/ \E m \in messages: RejectAppendConflict(m)
    \/ \E m \in messages: HandleUpdateMatched(m)
    \/ \E m \in messages: DiscardNegativeAck(m)
    \/ \E m \in messages: LoseMessage(m)
    \/ \E i \in Server: Crash(i)
    \/ \E i \in Server: Recover(i)

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
    /\ leaderActive \in [Server -> BOOLEAN]
    /\ \A i \in Server: ProgressRec(progress[i])
    /\ \A i \in Server: ~leaderActive[i] => progress[i] = NoProgress
    /\ logConfig \in [Server -> [0..MaxIndex -> SUBSET (SUBSET Server)]]

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

\* Every leader commit advance is backed by a quorum of the commit-time
\* membership whose ACKNOWLEDGED replication (ReplicationState.matched, plus the
\* leader's own log) covers the committed entry in the leader's term.
\* Requirement: guide/src/delete_log.md:18 ("commits logs that already are
\* replicated to a quorum"); guide/src/dynamic-membership.md:140-148 (joint
\* quorums); progress/mod.rs:15-16 ("calculates the committed value through a
\* QuorumSet").
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
