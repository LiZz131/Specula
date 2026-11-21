------------------------------ MODULE base ------------------------------
EXTENDS Naturals, Integers, FiniteSets, Sequences, TLC

\* V1 reference for the updated OpenRaft revision (artifact commit aa05a38).
\* V0 (exact-old) semantics that the update replaced are recorded in
\* spec/changelog.md; UPDATE-MAP comments point to the Update.tla focus.

CONSTANTS Server, MaxTerm, MaxIndex, AllowedConfigs

Nil == -1

ASSUME /\ Server # {}
       /\ MaxTerm \in Nat \ {0}
       /\ MaxIndex \in Nat

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

\* Membership payload of a log entry; NoCfg marks a non-membership entry.
NoCfg == {}

\* REPAIR (pre-existing V0 defect, see changelog Round 2): append requests carry
\* the leader's entries as sent (term and membership payload per index), instead
\* of re-reading the sender's log at delivery time.
MessageUniverse ==
    [type         : {"append", "ack"},
     from         : Server,
     to           : Server,
     term         : Term,
     prev         : Index,
     last         : Index,
     lastTerm     : Term,
     leaderCommit : Index,
     ok           : BOOLEAN,
     ents         : [0..MaxIndex -> Term],
     mcfg         : [0..MaxIndex -> SUBSET (SUBSET Server)]]

VARIABLES
    currentTerm,
    voteFor,
    voteCommitted,
    role,
    voteGranted,
    lastLog,
    logTerm,
    committed,
    \* UPDATE-MAP
    \* code: openraft/src/leader/leader.rs:22-43 (Leader.progress: VecProgress<NID, Option<LogId>, Arc<EffectiveMembership>>)
    \* update: Update!ProgressMonotonic, Update!CommitWitnessSound_new
    \* V1 meaning: matchedIndex[i][j]/matchedTerm[i][j] are the values stored in
    \* node i's Engine-owned leader progress for voter j (index/term of the
    \* LogId; Nil/0 = None or not tracked). They live only while leaderState[i].
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
    \* code: openraft/src/raft_state.rs:44,116-118 (RaftState.leader: Option<Leader>; new_leader)
    \* update: Update!LeaderProgressConfigCurrent
    \* leaderState[i] <=> Engine.state.leader.is_some() (candidate or leader data).
    leaderState,
    \* UPDATE-MAP
    \* code: openraft/src/progress/mod.rs:218-232 (quorum_set, upgrade_quorum_set); leader/leader.rs:50-53
    \* update: Update!LeaderProgressConfigCurrent
    \* progressConfig[i] = the quorum set owned by node i's leader progress; it
    \* decides both vote and commit quorums (meaningful while leaderState[i]).
    progressConfig,
    \* REPAIR (pre-existing V0 defect): logConfig[i][k] is the membership payload
    \* of node i's log entry k (NoCfg for other entries). Needed for
    \* follower_update_membership (engine_impl.rs:671-746) and truncate_logs
    \* (engine_impl.rs:428-485), which derive membership from log entries.
    logConfig

vars == <<
    currentTerm, voteFor, voteCommitted, role, voteGranted,
    lastLog, logTerm, committed, matchedIndex, matchedTerm,
    committedConfig, effectiveConfig,
    committedMembershipIndex, committedMembershipTerm,
    effectiveMembershipIndex, effectiveMembershipTerm,
    messages, crashed,
    witnessIndex, witnessNodes, witnessConfig, witnessTerm,
    leaderState, progressConfig, logConfig
>>

InitialConfig == {Server}
BaseAllowedConfigs == {InitialConfig}

NilRow == [j \in Server |-> Nil]
ZeroRow == [j \in Server |-> 0]
NoCfgLog == [k \in 0..MaxIndex |-> NoCfg]
ZeroLog == [k \in 0..MaxIndex |-> 0]
SetMax(S) == CHOOSE x \in S : \A y \in S : y <= x
SetMin(S) == CHOOSE x \in S : \A y \in S : x <= y

\* RaftCore::do_main resets volatile commit while reconstructing stored state:
\* openraft/src/core/raft_core.rs:181-205. RaftState.leader starts as None.
Init ==
    /\ currentTerm = [i \in Server |-> 0]
    /\ voteFor = [i \in Server |-> i]
    /\ voteCommitted = [i \in Server |-> FALSE]
    /\ role = [i \in Server |-> "follower"]
    /\ voteGranted = [i \in Server |-> {}]
    /\ lastLog = [i \in Server |-> Nil]
    /\ logTerm = [i \in Server |-> [k \in 0..MaxIndex |-> 0]]
    /\ committed = [i \in Server |-> Nil]
    /\ matchedIndex = [i \in Server |-> NilRow]
    /\ matchedTerm = [i \in Server |-> ZeroRow]
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
    /\ leaderState = [i \in Server |-> FALSE]
    /\ progressConfig = [i \in Server |-> InitialConfig]
    /\ logConfig = [i \in Server |-> NoCfgLog]

----------------------------------------------------------------------------
\* LogId order abstraction. A LogId is represented as <<term, index>> and
\* compared lexicographically (LeaderId first, then index); the node-id part of
\* LeaderId is abstracted because one term has one vote holder in this model.
\* None is <<0, Nil>>, the least value.
NoLid == <<0, Nil>>
LidGeq(a, b) == \/ a[1] > b[1]
                \/ /\ a[1] = b[1]
                   /\ a[2] >= b[2]
RowLid(rowI, rowT, j) == <<rowT[j], rowI[j]>>

\* UPDATE-MAP
\* code: openraft/src/progress/mod.rs:163-205 (VecProgress::update committed recalculation)
\* update: Update!AffectedActions (UpdateProgress via HandleUpdateMatched / LeaderAppendEntries)
\* VecProgress keeps `committed` equal to the greatest stored value v such that
\* the ids whose value is >= v form a quorum of its quorum set (values only
\* grow, quorum sets are monotone). Only ids of the quorum set are tracked.
QuorumValues(cfg, rowI, rowT) ==
    {v \in {RowLid(rowI, rowT, j) : j \in Voters(cfg)} :
        Quorum(cfg, {j \in Voters(cfg) : LidGeq(RowLid(rowI, rowT, j), v)})}

GreatestQuorumValue(cfg, rowI, rowT) ==
    LET qv == QuorumValues(cfg, rowI, rowT)
    IN IF qv = {} THEN NoLid
       ELSE CHOOSE v \in qv : \A w \in qv : LidGeq(v, w)

Supporters(cfg, rowI, rowT, v) ==
    {j \in Voters(cfg) : LidGeq(RowLid(rowI, rowT, j), v)}

\* VecProgress::upgrade_quorum_set: a fresh progress over the new quorum set,
\* re-fed with every old id's value (unknown ids are ignored):
\* openraft/src/progress/mod.rs:222-232, 163-171
UpgradeRow(row, oldCfg, newCfg, default) ==
    [j \in Server |-> IF j \in Voters(oldCfg) /\ j \in Voters(newCfg)
                      THEN row[j] ELSE default]

----------------------------------------------------------------------------
\* Node-local Engine state used to compose the synchronous Engine helpers that
\* leader_append_entries calls in sequence (engine_impl.rs:236-292). The record
\* is only a functional view of the reference variables.
Local(i) ==
    [mi |-> matchedIndex[i], mt |-> matchedTerm[i], c |-> committed[i],
     ccfg |-> committedConfig[i], cidx |-> committedMembershipIndex[i],
     cterm |-> committedMembershipTerm[i],
     ecfg |-> effectiveConfig[i], eidx |-> effectiveMembershipIndex[i],
     eterm |-> effectiveMembershipTerm[i],
     pcfg |-> progressConfig[i], role |-> role[i],
     wi |-> witnessIndex[i], wn |-> witnessNodes[i], wc |-> witnessConfig[i],
     wt |-> witnessTerm[i]]

