---- MODULE E_MONc ----
EXTENDS UpdateProps, TLC
CONSTANTS s1, s2, s3
Old == INSTANCE OldBase
\* source: ../output/final-evidence-oldmon.log state 15 (reached by MCEnterFollowerSync(s3))
S0 == [running |-> (s1 :> TRUE @@ s2 :> TRUE @@ s3 :> TRUE),
       role |-> (s1 :> "LEADING" @@ s2 :> "FOLLOWING" @@ s3 :> "FOLLOWING"),
       phase |-> (s1 :> "BROADCAST" @@ s2 :> "BROADCAST" @@ s3 :> "SYNCHRONIZATION"),
       syncMode |-> (s1 :> "NONE" @@ s2 :> "NONE" @@ s3 :> "NONE"),
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
       syncComplete |-> (s1 :> FALSE @@ s2 :> TRUE @@ s3 :> FALSE),
       learnerStage |-> (s1 :> "NONE" @@ s2 :> "UPTODATE" @@ s3 :> "NONE"),
       dbCleared |-> (s1 :> FALSE @@ s2 :> FALSE @@ s3 :> FALSE),
       prepared |-> (s1 :> <<1>> @@ s2 :> <<1>> @@ s3 :> <<>>),
       syncQueued |-> (s1 :> <<>> @@ s2 :> <<>> @@ s3 :> <<>>),
       leakedQueued |-> (s1 :> <<>> @@ s2 :> <<>> @@ s3 :> <<>>),
       pending |-> (s1 :> <<>> @@ s2 :> <<1>> @@ s3 :> <<>>),
       durable |-> (s1 :> <<1>> @@ s2 :> <<1>> @@ s3 :> <<>>),
       recoveryVisible |-> (s1 :> <<>> @@ s2 :> <<>> @@ s3 :> <<>>),
       committed |-> (s1 :> <<1>> @@ s2 :> <<>> @@ s3 :> <<1>>),
       applied |-> (s1 :> <<>> @@ s2 :> <<>> @@ s3 :> <<>>),
       globalCommitted |-> <<1>>,
       acks |-> <<{s1, s2}, {}>>,
       durabilityEvidence |-> <<{s1, s2}, {}>>,
       commitWitness |-> <<{s1, s2}, {}>>,
       nextTxn |-> 2,
       snapshotBusy |-> (s1 :> FALSE @@ s2 :> FALSE @@ s3 :> FALSE),
       snapshotImage |-> (s1 :> <<>> @@ s2 :> <<>> @@ s3 :> <<>>),
       snapshotPublished |-> (s1 :> <<>> @@ s2 :> <<>> @@ s3 :> <<>>)]
\* successor: state 16 (reached by MCChooseSync(s3,"DIFF"))
S1 == [running |-> (s1 :> TRUE @@ s2 :> TRUE @@ s3 :> TRUE),
       role |-> (s1 :> "LEADING" @@ s2 :> "FOLLOWING" @@ s3 :> "FOLLOWING"),
       phase |-> (s1 :> "BROADCAST" @@ s2 :> "BROADCAST" @@ s3 :> "SYNCHRONIZATION"),
       syncMode |-> (s1 :> "NONE" @@ s2 :> "NONE" @@ s3 :> "DIFF"),
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
       syncComplete |-> (s1 :> FALSE @@ s2 :> TRUE @@ s3 :> FALSE),
       learnerStage |-> (s1 :> "NONE" @@ s2 :> "UPTODATE" @@ s3 :> "UPTODATE"),
       dbCleared |-> (s1 :> FALSE @@ s2 :> FALSE @@ s3 :> FALSE),
       prepared |-> (s1 :> <<1>> @@ s2 :> <<1>> @@ s3 :> <<>>),
       syncQueued |-> (s1 :> <<>> @@ s2 :> <<>> @@ s3 :> <<>>),
       leakedQueued |-> (s1 :> <<>> @@ s2 :> <<>> @@ s3 :> <<>>),
       pending |-> (s1 :> <<>> @@ s2 :> <<1>> @@ s3 :> <<>>),
       durable |-> (s1 :> <<1>> @@ s2 :> <<1>> @@ s3 :> <<>>),
       recoveryVisible |-> (s1 :> <<>> @@ s2 :> <<>> @@ s3 :> <<>>),
       committed |-> (s1 :> <<>> @@ s2 :> <<>> @@ s3 :> <<>>),
       applied |-> (s1 :> <<>> @@ s2 :> <<>> @@ s3 :> <<>>),
       globalCommitted |-> <<1>>,
       acks |-> <<{s1, s2}, {}>>,
       durabilityEvidence |-> <<{s1, s2}, {}>>,
       commitWitness |-> <<{s1, s2}, {}>>,
       nextTxn |-> 2,
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
ENext == /\ running' = S1.running /\ role' = S1.role /\ phase' = S1.phase /\ syncMode' = S1.syncMode /\ leaderOf' = S1.leaderOf /\ acceptedEpoch' = S1.acceptedEpoch /\ currentEpoch' = S1.currentEpoch /\ epochProposal' = S1.epochProposal /\ electionRound' = S1.electionRound /\ votedFor' = S1.votedFor /\ electionVotes' = S1.electionVotes /\ epochAcks' = S1.epochAcks /\ newLeaderAcks' = S1.newLeaderAcks /\ newLeaderReady' = S1.newLeaderReady /\ syncComplete' = S1.syncComplete /\ learnerStage' = S1.learnerStage /\ dbCleared' = S1.dbCleared /\ prepared' = S1.prepared /\ syncQueued' = S1.syncQueued /\ leakedQueued' = S1.leakedQueued /\ pending' = S1.pending /\ durable' = S1.durable /\ recoveryVisible' = S1.recoveryVisible /\ committed' = S1.committed /\ applied' = S1.applied /\ globalCommitted' = S1.globalCommitted /\ acks' = S1.acks /\ durabilityEvidence' = S1.durabilityEvidence /\ commitWitness' = S1.commitWitness /\ nextTxn' = S1.nextTxn /\ snapshotBusy' = S1.snapshotBusy /\ snapshotImage' = S1.snapshotImage /\ snapshotPublished' = S1.snapshotPublished
         /\ PrintT(<<"E_MONc", <<"new_MonotoneStepUpd_retraction_without_recovery", MonotoneStepUpd>>>>)
ESpec == EInit /\ [][ENext]_vars
====
