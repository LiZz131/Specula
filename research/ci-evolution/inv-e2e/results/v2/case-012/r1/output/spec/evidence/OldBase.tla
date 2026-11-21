------------------------------ MODULE OldBase ------------------------------
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

\* REQ-EVIDENCE TypeOK
\* intent:   Every state variable stays inside its declared domain, and every committed and effective membership config is a non-empty set of non-empty node groups.
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

ReachLeader == \E i \in Server: role[i] = "leader"
ReachCommitWitness == \E i \in Server: witnessIndex[i] # Nil
ReachOutstandingMembership ==
    \E i \in Server: effectiveMembershipIndex[i] > committedMembershipIndex[i]

=============================================================================