AssignLocal(i, st) ==
    /\ matchedIndex' = [matchedIndex EXCEPT ![i] = st.mi]
    /\ matchedTerm' = [matchedTerm EXCEPT ![i] = st.mt]
    /\ committed' = [committed EXCEPT ![i] = st.c]
    /\ committedConfig' = [committedConfig EXCEPT ![i] = st.ccfg]
    /\ committedMembershipIndex' = [committedMembershipIndex EXCEPT ![i] = st.cidx]
    /\ committedMembershipTerm' = [committedMembershipTerm EXCEPT ![i] = st.cterm]
    /\ effectiveConfig' = [effectiveConfig EXCEPT ![i] = st.ecfg]
    /\ effectiveMembershipIndex' = [effectiveMembershipIndex EXCEPT ![i] = st.eidx]
    /\ effectiveMembershipTerm' = [effectiveMembershipTerm EXCEPT ![i] = st.eterm]
    /\ progressConfig' = [progressConfig EXCEPT ![i] = st.pcfg]
    /\ role' = [role EXCEPT ![i] = st.role]
    /\ witnessIndex' = [witnessIndex EXCEPT ![i] = st.wi]
    /\ witnessNodes' = [witnessNodes EXCEPT ![i] = st.wn]
    /\ witnessConfig' = [witnessConfig EXCEPT ![i] = st.wc]
    /\ witnessTerm' = [witnessTerm EXCEPT ![i] = st.wt]

\* UPDATE-MAP
\* code: openraft/src/raft_state.rs:122-136 (RaftState::update_committed)
\* update: Update!AffectedActions (HandleUpdateMatched, LeaderAppendEntries, DeliverAppendEntries)
\* Commit only moves forward; committed membership is promoted only when the
\* commit actually advanced and reaches the effective membership log id.
\* LogId comparison is abstracted to index comparison: all compared ids lie in
\* the node's own log, where index order equals LogId order.
UpdateCommittedF(st, newC) ==
    IF newC > st.c
    THEN LET promote == newC >= st.eidx
         IN [st EXCEPT !.c = newC,
                       !.ccfg = IF promote THEN st.ecfg ELSE @,
                       !.cidx = IF promote THEN st.eidx ELSE @,
                       !.cterm = IF promote THEN st.eterm ELSE @]
    ELSE st

\* UPDATE-MAP
\* code: openraft/src/engine/engine_impl.rs:617-647 (Engine::update_progress)
\* update: Update!AffectedActions, Update!CommitWitnessSound_new, Update!ProgressMonotonic
\* - no leader data: return without any change (engine_impl.rs:621-626);
\* - VecProgress::update ignores ids outside its quorum set (progress/mod.rs:166-171);
\* - the quorum value is committed only if its LeaderId is the current vote's
\*   (engine_impl.rs:631-637), through update_committed (engine_impl.rs:639-646).
UpdateProgressF(i, st, node, idx, term) ==
    IF ~leaderState[i]
    THEN st
    ELSE LET tracked == node \in Voters(st.pcfg)
             mi2 == IF tracked THEN [st.mi EXCEPT ![node] = idx] ELSE st.mi
             mt2 == IF tracked THEN [st.mt EXCEPT ![node] = term] ELSE st.mt
             v == GreatestQuorumValue(st.pcfg, mi2, mt2)
             byCurrentLeader == v[1] = currentTerm[i]
             advanced == byCurrentLeader /\ v[2] > st.c
             st1 == [st EXCEPT !.mi = mi2, !.mt = mt2]
             st2 == IF byCurrentLeader THEN UpdateCommittedF(st1, v[2]) ELSE st1
         IN IF advanced
            THEN [st2 EXCEPT !.wi = v[2],
                             !.wn = Supporters(st.pcfg, mi2, mt2, v),
                             !.wc = st.pcfg,
                             !.wt = currentTerm[i]]
            ELSE st2

\* Engine::calc_server_state: openraft/src/engine/engine_impl.rs:915-933
\* is_member = voter of the effective membership (membership_state.rs:38-40),
\* is_leader = committed vote for self, is_becoming_leader = leader data exists.
CalcServerState(i, cfg) ==
    IF i \in Voters(cfg)
    THEN IF voteFor[i] = i /\ voteCommitted[i] THEN "leader"
         ELSE IF leaderState[i] THEN "candidate"
         ELSE "follower"
    ELSE "learner"

\* UPDATE-MAP
\* code: openraft/src/engine/engine_impl.rs:591-615 (Engine::update_effective_membership)
\* update: Update!AffectedActions, Update!LeaderProgressConfigCurrent
\* Effective membership takes effect at once; leader progress is upgraded to
\* the new quorum set; the server state is recomputed unless it was Leader.
UpdateEffectiveMembershipF(i, st, idx, term, cfg) ==
    LET prevCalc == CalcServerState(i, st.ecfg)
        newCalc == CalcServerState(i, cfg)
        upgrade == leaderState[i]
    IN [st EXCEPT !.ecfg = cfg, !.eidx = idx, !.eterm = term,
                  !.pcfg = IF upgrade THEN cfg ELSE @,
                  !.mi = IF upgrade THEN UpgradeRow(st.mi, st.pcfg, cfg, Nil) ELSE @,
                  !.mt = IF upgrade THEN UpgradeRow(st.mt, st.pcfg, cfg, 0) ELSE @,
                  !.role = IF prevCalc # "leader" /\ prevCalc # newCalc
                           THEN newCalc ELSE @]

----------------------------------------------------------------------------
LogUpToDate(candidate, voter) ==
    IF lastLog[voter] = Nil
    THEN TRUE
    ELSE IF lastLog[candidate] = Nil
         THEN FALSE
         ELSE \/ logTerm[candidate][lastLog[candidate]] > logTerm[voter][lastLog[voter]]
              \/ /\ logTerm[candidate][lastLog[candidate]] = logTerm[voter][lastLog[voter]]
                 /\ lastLog[candidate] >= lastLog[voter]

\* UPDATE-MAP
\* code: openraft/src/engine/engine_impl.rs:99-128 (Engine::elect); raft_state.rs:114-118 (new_leader)
\* update: Update!AffectedActions (MCStartElection)
\* Engine::elect increments the vote, creates fresh leader data whose progress
\* quorum set is the current effective membership, self-grants, and uses
\* Leader::is_vote_granted (progress quorum set) for the single-node fast path.
StartElection(i) ==
    /\ i \notin crashed
    /\ role[i] \in {"follower", "candidate"}
    /\ currentTerm[i] < MaxTerm
    /\ LET nextTerm == currentTerm[i] + 1
           grants == {i}
           won == Quorum(effectiveConfig[i], grants)
       IN /\ currentTerm' = [currentTerm EXCEPT ![i] = nextTerm]
          /\ voteFor' = [voteFor EXCEPT ![i] = i]
          /\ voteCommitted' = [voteCommitted EXCEPT ![i] = won]
          /\ voteGranted' = [voteGranted EXCEPT ![i] = grants]
          /\ role' = [role EXCEPT ![i] = IF won THEN "leader" ELSE "candidate"]
          /\ leaderState' = [leaderState EXCEPT ![i] = TRUE]
          /\ progressConfig' = [progressConfig EXCEPT ![i] = effectiveConfig[i]]
          /\ matchedIndex' = [matchedIndex EXCEPT ![i] = NilRow]
          /\ matchedTerm' = [matchedTerm EXCEPT ![i] = ZeroRow]
    /\ UNCHANGED <<lastLog, logTerm, committed,
                   committedConfig, effectiveConfig,
                   committedMembershipIndex, committedMembershipTerm,
                   effectiveMembershipIndex, effectiveMembershipTerm,
                   messages, crashed, witnessIndex, witnessNodes,
                   witnessConfig, witnessTerm, logConfig>>

\* UPDATE-MAP
\* code: openraft/src/engine/engine_impl.rs:854-912 (internal_handle_vote_req clears leader data),
\*       engine_impl.rs:163-226 (handle_vote_resp uses Leader::is_vote_granted, leader/leader.rs:50-53)
\* update: Update!AffectedActions (MCGrantVote)
\* The voter's accepted vote request drops its leader data; the candidate counts
\* the grant against its progress quorum set.
GrantVote(candidate, voter) ==
    /\ candidate # voter
    /\ candidate \notin crashed
    /\ voter \notin crashed
    /\ role[candidate] = "candidate"
    /\ leaderState[candidate]
    /\ voter \in Voters(effectiveConfig[candidate])
    /\ LogUpToDate(candidate, voter)
    /\ \/ currentTerm[voter] < currentTerm[candidate]
       \/ /\ currentTerm[voter] = currentTerm[candidate]
          /\ voteFor[voter] = candidate
    /\ LET grants == voteGranted[candidate] \union {voter}
           won == Quorum(progressConfig[candidate], grants)
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
          /\ leaderState' = [leaderState EXCEPT ![voter] = FALSE]
          /\ matchedIndex' = [matchedIndex EXCEPT ![voter] = NilRow]
          /\ matchedTerm' = [matchedTerm EXCEPT ![voter] = ZeroRow]
    /\ UNCHANGED <<lastLog, logTerm, committed,
                   committedConfig, effectiveConfig,
                   committedMembershipIndex, committedMembershipTerm,
                   effectiveMembershipIndex, effectiveMembershipTerm,
                   messages, crashed, witnessIndex, witnessNodes,
                   witnessConfig, witnessTerm, progressConfig, logConfig>>

