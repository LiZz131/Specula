---- MODULE E3t ----
(* Trace-sourced separating transition for MonotoneUnlessRecovery.            *)
(* Pre-state: replay state before line 62 of traces/repro-trunc-abort-new.ndjson*)
(* (real updated implementation); step: the real reference action             *)
(* ReceiveSyncMode("s0","s2","TRUNC") observed at that line.                   *)
(* Control (Ctl=TRUE): same pre-state, durable[s0] shrinks with no sync step.  *)
EXTENDS base
CONSTANT Ctl
S0 ==
    /\ snapshotImage = [s0 |-> <<>>, s1 |-> <<>>, s2 |-> <<>>]
    /\ syncMode = [s0 |-> "TRUNC", s1 |-> "NONE", s2 |-> "NONE"]
    /\ acks = <<{"s1", "s2"}, {}, {}, {}, {}, {}, {}, {}, {}, {}, {}, {}, {}, {}, {}, {}>>
    /\ globalCommitted = <<1>>
    /\ nextTxn = 2
    /\ prepared = [s0 |-> <<1>>, s1 |-> <<1>>, s2 |-> <<1>>]
    /\ applied = [s0 |-> <<>>, s1 |-> <<1>>, s2 |-> <<1>>]
    /\ newLeaderReady = [s0 |-> FALSE, s1 |-> FALSE, s2 |-> TRUE]
    /\ durable = [s0 |-> <<1>>, s1 |-> <<1>>, s2 |-> <<1>>]
    /\ epochProposal = [s0 |-> 1, s1 |-> 1, s2 |-> 1]
    /\ syncComplete = [s0 |-> FALSE, s1 |-> TRUE, s2 |-> FALSE]
    /\ pending = [s0 |-> <<>>, s1 |-> <<1>>, s2 |-> <<>>]
    /\ acceptedEpoch = [s0 |-> 1, s1 |-> 1, s2 |-> 1]
    /\ role = [s0 |-> "FOLLOWING", s1 |-> "FOLLOWING", s2 |-> "LEADING"]
    /\ logCursor = [s0 |-> 1, s1 |-> 1, s2 |-> 1]
    /\ phase = [s0 |-> "SYNCHRONIZATION", s1 |-> "BROADCAST", s2 |-> "BROADCAST"]
    /\ electionVotes = [s0 |-> {}, s1 |-> {}, s2 |-> {"s0", "s1", "s2"}]
    /\ currentEpoch = [s0 |-> 1, s1 |-> 1, s2 |-> 1]
    /\ votedFor = [s0 |-> "s2", s1 |-> "s2", s2 |-> "s2"]
    /\ running = [s0 |-> TRUE, s1 |-> TRUE, s2 |-> TRUE]
    /\ epochAcks = [s0 |-> {}, s1 |-> {}, s2 |-> {}]
    /\ newLeaderAcks = [s0 |-> {}, s1 |-> {}, s2 |-> {"s0", "s1", "s2"}]
    /\ syncQueued = [s0 |-> <<>>, s1 |-> <<>>, s2 |-> <<>>]
    /\ durabilityEvidence = << {"s0", "s1", "s2"},
       {},
       {},
       {},
       {},
       {},
       {},
       {},
       {},
       {},
       {},
       {},
       {},
       {},
       {},
       {} >>
    /\ leakedQueued = [s0 |-> <<>>, s1 |-> <<>>, s2 |-> <<>>]
    /\ committed = [s0 |-> <<>>, s1 |-> <<1>>, s2 |-> <<1>>]
    /\ snapshotPublished = [s0 |-> <<>>, s1 |-> <<>>, s2 |-> <<>>]
    /\ syncPlan = [ s0 |-> [mode |-> "TRUNC", z |-> 0, cut |-> 1],
      s1 |-> [mode |-> "NONE", z |-> 0, cut |-> 0],
      s2 |-> [mode |-> "NONE", z |-> 0, cut |-> 0] ]
    /\ recoveryVisible = [s0 |-> <<1>>, s1 |-> <<>>, s2 |-> <<>>]
    /\ dbInitialized = [s0 |-> TRUE, s1 |-> TRUE, s2 |-> TRUE]
    /\ electionRound = 0
    /\ learnerStage = [s0 |-> "IDLE", s1 |-> "NEWLEADER", s2 |-> "IDLE"]
    /\ sessionMode = [s0 |-> "NONE", s1 |-> "DIFF", s2 |-> "NONE"]
    /\ syncCommitCut = [s0 |-> 0, s1 |-> 0, s2 |-> 0]
    /\ commitWitness = <<{"s1", "s2"}, {}, {}, {}, {}, {}, {}, {}, {}, {}, {}, {}, {}, {}, {}, {}>>
    /\ leaderOf = [s0 |-> "s2", s1 |-> "s2", s2 |-> "s2"]
    /\ snapshotBusy = [s0 |-> FALSE, s1 |-> FALSE, s2 |-> FALSE]
OldMonotoneStep ==
    \/ \E f \in Server : ~syncComplete[f] /\ syncComplete'[f]
    \/ /\ \A s \in Server : Len(durable'[s]) >= Len(durable[s])
       /\ \A s \in Server : Len(committed'[s]) >= Len(committed[s])
       /\ \A s \in Server : Len(applied'[s]) >= Len(applied[s])
CtlStep == /\ durable' = [durable EXCEPT !["s0"] = <<>>]
           /\ UNCHANGED <<running, role, phase, syncMode, leaderOf, acceptedEpoch, currentEpoch,
                epochProposal, electionRound, votedFor, electionVotes, epochAcks, newLeaderAcks,
                newLeaderReady, syncComplete, prepared, syncQueued, pending, recoveryVisible,
                committed, applied, globalCommitted, acks, durabilityEvidence, commitWitness,
                nextTxn, snapshotBusy, snapshotImage, snapshotPublished, dbInitialized,
                learnerStage, sessionMode, logCursor, leakedQueued, syncCommitCut, syncPlan>>
E3Next == IF Ctl THEN CtlStep ELSE ReceiveSyncMode("s0", "s2", "TRUNC")
E3Spec == S0 /\ [][E3Next]_vars
OldProp == [][OldMonotoneStep]_vars
NewProp == MonotoneUnlessRecovery
====
