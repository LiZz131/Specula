---- MODULE E_U2b ----
EXTENDS UpdateProps, TLC
CONSTANTS s1, s2, s3
Old == INSTANCE OldBase
\* source: ../output/final-update-hunt-leak-gap.log state 17 (reached by LeakScenarioNext)
S0 == [running |-> (s1 :> TRUE @@ s2 :> TRUE @@ s3 :> TRUE),
       role |-> (s1 :> "LEADING" @@ s2 :> "FOLLOWING" @@ s3 :> "FOLLOWING"),
       phase |-> (s1 :> "BROADCAST" @@ s2 :> "SYNCHRONIZATION" @@ s3 :> "BROADCAST"),
       syncMode |-> (s1 :> "NONE" @@ s2 :> "TRUNC" @@ s3 :> "NONE"),
       leaderOf |-> (s1 :> s1 @@ s2 :> s1 @@ s3 :> s1),
       acceptedEpoch |-> (s1 :> 1 @@ s2 :> 1 @@ s3 :> 1),
       currentEpoch |-> (s1 :> 1 @@ s2 :> 1 @@ s3 :> 1),
       epochProposal |-> (s1 :> 1 @@ s2 :> 1 @@ s3 :> 1),
       electionRound |-> 0,
       votedFor |-> (s1 :> s1 @@ s2 :> s1 @@ s3 :> s1),
       electionVotes |-> (s1 :> {s1, s2, s3} @@ s2 :> {} @@ s3 :> {}),
       epochAcks |-> (s1 :> {s1, s2, s3} @@ s2 :> {} @@ s3 :> {}),
       newLeaderAcks |-> (s1 :> {s1, s2, s3} @@ s2 :> {} @@ s3 :> {}),
       newLeaderReady |-> (s1 :> TRUE @@ s2 :> FALSE @@ s3 :> FALSE),
       syncComplete |-> (s1 :> FALSE @@ s2 :> FALSE @@ s3 :> TRUE),
       learnerStage |-> (s1 :> "NONE" @@ s2 :> "DATA" @@ s3 :> "UPTODATE"),
       dbCleared |-> (s1 :> FALSE @@ s2 :> FALSE @@ s3 :> FALSE),
       prepared |-> (s1 :> <<1, 2>> @@ s2 :> <<>> @@ s3 :> <<>>),
       syncQueued |-> (s1 :> <<2>> @@ s2 :> <<>> @@ s3 :> <<>>),
       leakedQueued |-> (s1 :> <<>> @@ s2 :> <<>> @@ s3 :> <<>>),
       pending |-> (s1 :> <<>> @@ s2 :> <<>> @@ s3 :> <<>>),
       durable |-> (s1 :> <<1>> @@ s2 :> <<2>> @@ s3 :> <<>>),
       recoveryVisible |-> (s1 :> <<>> @@ s2 :> <<>> @@ s3 :> <<>>),
       committed |-> (s1 :> <<1>> @@ s2 :> <<>> @@ s3 :> <<>>),
       applied |-> (s1 :> <<>> @@ s2 :> <<>> @@ s3 :> <<>>),
       globalCommitted |-> <<1>>,
       acks |-> <<{s1, s2}, {}>>,
       durabilityEvidence |-> <<{s1, s2}, {}>>,
       commitWitness |-> <<{s1, s2}, {}>>,
       nextTxn |-> 3,
       snapshotBusy |-> (s1 :> FALSE @@ s2 :> FALSE @@ s3 :> FALSE),
       snapshotImage |-> (s1 :> <<>> @@ s2 :> <<>> @@ s3 :> <<>>),
       snapshotPublished |-> (s1 :> <<>> @@ s2 :> <<>> @@ s3 :> <<>>)]
EInit ==
    /\ running = S0.running
    /\ role = S0.role
    /\ phase = S0.phase
    /\ syncMode = S0.syncMode
    /\ leaderOf = S0.leaderOf
    /\ acceptedEpoch = S0.acceptedEpoch
    /\ currentEpoch = S0.currentEpoch
    /\ epochProposal = S0.epochProposal
    /\ electionRound = S0.electionRound
    /\ votedFor = S0.votedFor
    /\ electionVotes = S0.electionVotes
    /\ epochAcks = S0.epochAcks
    /\ newLeaderAcks = S0.newLeaderAcks
    /\ newLeaderReady = S0.newLeaderReady
    /\ syncComplete = S0.syncComplete
    /\ learnerStage = S0.learnerStage
    /\ dbCleared = S0.dbCleared
    /\ prepared = S0.prepared
    /\ syncQueued = S0.syncQueued
    /\ leakedQueued = S0.leakedQueued
    /\ pending = S0.pending
    /\ durable = S0.durable
    /\ recoveryVisible = S0.recoveryVisible
    /\ committed = S0.committed
    /\ applied = S0.applied
    /\ globalCommitted = S0.globalCommitted
    /\ acks = S0.acks
    /\ durabilityEvidence = S0.durabilityEvidence
    /\ commitWitness = S0.commitWitness
    /\ nextTxn = S0.nextTxn
    /\ snapshotBusy = S0.snapshotBusy
    /\ snapshotImage = S0.snapshotImage
    /\ snapshotPublished = S0.snapshotPublished
    /\ PrintT(<<"E_U2b", <<"new_RecoverableHistoryComplete", RecoverableHistoryComplete>>, <<"old_OrderedHistories", Old!OrderedHistories>>>>)
ENext == UNCHANGED vars
ESpec == EInit /\ [][ENext]_vars
====