AppendTerms(i, oldLast, count) ==
    [k \in 0..MaxIndex |->
        IF k > oldLast /\ k <= oldLast + count
        THEN currentTerm[i]
        ELSE logTerm[i][k]]

\* UPDATE-MAP
\* code: openraft/src/engine/engine_impl.rs:226-292 (Engine::leader_append_entries)
\* update: Update!AffectedActions (MCClientAppend, MCProposeMembership)
\* Log ids are assigned from the current vote. For a membership entry at log
\* index mIdx, leader progress is first advanced to mIdx-1 under the old quorum
\* set (engine_impl.rs:272-280), then effective membership and the progress
\* quorum set change (engine_impl.rs:282-283), and finally the leader's own
\* progress reaches the last entry under the new set (engine_impl.rs:286-288).
\* Commit (and committed-membership promotion) happens only through
\* update_progress, i.e. only when leader data exists. The model admits at most
\* one membership entry per batch; the runtime writes single-entry batches
\* (core/admin.rs:249-274, core/client.rs).
LeaderAppendEntries(i, count, membershipPosition, newConfig) ==
    /\ i \notin crashed
    /\ count \in 1..(MaxIndex + 1)
    /\ lastLog[i] + count <= MaxIndex
    /\ \/ membershipPosition = Nil
       \/ /\ membershipPosition \in 1..count
          /\ ConfigOK(newConfig)
    /\ LET newLast == lastLog[i] + count
           newLog == AppendTerms(i, lastLog[i], count)
           hasMembership == membershipPosition # Nil
           mIdx == lastLog[i] + membershipPosition
           st0 == Local(i)
           st1 == IF hasMembership /\ mIdx > 0
                  THEN UpdateProgressF(i, st0, i, mIdx - 1, newLog[mIdx - 1])
                  ELSE st0
           st2 == IF hasMembership
                  THEN UpdateEffectiveMembershipF(i, st1, mIdx, currentTerm[i], newConfig)
                  ELSE st1
           st3 == UpdateProgressF(i, st2, i, newLast, currentTerm[i])
       IN /\ lastLog' = [lastLog EXCEPT ![i] = newLast]
          /\ logTerm' = [logTerm EXCEPT ![i] = newLog]
          /\ logConfig' = [logConfig EXCEPT ![i] =
                [k \in 0..MaxIndex |->
                    IF k > lastLog[i] /\ k <= newLast
                    THEN IF hasMembership /\ k = mIdx THEN newConfig ELSE NoCfg
                    ELSE logConfig[i][k]]]
          /\ AssignLocal(i, st3)
    /\ UNCHANGED <<currentTerm, voteFor, voteCommitted, voteGranted,
                   messages, crashed, leaderState>>

\* Public client writes reach this internal action only in established leader state:
\* openraft/src/core/leader_state.rs:141-167
ClientAppend(i) ==
    /\ role[i] = "leader"
    /\ voteCommitted[i]
    /\ LeaderAppendEntries(i, 1, Nil, effectiveConfig[i])

\* LeaderState::change_membership rejects a second outstanding voter change:
\* openraft/src/core/admin.rs:135-199
ProposeMembership(i, cfg) ==
    /\ role[i] = "leader"
    /\ voteCommitted[i]
    /\ effectiveMembershipIndex[i] <= committed[i]
    /\ cfg \in AllowedConfigs
    /\ LeaderAppendEntries(i, 1, 1, cfg)

\* ReplicationCore builds a semantic AppendEntries request after loading a
\* consecutive range: openraft/src/replication/mod.rs:264-361. The previous log
\* id is the abstraction of the stream's matched cursor; leader progress is the
\* Engine-side copy of that cursor (fresh streams start at None).
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
                   lastTerm |-> lt, leaderCommit |-> committed[i], ok |-> TRUE,
                   ents |-> [k \in 0..MaxIndex |->
                               IF k <= lastLog[i] THEN logTerm[i][k] ELSE 0],
                   mcfg |-> [k \in 0..MaxIndex |->
                               IF k <= lastLog[i] THEN logConfig[i][k] ELSE NoCfg]]
       IN messages' = messages \union {msg}
    /\ UNCHANGED <<currentTerm, voteFor, voteCommitted, role, voteGranted,
                   lastLog, logTerm, committed, matchedIndex, matchedTerm,
                   committedConfig, effectiveConfig,
                   committedMembershipIndex, committedMembershipTerm,
                   effectiveMembershipIndex, effectiveMembershipTerm,
                   crashed, witnessIndex, witnessNodes, witnessConfig, witnessTerm,
                   leaderState, progressConfig, logConfig>>

AckMsg(from, to, term, prev, last, lastTerm, lc, ok) ==
    [type |-> "ack", from |-> from, to |-> to, term |-> term, prev |-> prev,
     last |-> last, lastTerm |-> lastTerm, leaderCommit |-> lc, ok |-> ok,
     ents |-> ZeroLog, mcfg |-> NoCfgLog]

\* RaftState::has_log_id: an index inside the committed prefix is treated as
\* present; otherwise the local entry must carry the same LogId (term):
\* openraft/src/raft_state.rs:85-97
HasLogId(i, k, t) ==
    \/ k <= committed[i]
    \/ /\ k <= lastLog[i]
       /\ logTerm[i][k] = t

