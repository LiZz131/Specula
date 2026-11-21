------------------------------ MODULE base ------------------------------
EXTENDS Naturals, Integers, FiniteSets, Sequences, TLC

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
    witnessTerm

vars == <<
    currentTerm, voteFor, voteCommitted, role, voteGranted,
    lastLog, logTerm, committed, matchedIndex, matchedTerm,
    committedConfig, effectiveConfig,
    committedMembershipIndex, committedMembershipTerm,
    effectiveMembershipIndex, effectiveMembershipTerm,
    messages, crashed,
    witnessIndex, witnessNodes, witnessConfig, witnessTerm
>>

InitialConfig == {Server}
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

LogUpToDate(candidate, voter) ==
    IF lastLog[voter] = Nil
    THEN TRUE
    ELSE IF lastLog[candidate] = Nil
         THEN FALSE
         ELSE \/ logTerm[candidate][lastLog[candidate]] > logTerm[voter][lastLog[voter]]
              \/ /\ logTerm[candidate][lastLog[candidate]] = logTerm[voter][lastLog[voter]]
                 /\ lastLog[candidate] >= lastLog[voter]

\* Engine::elect increments the vote, self-grants, and uses effective membership:
\* openraft/src/engine/engine_impl.rs:105-137
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
    /\ UNCHANGED <<lastLog, logTerm, committed, matchedIndex, matchedTerm,
                   committedConfig, effectiveConfig,
                   committedMembershipIndex, committedMembershipTerm,
                   effectiveMembershipIndex, effectiveMembershipTerm,
                   messages, crashed, witnessIndex, witnessNodes,
                   witnessConfig, witnessTerm>>

\* Engine::internal_handle_vote_req + handle_vote_resp:
\* openraft/src/engine/engine_impl.rs:797-864,169-227
GrantVote(candidate, voter) ==
    /\ candidate # voter
    /\ candidate \notin crashed
    /\ voter \notin crashed
    /\ role[candidate] = "candidate"
    /\ voter \in Voters(effectiveConfig[candidate])
    /\ LogUpToDate(candidate, voter)
    /\ \/ currentTerm[voter] < currentTerm[candidate]
       \/ /\ currentTerm[voter] = currentTerm[candidate]
          /\ voteFor[voter] = candidate
    /\ LET grants == voteGranted[candidate] \union {voter}
           won == Quorum(effectiveConfig[candidate], grants)
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
    /\ UNCHANGED <<lastLog, logTerm, committed, matchedIndex, matchedTerm,
                   committedConfig, effectiveConfig,
                   committedMembershipIndex, committedMembershipTerm,
                   effectiveMembershipIndex, effectiveMembershipTerm,
                   messages, crashed, witnessIndex, witnessNodes,
                   witnessConfig, witnessTerm>>

AppendTerms(i, oldLast, count) ==
    [k \in 0..MaxIndex |->
        IF k > oldLast /\ k <= oldLast + count
        THEN currentTerm[i]
        ELSE logTerm[i][k]]

\* Engine::leader_append_entries assigns consecutive current-vote log ids,
\* updates effective membership immediately, and applies the self-quorum fast path:
\* openraft/src/engine/engine_impl.rs:232-273,604-623
LeaderAppendEntries(i, count, membershipPosition, newConfig) ==
    /\ i \notin crashed
    /\ count \in 1..(MaxIndex + 1)
    /\ lastLog[i] + count <= MaxIndex
    /\ membershipPosition = Nil
       \/ /\ membershipPosition \in 1..count
          /\ ConfigOK(newConfig)
    /\ LET newLast == lastLog[i] + count
           hasMembership == membershipPosition # Nil
           selectedConfig == IF hasMembership THEN newConfig ELSE effectiveConfig[i]
           selectedMembershipIndex == IF hasMembership
                                      THEN lastLog[i] + membershipPosition
                                      ELSE effectiveMembershipIndex[i]
           selfCommitted == Quorum(selectedConfig, {i})
       IN /\ lastLog' = [lastLog EXCEPT ![i] = newLast]
          /\ logTerm' = [logTerm EXCEPT ![i] = AppendTerms(i, lastLog[i], count)]
          /\ effectiveConfig' = [effectiveConfig EXCEPT ![i] = selectedConfig]
          /\ effectiveMembershipIndex' = [effectiveMembershipIndex EXCEPT
                                             ![i] = selectedMembershipIndex]
          /\ effectiveMembershipTerm' = [effectiveMembershipTerm EXCEPT
                                            ![i] = IF hasMembership
                                                  THEN currentTerm[i] ELSE @]
          /\ committed' = [committed EXCEPT
                              ![i] = IF selfCommitted THEN newLast ELSE @]
          /\ matchedIndex' = [matchedIndex EXCEPT ![i][i] = newLast]
          /\ matchedTerm' = [matchedTerm EXCEPT ![i][i] = currentTerm[i]]
          /\ witnessIndex' = [witnessIndex EXCEPT
                                 ![i] = IF selfCommitted THEN newLast ELSE @]
          /\ witnessNodes' = [witnessNodes EXCEPT
                                 ![i] = IF selfCommitted THEN {i} ELSE @]
          /\ witnessConfig' = [witnessConfig EXCEPT
                                  ![i] = IF selfCommitted THEN selectedConfig ELSE @]
          /\ witnessTerm' = [witnessTerm EXCEPT
                                ![i] = IF selfCommitted THEN currentTerm[i] ELSE @]
    /\ UNCHANGED <<currentTerm, voteFor, voteCommitted, role, voteGranted,
                   committedConfig, committedMembershipIndex,
                   committedMembershipTerm, messages, crashed>>

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
                   crashed, witnessIndex, witnessNodes, witnessConfig, witnessTerm>>