\* UPDATE-MAP
\* code: openraft/src/engine/engine_impl.rs:295-389 (handle_append_entries_req, follower_commit_entries)
\* update: Update!AffectedActions (MCDeliverAppendEntries)
\* Engine::handle_append_entries_req: the vote check drops leader data
\* (internal_handle_vote_req, engine_impl.rs:897); prev_log_id must be present
\* (engine_impl.rs:322-331); the first entry that is not present is located
\* (first_conflicting_index, engine_impl.rs:337-346); conflicting local entries
\* are truncated, reverting an effective membership that lived in them to the
\* committed one (truncate_logs, engine_impl.rs:428-485); the remaining entries
\* are appended and the last two membership entries among them become
\* committed/effective (follower_update_membership/update_membership_state,
\* engine_impl.rs:671-746); finally the exact follower commit cap is applied and
\* committed membership is promoted only when the commit advances
\* (follower_commit_entries -> RaftState::update_committed).
\* REPAIR (pre-existing V0 defect, changelog Round 2): V0 copied the sender's
\* *current* effective membership only if it was <= m.last, read the sender's
\* log at delivery time, and never truncated a conflicting suffix.
DeliverAppendEntries(m) ==
    /\ m \in messages
    /\ m.type = "append"
    /\ m.to \notin crashed
    /\ m.term >= currentTerm[m.to]
    /\ IF m.prev = Nil THEN TRUE ELSE HasLogId(m.to, m.prev, m.ents[m.prev])
    /\ LET f == m.to
           missing == {k \in (m.prev + 1)..m.last : ~HasLogId(f, k, m.ents[k])}
           conflict == missing # {}
           since == IF conflict THEN SetMin(missing) ELSE Nil
           truncates == conflict /\ since <= lastLog[f]
           revert == truncates /\ since <= effectiveMembershipIndex[f]
           e0cfg == IF revert THEN committedConfig[f] ELSE effectiveConfig[f]
           e0idx == IF revert THEN committedMembershipIndex[f] ELSE effectiveMembershipIndex[f]
           e0term == IF revert THEN committedMembershipTerm[f] ELSE effectiveMembershipTerm[f]
           newLast == IF conflict THEN m.last ELSE lastLog[f]
           newLog == IF conflict
                     THEN [k \in 0..MaxIndex |->
                             IF k < since THEN logTerm[f][k]
                             ELSE IF k <= m.last THEN m.ents[k] ELSE 0]
                     ELSE logTerm[f]
           newCfgLog == IF conflict
                        THEN [k \in 0..MaxIndex |->
                                IF k < since THEN logConfig[f][k]
                                ELSE IF k <= m.last THEN m.mcfg[k] ELSE NoCfg]
                        ELSE logConfig[f]
           mems == IF conflict THEN {k \in since..m.last : m.mcfg[k] # NoCfg} ELSE {}
           lastM == SetMax(mems)
           prevMs == mems \ {lastM}
           prevM == SetMax(prevMs)
           e1cfg == IF mems = {} THEN e0cfg ELSE m.mcfg[lastM]
           e1idx == IF mems = {} THEN e0idx ELSE lastM
           e1term == IF mems = {} THEN e0term ELSE m.ents[lastM]
           c1cfg == IF mems = {} THEN committedConfig[f]
                    ELSE IF prevMs = {} THEN e0cfg ELSE m.mcfg[prevM]
           c1idx == IF mems = {} THEN committedMembershipIndex[f]
                    ELSE IF prevMs = {} THEN e0idx ELSE prevM
           c1term == IF mems = {} THEN committedMembershipTerm[f]
                     ELSE IF prevMs = {} THEN e0term ELSE m.ents[prevM]
           capped == IMin(m.leaderCommit, m.last)
           advance == capped > committed[f]
           newCommit == IF advance THEN capped ELSE committed[f]
           promote == advance /\ newCommit >= e1idx
           ack == AckMsg(f, m.from, m.term, m.prev, m.last, m.lastTerm, newCommit, TRUE)
       IN /\ currentTerm' = [currentTerm EXCEPT ![f] = m.term]
          /\ voteFor' = [voteFor EXCEPT ![f] = m.from]
          /\ voteCommitted' = [voteCommitted EXCEPT ![f] = TRUE]
          /\ role' = [role EXCEPT ![f] = IF f \in Voters(e1cfg) THEN "follower" ELSE "learner"]
          /\ lastLog' = [lastLog EXCEPT ![f] = newLast]
          /\ logTerm' = [logTerm EXCEPT ![f] = newLog]
          /\ logConfig' = [logConfig EXCEPT ![f] = newCfgLog]
          /\ committed' = [committed EXCEPT ![f] = newCommit]
          /\ effectiveConfig' = [effectiveConfig EXCEPT ![f] = e1cfg]
          /\ effectiveMembershipIndex' = [effectiveMembershipIndex EXCEPT ![f] = e1idx]
          /\ effectiveMembershipTerm' = [effectiveMembershipTerm EXCEPT ![f] = e1term]
          /\ committedConfig' = [committedConfig EXCEPT ![f] = IF promote THEN e1cfg ELSE c1cfg]
          /\ committedMembershipIndex' = [committedMembershipIndex EXCEPT
                                             ![f] = IF promote THEN e1idx ELSE c1idx]
          /\ committedMembershipTerm' = [committedMembershipTerm EXCEPT
                                            ![f] = IF promote THEN e1term ELSE c1term]
          /\ messages' = (messages \ {m}) \union {ack}
          /\ leaderState' = [leaderState EXCEPT ![f] = FALSE]
          /\ matchedIndex' = [matchedIndex EXCEPT ![f] = NilRow]
          /\ matchedTerm' = [matchedTerm EXCEPT ![f] = ZeroRow]
    /\ UNCHANGED <<voteGranted, crashed,
                   witnessIndex, witnessNodes, witnessConfig, witnessTerm,
                   progressConfig>>

\* A missing or conflicting prev-log id truncates the local log at prev (when an
\* entry exists there), reverting an effective membership inside the truncated
\* range to the committed one, and answers Conflict; binary-search cursor
\* details stay internal:
\* openraft/src/engine/engine_impl.rs:322-331, 428-485
\* openraft/src/replication/mod.rs:431-442
\* The vote check (internal_handle_vote_req) drops leader data first.
\* REPAIR (pre-existing V0 defect): membership revert and payload truncation.
RejectAppendConflict(m) ==
    /\ m \in messages
    /\ m.type = "append"
    /\ m.to \notin crashed
    /\ m.term >= currentTerm[m.to]
    /\ m.prev # Nil
    /\ ~HasLogId(m.to, m.prev, m.ents[m.prev])
    /\ LET f == m.to
           exists == m.prev <= lastLog[f]
           revert == exists /\ m.prev <= effectiveMembershipIndex[f]
           ecfg == IF revert THEN committedConfig[f] ELSE effectiveConfig[f]
           ack == AckMsg(f, m.from, m.term, m.prev, m.prev, 0, committed[f], FALSE)
       IN /\ currentTerm' = [currentTerm EXCEPT ![f] = m.term]
          /\ voteFor' = [voteFor EXCEPT ![f] = m.from]
          /\ voteCommitted' = [voteCommitted EXCEPT ![f] = TRUE]
          /\ role' = [role EXCEPT ![f] = IF f \in Voters(ecfg) THEN "follower" ELSE "learner"]
          /\ lastLog' = [lastLog EXCEPT ![f] = IF exists THEN m.prev - 1 ELSE @]
          /\ logTerm' = [logTerm EXCEPT
                            ![f] = IF exists
                                   THEN [k \in 0..MaxIndex |->
                                           IF k >= m.prev THEN 0 ELSE logTerm[f][k]]
                                   ELSE @]
          /\ logConfig' = [logConfig EXCEPT
                              ![f] = IF exists
                                     THEN [k \in 0..MaxIndex |->
                                             IF k >= m.prev THEN NoCfg ELSE logConfig[f][k]]
                                     ELSE @]
          /\ effectiveConfig' = [effectiveConfig EXCEPT ![f] = ecfg]
          /\ effectiveMembershipIndex' = [effectiveMembershipIndex EXCEPT
                                             ![f] = IF revert THEN committedMembershipIndex[f] ELSE @]
          /\ effectiveMembershipTerm' = [effectiveMembershipTerm EXCEPT
                                            ![f] = IF revert THEN committedMembershipTerm[f] ELSE @]
          /\ messages' = (messages \ {m}) \union {ack}
          /\ leaderState' = [leaderState EXCEPT ![f] = FALSE]
          /\ matchedIndex' = [matchedIndex EXCEPT ![f] = NilRow]
          /\ matchedTerm' = [matchedTerm EXCEPT ![f] = ZeroRow]
    /\ UNCHANGED <<voteGranted, committed,
                   committedConfig, committedMembershipIndex, committedMembershipTerm,
                   crashed, witnessIndex, witnessNodes, witnessConfig, witnessTerm,
                   progressConfig>>

\* UPDATE-MAP
\* code: openraft/src/core/replication.rs:97-141 (handle_update_matched -> Engine::update_progress)
\* update: Update!AffectedActions (MCHandleUpdateMatched)
\* The leader actor asserts monotonic per-stream matched values
\* (replication.rs:122), returns early when the matched id is not above the
\* current commit (replication.rs:133-135, so leader progress is not updated),
\* and otherwise delegates the progress+commit transition to the Engine.
HandleUpdateMatched(m) ==
    /\ m \in messages
    /\ m.type = "ack"
    /\ m.ok
    /\ m.to \notin crashed
    /\ role[m.to] = "leader"
    /\ currentTerm[m.to] = m.term
    /\ m.last >= matchedIndex[m.to][m.from]
    /\ LET st == IF m.last <= committed[m.to]
                 THEN Local(m.to)
                 ELSE UpdateProgressF(m.to, Local(m.to), m.from, m.last, m.lastTerm)
       IN AssignLocal(m.to, st)
    /\ messages' = messages \ {m}
    /\ UNCHANGED <<currentTerm, voteFor, voteCommitted, voteGranted,
                   lastLog, logTerm, crashed, leaderState, logConfig>>

\* UPDATE-MAP
\* code: openraft/src/progress/mod.rs:163-205 (VecProgress::update, unknown id ignored at 166-171)
\* update: Update!ProgressMonotonic (trace-only data-structure relation)
\* Direct form used to validate VecProgress's externally visible update relation;
\* its sorted-vector layout is deliberately abstracted away. Unit-test values
\* are plain integers, represented with the node's current term.
ProgressUpdateValue(i, target, newValue) ==
    /\ i \in Server
    /\ target \in Server
    /\ newValue \in Index
    /\ LET tracked == target \in Voters(progressConfig[i])
           nextMatched == IF tracked THEN [matchedIndex[i] EXCEPT ![target] = newValue]
                          ELSE matchedIndex[i]
           nextMatchedTerm == IF tracked THEN [matchedTerm[i] EXCEPT ![target] = currentTerm[i]]
                              ELSE matchedTerm[i]
           v == GreatestQuorumValue(progressConfig[i], nextMatched, nextMatchedTerm)
       IN /\ tracked => newValue >= matchedIndex[i][target]
          /\ matchedIndex' = [matchedIndex EXCEPT ![i] = nextMatched]
          /\ matchedTerm' = [matchedTerm EXCEPT ![i] = nextMatchedTerm]
          /\ committed' = [committed EXCEPT ![i] = IMax(@, v[2])]
    /\ UNCHANGED <<currentTerm, voteFor, voteCommitted, role, voteGranted,
                   lastLog, logTerm, committedConfig, effectiveConfig,
                   committedMembershipIndex, committedMembershipTerm,
                   effectiveMembershipIndex, effectiveMembershipTerm,
                   messages, crashed, witnessIndex, witnessNodes,
                   witnessConfig, witnessTerm, leaderState, progressConfig, logConfig>>

\* UPDATE-MAP
\* code: openraft/src/engine/engine_impl.rs:617-647 (Engine::update_progress)
\* update: Update!AffectedActions (trace-only direct form)
\* Engine-level update_progress validated directly by traces. VecProgress
\* asserts non-decreasing values for tracked ids (progress/mod.rs:180).
UpdateProgress(i, node, idx, term) ==
    /\ i \notin crashed
    /\ node \in Server
    /\ idx \in Index
    /\ term \in Term
    /\ (leaderState[i] /\ node \in Voters(progressConfig[i]))
          => LidGeq(<<term, idx>>, RowLid(matchedIndex[i], matchedTerm[i], node))
    /\ AssignLocal(i, UpdateProgressF(i, Local(i), node, idx, term))
    /\ UNCHANGED <<currentTerm, voteFor, voteCommitted, voteGranted,
                   lastLog, logTerm, messages, crashed, leaderState, logConfig>>

\* UPDATE-MAP
\* code: openraft/src/engine/engine_impl.rs:591-615 (Engine::update_effective_membership)
\* update: Update!LeaderProgressConfigCurrent (trace-only direct form)
UpdateEffectiveMembership(i, idx, term, cfg) ==
    /\ i \notin crashed
    /\ idx \in Index
    /\ term \in Term
    /\ ConfigOK(cfg)
    /\ AssignLocal(i, UpdateEffectiveMembershipF(i, Local(i), idx, term, cfg))
    /\ UNCHANGED <<currentTerm, voteFor, voteCommitted, voteGranted,
                   lastLog, logTerm, messages, crashed, leaderState, logConfig>>

\* UPDATE-MAP
\* code: openraft/src/engine/engine_impl.rs:163-226 (Engine::handle_vote_resp)
\* update: Update!AffectedActions (candidate half of MCGrantVote, trace-only direct form)
\* cmp is the total order of the response vote against the local vote
\* (vote/vote.rs:7 derives Ord over term, node_id, committed).
HandleVoteResp(i, target, cmp, respTerm, respNode, respCommitted, granted) ==
    /\ i \notin crashed
    /\ cmp \in {"lt", "eq", "gt"}
    /\ IF ~leaderState[i] \/ cmp = "lt"
       THEN UNCHANGED vars
       ELSE IF cmp = "gt"
       THEN /\ currentTerm' = [currentTerm EXCEPT ![i] = respTerm]
            /\ voteFor' = [voteFor EXCEPT ![i] = respNode]
            /\ voteCommitted' = [voteCommitted EXCEPT ![i] = respCommitted]
            /\ role' = [role EXCEPT ![i] = IF i \in Voters(effectiveConfig[i])
                                           THEN "follower" ELSE "learner"]
            /\ leaderState' = [leaderState EXCEPT ![i] = FALSE]
            /\ matchedIndex' = [matchedIndex EXCEPT ![i] = NilRow]
            /\ matchedTerm' = [matchedTerm EXCEPT ![i] = ZeroRow]
            /\ UNCHANGED <<voteGranted, lastLog, logTerm, committed,
                           committedConfig, effectiveConfig,
                           committedMembershipIndex, committedMembershipTerm,
                           effectiveMembershipIndex, effectiveMembershipTerm,
                           messages, crashed, witnessIndex, witnessNodes,
                           witnessConfig, witnessTerm, progressConfig, logConfig>>
       ELSE IF ~granted
       THEN UNCHANGED vars
       ELSE LET grants == voteGranted[i] \union {target}
                won == Quorum(progressConfig[i], grants)
            IN /\ voteGranted' = [voteGranted EXCEPT ![i] = grants]
               /\ voteCommitted' = [voteCommitted EXCEPT ![i] = IF won THEN TRUE ELSE @]
               /\ role' = [role EXCEPT ![i] = IF won THEN "leader" ELSE @]
               /\ UNCHANGED <<currentTerm, voteFor, lastLog, logTerm, committed,
                              matchedIndex, matchedTerm,
                              committedConfig, effectiveConfig,
                              committedMembershipIndex, committedMembershipTerm,
                              effectiveMembershipIndex, effectiveMembershipTerm,
                              messages, crashed, witnessIndex, witnessNodes,
                              witnessConfig, witnessTerm, leaderState, progressConfig, logConfig>>

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
                   leaderState, progressConfig, logConfig>>

\* UPDATE-MAP
\* code: openraft/src/engine/engine_impl.rs:364-389 (follower_commit_entries -> RaftState::update_committed)
\* update: Update!AffectedActions (trace-only direct form of the delivery commit step)
\* Follower commit helper used by trace validation directly.
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
           st == UpdateCommittedF(Local(i), cappedCommit)
       IN AssignLocal(i, st)
    /\ UNCHANGED <<currentTerm, voteFor, voteCommitted, voteGranted,
                   lastLog, logTerm, messages, crashed, leaderState, logConfig>>

\* Engine::update_committed_membership compares committed log ids by term/index
\* and effective membership by index: openraft/src/engine/engine_impl.rs:555-588
\* (unchanged by the update; it does not touch leader progress).
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
          /\ role' = [role EXCEPT
                         ![i] = IF i \in Voters(effectiveConfig'[i])
                                THEN IF role[i] = "learner" THEN "follower" ELSE role[i]
                                ELSE "learner"]
    /\ UNCHANGED <<currentTerm, voteFor, voteCommitted, voteGranted,
                   lastLog, logTerm, committed, matchedIndex, matchedTerm,
                   messages, crashed, witnessIndex, witnessNodes,
                   witnessConfig, witnessTerm, leaderState, progressConfig, logConfig>>

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
                   leaderState, progressConfig, logConfig>>

\* UPDATE-MAP
\* code: openraft/src/core/raft_core.rs:177-205 (restart rebuilds Engine; RaftState.leader is None)
\* update: Update!EnvUpdate (crash/restart summarized in the open focused view)
\* Crash/restart preserves vote/log/membership and clears volatile leader data
\* and commit; commit is reconstructed later by the leader.
Crash(i) ==
    /\ i \notin crashed
    /\ crashed' = crashed \union {i}
    /\ role' = [role EXCEPT ![i] = IF i \in Voters(effectiveConfig[i])
                                     THEN "follower" ELSE "learner"]
    /\ committed' = [committed EXCEPT ![i] = Nil]
    /\ voteGranted' = [voteGranted EXCEPT ![i] = {}]
    /\ matchedIndex' = [matchedIndex EXCEPT ![i] = NilRow]
    /\ matchedTerm' = [matchedTerm EXCEPT ![i] = ZeroRow]
    /\ witnessIndex' = [witnessIndex EXCEPT ![i] = Nil]
    /\ witnessNodes' = [witnessNodes EXCEPT ![i] = {}]
    /\ witnessConfig' = [witnessConfig EXCEPT ![i] = effectiveConfig[i]]
    /\ witnessTerm' = [witnessTerm EXCEPT ![i] = 0]
    /\ leaderState' = [leaderState EXCEPT ![i] = FALSE]
    /\ UNCHANGED <<currentTerm, voteFor, voteCommitted, lastLog, logTerm,
                   committedConfig, effectiveConfig,
                   committedMembershipIndex, committedMembershipTerm,
                   effectiveMembershipIndex, effectiveMembershipTerm, messages,
                   progressConfig, logConfig>>

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
                   leaderState, progressConfig, logConfig>>

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