CopyLeaderLog(m) ==
    [k \in 0..MaxIndex |->
        IF k <= m.last THEN logTerm[m.from][k] ELSE logTerm[m.to][k]]

\* Engine::handle_append_entries_req accepts a matching prefix and applies the
\* exact follower commit cap: openraft/src/engine/engine_impl.rs:276-373
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
           promoteMembership == newCommit >= newEffectiveIndex
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
    /\ UNCHANGED <<voteGranted, matchedIndex, matchedTerm, crashed,
                   witnessIndex, witnessNodes, witnessConfig, witnessTerm>>

\* A conflicting prev-log causes truncation at an existing conflict and a
\* negative response; binary-search cursor details stay internal:
\* openraft/src/engine/engine_impl.rs:309-318
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
    /\ UNCHANGED <<voteGranted, committed, matchedIndex, matchedTerm,
                   committedConfig, effectiveConfig,
                   committedMembershipIndex, committedMembershipTerm,
                   effectiveMembershipIndex, effectiveMembershipTerm,
                   crashed, witnessIndex, witnessNodes, witnessConfig, witnessTerm>>

AckedAt(rowIndex, rowTerm, idx, term) ==
    {j \in Server: rowIndex[j] >= idx /\ rowTerm[j] = term}

CommitCandidates(i, rowIndex, rowTerm) ==
    {idx \in 0..lastLog[i]:
        /\ logTerm[i][idx] = currentTerm[i]
        /\ Quorum(effectiveConfig[i],
                  AckedAt(rowIndex, rowTerm, idx, currentTerm[i]))}

GreatestCandidateOrOld(i, rowIndex, rowTerm) ==
    LET candidates == CommitCandidates(i, rowIndex, rowTerm)
    IN IF candidates = {}
       THEN committed[i]
       ELSE CHOOSE idx \in candidates: \A other \in candidates: other <= idx

\* LeaderState::handle_update_matched owns the atomic externally meaningful
\* progress+commit transition: openraft/src/core/replication.rs:97-169
HandleUpdateMatched(m) ==
    /\ m \in messages
    /\ m.type = "ack"
    /\ m.ok
    /\ m.to \notin crashed
    /\ role[m.to] = "leader"
    /\ currentTerm[m.to] = m.term
    /\ m.last >= matchedIndex[m.to][m.from]
    /\ LET nextMatched == [matchedIndex[m.to] EXCEPT ![m.from] = m.last]
           nextMatchedTerm == [matchedTerm[m.to] EXCEPT ![m.from] = m.lastTerm]
           nextCommit == GreatestCandidateOrOld(m.to, nextMatched, nextMatchedTerm)
           advanced == nextCommit > committed[m.to]
           supporters == AckedAt(nextMatched, nextMatchedTerm, nextCommit, currentTerm[m.to])
       IN /\ matchedIndex' = [matchedIndex EXCEPT ![m.to] = nextMatched]
          /\ matchedTerm' = [matchedTerm EXCEPT ![m.to] = nextMatchedTerm]
          /\ committed' = [committed EXCEPT ![m.to] = nextCommit]
          /\ committedConfig' = [committedConfig EXCEPT
                                    ![m.to] = IF nextCommit >= effectiveMembershipIndex[m.to]
                                              THEN effectiveConfig[m.to] ELSE @]
          /\ committedMembershipIndex' = [committedMembershipIndex EXCEPT
                                             ![m.to] = IF nextCommit >= effectiveMembershipIndex[m.to]
                                                       THEN effectiveMembershipIndex[m.to] ELSE @]
          /\ committedMembershipTerm' = [committedMembershipTerm EXCEPT
                                            ![m.to] = IF nextCommit >= effectiveMembershipIndex[m.to]
                                                      THEN effectiveMembershipTerm[m.to] ELSE @]
          /\ witnessIndex' = [witnessIndex EXCEPT
                                 ![m.to] = IF advanced THEN nextCommit ELSE @]
          /\ witnessNodes' = [witnessNodes EXCEPT
                                 ![m.to] = IF advanced THEN supporters ELSE @]
          /\ witnessConfig' = [witnessConfig EXCEPT
                                  ![m.to] = IF advanced THEN effectiveConfig[m.to] ELSE @]
          /\ witnessTerm' = [witnessTerm EXCEPT
                                ![m.to] = IF advanced THEN currentTerm[m.to] ELSE @]
          /\ messages' = messages \ {m}
    /\ UNCHANGED <<currentTerm, voteFor, voteCommitted, role, voteGranted,
                   lastLog, logTerm, effectiveConfig,
                   effectiveMembershipIndex, effectiveMembershipTerm, crashed>>