\* REQ-EVIDENCE TypeOK
\* intent:   Every state variable stays inside its declared domain, and every committed, effective and leader-progress membership config is a non-empty set of non-empty node groups.
\* status:   model-internal
\* watch:    none
\* verified: base
\* review:   ok
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
    /\ leaderState \in [Server -> BOOLEAN]
    /\ progressConfig \in [Server -> SUBSET (SUBSET Server)]
    /\ \A i \in Server: ConfigOK(progressConfig[i])
    /\ logConfig \in [Server -> [0..MaxIndex -> SUBSET (SUBSET Server)]]

\* REQ-EVIDENCE ElectionSafety
\* intent:   Two nodes that are both leaders in the same term hold a vote for the same node.
\* status:   unknown
\* evidence: impl source/openraft/src/engine/engine_impl.rs:214 "let quorum_granted = leader.is_granted_by(&self.state.membership_state.effective);"
\* evidence: impl source/openraft/src/leader/leader.rs:41 "em.is_quorum(self.vote_granted_by.iter())"
\* evidence: impl source/openraft/src/engine/engine_impl.rs:814 "if vote >= &self.state.vote {"
\* evidence: impl source/openraft/src/vote/vote.rs:8 "#[derive(Debug, Clone, Copy, Default, PartialOrd, Ord, PartialEq, Eq)]"
\* watch:    source/openraft/src/engine/engine_impl.rs:Engine::internal_handle_vote_req; source/openraft/src/engine/engine_impl.rs:Engine::handle_vote_resp; source/openraft/src/engine/engine_impl.rs:Engine::elect; source/openraft/src/vote/vote.rs:Vote; source/openraft/src/vote/leader_id.rs:LeaderId; source/openraft/src/leader/leader.rs:Leader::is_granted_by
\* verified: base
\* note:     source/raft-essentials.md:25 restates the Raft rule "Raft ensures that there is at most one leader in a given term" (§5.1, and :54 one vote per term, §5.2) but was not counted as a requirement of this system: a68a9a9 (message) says "in a `term`, it allows to elect more than one leader" and "A node is able to grant more than one vote within one term"; source/openraft/src/vote/leader_id.rs:7-11 calls per-term uniqueness the raft-spec rule and says a leader "is actually identified by `(term, node_id)`"; the older rule "Two committed votes have to be the same" (58f2491:openraft/src/vote/vote.rs:80) was deleted by a68a9a9; searched source/ for "at most one leader", "one leader", "same term", "two leader", "brain split", "split brain", and traced the history of vote/leader_id.rs and vote/vote.rs with tools/hist.sh (blame, log -S"dirty and stupid", show a68a9a9 and 58f2491); source/guide/src/cluster-controls.md:13 and source/openraft/tests/fixtures/mod.rs:724 speak of one leader in a cluster, not per term, and were not counted.
\* review:   Dropped "so a term never has two different leaders" from the intent because the formula only compares the two leaders' votes and does not check that consequence by itself; status unknown kept, since all evidence is impl and the note's non-impl sources were rightly not counted.
ElectionSafety ==
    \A i, j \in Server:
        /\ role[i] = "leader"
        /\ role[j] = "leader"
        /\ currentTerm[i] = currentTerm[j]
        => voteFor[i] = voteFor[j]

\* REQ-EVIDENCE ActiveLeaderHasCommittedVote
\* intent:   A node in the leader role always holds a committed vote, i.e. a vote that a quorum has granted.
\* status:   requirement
\* evidence: contract source/openraft/src/vote/vote.rs:59 "committed vote is seen(granted by a quorum) the voted node id is a valid leader" -> only a quorum-granted (committed) vote makes its holder a leader
\* evidence: comment source/openraft/src/leader/leader.rs:11 "A leader without commit vote is a Candidate in original raft." -> without a committed vote the node is not a leader
\* evidence: comment source/openraft/src/raft_state.rs:34 "is able to propose new log if its vote is granted by" -> leader privileges depend on a quorum-granted vote
\* evidence: history 58f2491 (message) "A Leader has a `Vote` that is committed" -> a leader holds a committed vote
\* evidence: history f882e11 (message) "the `vote` should be committed before entering leader state" -> the vote is committed before the node enters the leader role
\* evidence: test source/openraft/src/engine/handle_vote_resp_test.rs:233 test_handle_vote_resp "assert_eq!(Vote::new_committed(2, 1), eng.state.vote);" -> when a quorum grants the vote the node holds a committed vote as it becomes leader
\* evidence: test source/openraft/src/engine/elect_test.rs:47 test_elect "assert_eq!(Vote::new_committed(1, 1), eng.state.vote);" -> a single-node election commits the vote together with entering leader state
\* evidence: impl source/openraft/src/engine/engine_impl.rs:897 "self.state.vote.node_id == self.id && self.state.vote.committed"
\* evidence: impl source/openraft/src/core/leader_state.rs:72 "debug_assert!(self.core.engine.state.vote.committed);"
\* watch:    source/openraft/src/engine/engine_impl.rs:Engine::elect; source/openraft/src/engine/engine_impl.rs:Engine::handle_vote_resp; source/openraft/src/engine/engine_impl.rs:Engine::is_leader; source/openraft/src/engine/engine_impl.rs:Engine::set_server_state; source/openraft/src/vote/vote.rs:Vote::commit; source/openraft/src/core/leader_state.rs:LeaderState::run; source/openraft/src/core/raft_core.rs:RaftCore::do_main
\* verified: base
\* review:   ok
ActiveLeaderHasCommittedVote ==
    \A i \in Server: role[i] = "leader" => voteCommitted[i]

\* REQ-EVIDENCE CommitWithinLocalLog
\* intent:   A node's commit index never points past the last entry of its own log.
\* status:   requirement
\* evidence: comment source/openraft/src/engine/engine_impl.rs:356 "Committed index can not > last_log_id.index" -> the commit index never exceeds the last local log index
\* evidence: doc source/guide/src/replication.md:74 "and must point to a log entry that is consistent to the leader." -> the commit index must refer to an entry the node holds
\* evidence: doc source/change-log.md:364 "and must point to a log entry that is consistent to leader." -> same rule, recorded with the fix 9540c904
\* evidence: doc source/raft-essentials.md:98 "set commitIndex to min(leaderCommit, index of last new entry)" -> a follower caps its commit index at its last new entry
\* evidence: history 2eaab71:openraft/src/core/append_entries.rs:56 "commit-index must not advance the last known consistent log" -> the commit index must not move past the locally held consistent log
\* evidence: test source/openraft/src/engine/follower_commit_entries_test.rs:140 test_follower_commit_entries_gt_last_entry "assert_eq!(Some(log_id(2, 3)), eng.state.committed);" -> a leader commit beyond the last received entry is capped at that entry
\* evidence: impl source/openraft/src/engine/engine_impl.rs:359 "let committed = std::cmp::min(leader_committed, last);"
\* watch:    source/openraft/src/engine/engine_impl.rs:Engine::follower_commit_entries; source/openraft/src/engine/engine_impl.rs:Engine::truncate_logs; source/openraft/src/engine/engine_impl.rs:Engine::fast_commit; source/openraft/src/core/replication.rs:LeaderState::calc_commit_log_id; source/openraft/src/core/replication.rs:LeaderState::get_match_log_ids; source/openraft/src/core/raft_core.rs:RaftCore::do_main
\* verified: base
\* note:     the guide, change-log and raft-essentials quotes are stated for a follower handling append-entries; engine_impl.rs:356 states the cap without naming a role; no quote states it separately for the leader.
\* review:   ok
CommitWithinLocalLog ==
    \A i \in Server: committed[i] <= lastLog[i]

\* REQ-EVIDENCE CommittedLogAgreement
\* intent:   Any two nodes hold entries of the same term at every log index up to the smaller of their two commit indexes.
\* status:   requirement
\* evidence: comment source/openraft/src/membership/membership_state.rs:16 "A committed log must be consistent with the leader." -> every node's committed entries equal the leader's entries
\* evidence: doc source/guide/src/replication.md:10 "This way it guarantees committed log can always been seen by next leader." -> committed entries are always present in the next leader's log
\* evidence: doc source/raft-essentials.md:84 "(which will only ever happen to uncommitted log entries)" -> a committed entry is never overwritten on a follower
\* evidence: comment source/openraft/src/raft_state.rs:78 "It assumes a committed log will always be chosen, according to raft spec." -> a committed entry is always the entry chosen at its index
\* evidence: doc source/derived-from-async-raft.md:8 "deleting entries after prev-log-id causes committed entry to be lost" -> losing a committed entry while handling append-entries is treated as a bug
\* evidence: comment source/openraft/src/engine/engine_impl.rs:334 "Otherwise the log id with max index makes committed entry invisible in election." -> conflicting entries are truncated so committed entries stay visible to the next leader
\* evidence: impl source/openraft/src/engine/engine_impl.rs:312 "if !self.state.has_log_id(prev) {"
\* evidence: impl source/openraft/src/engine/engine_impl.rs:455 "committed membership can not conflict with the leader"
\* watch:    source/openraft/src/engine/engine_impl.rs:Engine::handle_append_entries_req; source/openraft/src/engine/engine_impl.rs:Engine::truncate_logs; source/openraft/src/engine/engine_impl.rs:Engine::first_conflicting_index; source/openraft/src/engine/engine_impl.rs:Engine::follower_do_append_entries; source/openraft/src/engine/engine_impl.rs:Engine::internal_handle_vote_req; source/openraft/src/raft_state.rs:RaftState::has_log_id; source/openraft/src/core/replication.rs:LeaderState::get_match_log_ids
\* verified: base
\* note:     no quote states pairwise agreement between two non-leaders directly; it follows from the quotes that each node's committed entries match the leader's and survive into later leaders' logs.
\* review:   Narrowed the arrows of guide/src/replication.md:10, raft_state.rs:78 and derived-from-async-raft.md:8 to what their quotes literally say (the old arrows added "unchanged into every later leader", "every node keeps" and "or replacing"); intent and status unchanged.
CommittedLogAgreement ==
    \A i, j \in Server:
      \A idx \in 0..IMin(committed[i], committed[j]):
          logTerm[i][idx] = logTerm[j][idx]

\* SUPERSEDED in V1: this V0 definition reads matchedIndex/matchedTerm as a
\* persistent per-target record. In the updated revision those rows are the
\* Engine-owned leader progress, recreated by every election (raft_state.rs:116-118)
\* and re-keyed by upgrade_quorum_set (progress/mod.rs:222-232). It is kept only
\* for divergence evidence and is not enabled by any V1 cfg; the revised
\* property is Update!CommitWitnessSound_new (see spec/invariant-evidence.json).
\* REQ-EVIDENCE CommitWitnessSound
\* intent:   Once a node has recorded the point its commit index last advanced to, that point stays at or below its commit index, its log still holds the committing term's entry there, and a quorum of the membership used for that commit has matched positions reaching it in that term.
\* status:   mixed
\* evidence: comment source/openraft/src/raft_state.rs:45 "a quorum of the cluster and it is of the term of the leader" -> a commit point is an entry of the leader's term replicated on a quorum
\* evidence: comment source/openraft/src/core/replication.rs:209 "Mismatching term can not prevent other replica with higher term log from being chosen" -> replicas matched at another term do not count toward a commit
\* evidence: history 1451f96:async-raft/src/core/replication.rs:286 "only log entries from the leader’s current term are committed" -> only entries of the leader's current term are committed by counting replicas
\* evidence: doc source/raft-essentials.md:106 "entry commitment) requires separate majorities from both the old and new configurations" -> the quorum is a joint quorum of every config in the membership
\* evidence: doc source/raft-essentials.md:103 "uses the latest configuration in its log, regardless of whether the entry is committed" -> the membership used for the commit is the node's latest (effective) one
\* evidence: doc source/raft-essentials.md:8 "has replicated it on a majority of the servers." -> a committed entry is replicated on a majority
\* evidence: history 1451f96:async-raft/src/core/replication.rs:285 "The output of this function will never be less than this value." -> the leader's commit index never falls below its previous value
\* evidence: doc source/openraft/src/progress/mod.rs:4 "The scalar value is monotonically incremental. Decreasing it is not allowed." -> matched positions that formed the quorum do not move back
\* evidence: history 9915089 (message) "This field can only be updated monotonically." -> a replica's matched position only grows
\* evidence: doc source/raft-essentials.md:79 "a leader never overwrites or deletes entries in its own log." -> the committed entry stays in the leader's log with its term
\* evidence: doc source/raft-essentials.md:84 "(which will only ever happen to uncommitted log entries)" -> a committed entry is not overwritten after the node stops leading
\* evidence: impl source/openraft/src/core/replication.rs:213 "if log_id.leader_id == self.core.engine.state.vote.leader_id() {"
\* evidence: impl source/openraft/src/core/replication.rs:187 "greatest_majority_value(&repl_indexes);"
\* evidence: impl source/openraft/src/core/replication.rs:190 "std::cmp::max(committed.cloned(), self.core.engine.state.committed)"
\* evidence: impl source/openraft/src/core/replication.rs:126 "assert!(Some(matched) >= state.matched,"
\* watch:    source/openraft/src/core/replication.rs:LeaderState::handle_update_matched; source/openraft/src/core/replication.rs:LeaderState::calc_commit_log_id; source/openraft/src/core/replication.rs:LeaderState::get_match_log_ids; source/openraft/src/membership/membership.rs:Membership::greatest_majority_value; source/openraft/src/quorum/joint.rs:Joint::is_quorum; source/openraft/src/quorum/quorum_set_impl.rs:QuorumSet::is_quorum; source/openraft/src/progress/mod.rs:VecProgress::update; source/openraft/src/engine/engine_impl.rs:Engine::fast_commit; source/openraft/src/engine/engine_impl.rs:Engine::leader_append_entries
\* verified: base
\* clause quorum-support: requirement — Quorum(witnessConfig, witnessNodes) with every witness node's matchedIndex at or beyond the point; raft_state.rs:45, replication.rs:209-211, raft-essentials.md:8/103/106 and 1451f96:async-raft/src/core/replication.rs:286 state the joint-quorum, current-term commit rule; progress/mod.rs:4 and 9915089 state that matched positions only grow
\* clause matched-term-kept: unknown — every witness node's matchedTerm still equals witnessTerm; the commit-rule quotes require the leader's term only when a commit is counted, progress/mod.rs:4 and 9915089 only forbid a matched position from moving back, and no quote states that it keeps the committing term afterwards; only impl (replication.rs:213) relates matched terms to the leader's term
\* clause entry-retained: requirement — witnessIndex <= lastLog and witnessTerm equals the local entry's term; raft-essentials.md:79 and :84 state that committed entries are never overwritten or deleted
\* clause commit-not-below-witness: requirement — witnessIndex <= committed; only 1451f96:async-raft/src/core/replication.rs:285, a doc line deleted in 0135e3b, states that the leader's commit never falls below its previous value; at base the rule survives only as code (replication.rs:190, engine_impl.rs:363)
\* clause witness-bookkeeping: model-internal — the witnessIndex = Nil disjunct and the witness* records are observer state with no source counterpart
\* note:     searched source/ for "monoton", "never decrease", "must not decrease", "can not decrease", "go backward"; searched history with tools/hist.sh log -S on "Mismatching term", "matched.term == self.core.current_term", "leader_id == self.core.engine.state.vote.leader_id()", "std::cmp::max(committed.cloned()", "TODO(xp): remove this line" and "the matched increments monotonically"; the deleted async-raft doc (1451f96, removed in 0135e3b) is the only statement found that the leader's commit never decreases; review searched history with tools/hist.sh log -S on "will never be less than this value", "Mismatching term", "matched.term == self.core.current_term" and "monotonically" (replication.rs, replication/mod.rs, progress/mod.rs) and read 3511e43, e2df554, 4a83c76 and 0135e3b: none states that a matched position keeps the term it had when the commit was counted.
\* review:   Split the matchedTerm = witnessTerm conjunct out of clause quorum-support into a new clause matched-term-kept (unknown), because the cited quotes only forbid matched positions from moving back and none says they keep the committing term; intent, block status and the other clauses unchanged.
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