\* Direct form used to validate VecProgress's externally visible update relation;
\* its sorted-vector layout is deliberately abstracted away:
\* openraft/src/progress/mod.rs:127-225
ProgressUpdateValue(i, target, newValue) ==
    /\ i \in Server
    /\ target \in Server
    /\ newValue \in Index
    /\ newValue >= matchedIndex[i][target]
    /\ LET nextMatched == [matchedIndex[i] EXCEPT ![target] = newValue]
           nextMatchedTerm == [matchedTerm[i] EXCEPT ![target] = currentTerm[i]]
           nextCommit == GreatestCandidateOrOld(i, nextMatched, nextMatchedTerm)
           advanced == nextCommit > committed[i]
           supporters == AckedAt(nextMatched, nextMatchedTerm, nextCommit, currentTerm[i])
       IN /\ matchedIndex' = [matchedIndex EXCEPT ![i] = nextMatched]
          /\ matchedTerm' = [matchedTerm EXCEPT ![i] = nextMatchedTerm]
          /\ committed' = [committed EXCEPT ![i] = nextCommit]
          /\ witnessIndex' = [witnessIndex EXCEPT
                                 ![i] = IF advanced THEN nextCommit ELSE @]
          /\ witnessNodes' = [witnessNodes EXCEPT
                                 ![i] = IF advanced THEN supporters ELSE @]
          /\ witnessConfig' = [witnessConfig EXCEPT
                                  ![i] = IF advanced THEN effectiveConfig[i] ELSE @]
          /\ witnessTerm' = [witnessTerm EXCEPT
                                ![i] = IF advanced THEN currentTerm[i] ELSE @]
    /\ UNCHANGED <<currentTerm, voteFor, voteCommitted, role, voteGranted,
                   lastLog, logTerm, committedConfig, effectiveConfig,
                   committedMembershipIndex, committedMembershipTerm,
                   effectiveMembershipIndex, effectiveMembershipTerm,
                   messages, crashed>>

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
                   crashed, witnessIndex, witnessNodes, witnessConfig, witnessTerm>>

\* Follower commit helper used by trace validation directly:
\* openraft/src/engine/engine_impl.rs:344-373
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
           promote == nextCommit >= effectiveMembershipIndex[i]
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
                   witnessConfig, witnessTerm>>

\* Engine::update_committed_membership compares committed log ids by term/index
\* and effective membership by index: openraft/src/engine/engine_impl.rs:538-573
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
                   witnessConfig, witnessTerm>>

PromoteCommittedMembership(i) ==
    /\ committed[i] >= effectiveMembershipIndex[i]
    /\ committedMembershipIndex[i] < effectiveMembershipIndex[i]
    /\ committedConfig' = [committedConfig EXCEPT ![i] = effectiveConfig[i]]
    /\ committedMembershipIndex' = [committedMembershipIndex EXCEPT
                                       ![i] = effectiveMembershipIndex[i]]
    /\ committedMembershipTerm' = [committedMembershipTerm EXCEPT
                                      ![i] = effectiveMembershipTerm[i]]
    /\ UNCHANGED <<currentTerm, voteFor, voteCommitted, role, voteGranted,
                   lastLog, logTerm, committed, matchedIndex, matchedTerm,
                   effectiveConfig, effectiveMembershipIndex,
                   effectiveMembershipTerm, messages, crashed,
                   witnessIndex, witnessNodes, witnessConfig, witnessTerm>>

\* Message loss occurs outside Engine state. It is bounded in MC only.
LoseMessage(m) ==
    /\ m \in messages
    /\ messages' = messages \ {m}
    /\ UNCHANGED <<currentTerm, voteFor, voteCommitted, role, voteGranted,
                   lastLog, logTerm, committed, matchedIndex, matchedTerm,
                   committedConfig, effectiveConfig,
                   committedMembershipIndex, committedMembershipTerm,
                   effectiveMembershipIndex, effectiveMembershipTerm,
                   crashed, witnessIndex, witnessNodes, witnessConfig, witnessTerm>>

\* Crash/restart preserves vote/log/membership and clears volatile leader data;
\* commit is reconstructed later by the leader: openraft/src/core/raft_core.rs:181-205
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
                   messages, witnessIndex, witnessNodes, witnessConfig, witnessTerm>>

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