\* REQ-EVIDENCE MembershipOrder
\* intent:   On every node, the log index of the committed membership is never greater than the log index of the effective membership.
\* status:   requirement
\* evidence: doc source/guide/src/effective-membership.md:5 "membership is always the last present one found in log." -> the effective membership is the latest membership entry in the log
\* evidence: comment source/openraft/src/membership/membership_state.rs:9 "The first(committed) one must have been committed" -> the committed membership is the earlier of the two tracked entries
\* evidence: comment source/openraft/src/membership/membership_state.rs:11 "The second(effective) may be committed or not." -> the effective membership is the later of the two tracked entries
\* evidence: comment source/openraft/src/membership/membership_state.rs:18 "(3) By raft design, the last membership takes effect." -> effective means the last membership entry
\* evidence: history 3fd1d8a (message) "the `last()` is the effective one but may not be committed." -> the effective entry is the last of the pair
\* evidence: test source/openraft/src/engine/update_committed_membership_test.rs:86 test_update_committed_membership_at_index_2 "effective: Arc::new(EffectiveMembership::new(Some(log_id(2, 3)), m23()))" -> an older committed membership does not replace a later effective one
\* evidence: impl source/openraft/src/engine/engine_impl.rs:558 "if effective.log_id.index() <= m.log_id.index() {"
\* evidence: impl source/openraft/src/engine/engine_impl.rs:455 "committed membership can not conflict with the leader"
\* watch:    source/openraft/src/engine/engine_impl.rs:Engine::update_committed_membership; source/openraft/src/engine/engine_impl.rs:Engine::truncate_logs; source/openraft/src/engine/engine_impl.rs:Engine::update_membership_state; source/openraft/src/engine/engine_impl.rs:Engine::follower_commit_entries; source/openraft/src/engine/engine_impl.rs:Engine::leader_append_entries; source/openraft/src/core/replication.rs:LeaderState::handle_update_matched; source/openraft/src/storage/helper.rs:StorageHelper::get_membership; source/openraft/src/membership/membership_state.rs:MembershipState
\* verified: base
\* note:     the quotes order the two entries by position in the log ("first"/"second", "last"); none states the index comparison literally; source/guide/src/effective-membership.md:18 "The second last membership log has to be committed." was not counted: it says which membership entry is committed, not where the committed record sits relative to the effective one.
\* review:   Removed the evidence line guide/src/effective-membership.md:18, whose quote says the second-last membership entry is committed but not that the committed record is that entry (as its arrow claimed), and adjusted the note accordingly; intent and status unchanged.
MembershipOrder ==
    \A i \in Server:
        committedMembershipIndex[i] <= effectiveMembershipIndex[i]

\* REQ-EVIDENCE OneOutstandingMembership
\* intent:   While a node's effective membership entry lies beyond its commit index, the membership it records as committed is a strictly earlier entry.
\* status:   requirement
\* evidence: comment source/openraft/src/membership/membership_state.rs:9 "The first(committed) one must have been committed" -> the entry recorded as committed must be a committed entry, the first (earlier) of the two tracked, so never the uncommitted one
\* evidence: history 7f34793 (message) "check if a membership is committed by comparing the log index and its committed index" -> a membership entry counts as committed only once the commit index reaches its log index
\* evidence: impl source/openraft/src/core/admin.rs:137 "The last membership config is not committed yet."
\* evidence: impl source/openraft/src/core/admin.rs:139 "self.core.engine.state.committed < self.core.engine.state.membership_state.effective.log_id"
\* evidence: impl source/openraft/src/core/replication.rs:150 "if st.committed >= st.membership_state.effective.log_id {"
\* evidence: impl source/openraft/src/engine/engine_impl.rs:370 "if self.state.committed >= self.state.membership_state.effective.log_id {"
\* watch:    source/openraft/src/core/admin.rs:LeaderState::has_pending_config; source/openraft/src/core/admin.rs:LeaderState::change_membership; source/openraft/src/core/replication.rs:LeaderState::handle_update_matched; source/openraft/src/engine/engine_impl.rs:Engine::follower_commit_entries; source/openraft/src/engine/engine_impl.rs:Engine::leader_append_entries; source/openraft/src/engine/engine_impl.rs:Engine::update_committed_membership; source/openraft/src/storage/helper.rs:StorageHelper::get_membership; source/openraft/src/core/raft_core.rs:RaftCore::do_main
\* verified: base
\* note:     the comments and guides use "committed" for a membership entry committed in the cluster; 7f34793 (message) is the only quote that ties it to the node's own commit index; source/openraft/src/raft_state.rs:49 says the commit index "is volatile and will not be persisted", and no quote says how the committed-membership record relates to the commit index after a restart; source/openraft/src/membership/membership_state.rs:14, source/openraft/src/storage/helper.rs:98, source/guide/src/effective-membership.md:13, source/guide/src/dynamic-membership.md:134, source/openraft/src/engine/engine_impl.rs:237 and source/openraft/src/error.rs:372 were not counted: they state that at most one membership entry is uncommitted and that a new one may be proposed only after the previous one commits, not which entry a node records as committed relative to its commit index; source/openraft/src/core/admin.rs:137 restates the condition computed on admin.rs:139 and is counted as impl.
\* review:   Removed six evidence lines (membership_state.rs:14, helper.rs:98, effective-membership.md:13, dynamic-membership.md:134, engine_impl.rs:237, error.rs:372) whose quotes support the propose-after-commit / at-most-one-outstanding rule rather than the checked relation between the committed record, the effective entry and the commit index, retyped the narrating comment admin.rs:137 to impl, and stated the earlier-entry part in the membership_state.rs:9 arrow; intent and status unchanged.
OneOutstandingMembership ==
    \A i \in Server:
        effectiveMembershipIndex[i] > committed[i]
        => committedMembershipIndex[i] < effectiveMembershipIndex[i]

\* REQ-EVIDENCE EffectiveIsLastLogMembership
\* intent:   A node's effective membership is the last membership entry present in its own log, or the initial membership with no log position when its log holds no membership entry.
\* status:   requirement
\* evidence: doc source/guide/src/effective-membership.md:5 "the **effective** membership is always the last present one found in log." -> effective = last membership entry in the log
\* evidence: comment source/openraft/src/membership/membership_state.rs:18 "(3) By raft design, the last membership takes effect." -> the last membership entry is effective
\* evidence: comment source/openraft/src/storage/helper.rs:95 "and (2) a membership will take effect at once it is written," -> a membership entry is effective as soon as it is in the log
\* evidence: impl source/openraft/src/engine/engine_impl.rs:671-746 (follower_update_membership, update_membership_state)
\* evidence: impl source/openraft/src/engine/engine_impl.rs:456-485 (truncate_logs reverts to committed)
\* watch:    source/openraft/src/engine/engine_impl.rs:Engine::follower_update_membership; source/openraft/src/engine/engine_impl.rs:Engine::truncate_logs; source/openraft/src/engine/engine_impl.rs:Engine::update_effective_membership; source/openraft/src/engine/engine_impl.rs:Engine::leader_append_entries; source/openraft/src/engine/engine_impl.rs:Engine::update_committed_membership; source/openraft/src/storage/helper.rs:StorageHelper::get_membership
\* verified: update (aa05a38)
\* note:     added in V1 as a structural check of the repaired follower membership path (DeliverAppendEntries/RejectAppendConflict); it reads the per-entry membership payload logConfig, which V0 did not represent. Snapshot-installed memberships (update_committed_membership) are outside the MC Next relation.
EffectiveIsLastLogMembership ==
    \A i \in Server:
        LET ms == {k \in 0..MaxIndex : k <= lastLog[i] /\ logConfig[i][k] # NoCfg}
        IN IF ms = {}
           THEN effectiveMembershipIndex[i] = Nil
           ELSE /\ effectiveMembershipIndex[i] = SetMax(ms)
                /\ effectiveConfig[i] = logConfig[i][SetMax(ms)]

ReachLeader == \E i \in Server: role[i] = "leader"
ReachCommitWitness == \E i \in Server: witnessIndex[i] # Nil
ReachOutstandingMembership ==
    \E i \in Server: effectiveMembershipIndex[i] > committedMembershipIndex[i]
\* V1 reachability predicates for the changed mechanism.
ReachLeaderWithProgressUpgrade ==
    \E i \in Server: leaderState[i] /\ progressConfig[i] # InitialConfig
ReachReelectedLeaderWithOldWitness ==
    \E i \in Server: leaderState[i] /\ witnessIndex[i] # Nil /\ witnessTerm[i] < currentTerm[i]
ReachUnpromotedCoveredMembership ==
    \E i \in Server: /\ effectiveMembershipIndex[i] <= committed[i]
                     /\ committedMembershipIndex[i] < effectiveMembershipIndex[i]

=============================================================================
