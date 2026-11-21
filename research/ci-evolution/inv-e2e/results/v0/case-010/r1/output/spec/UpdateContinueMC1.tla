---- MODULE UpdateContinueMC1 ----
(* Continuation of the MC-1 final-model witness: INIT is the reachable final state
   (state 55) of output/counterexamples/MC-1-witness-deterministic-commit-final.log,
   with the Txn-indexed maps extended by an empty entry for record 3. *)
EXTENDS Update
CONSTANTS s1, s2, s3

ContinueInit ==
    /\ acceptedEpoch = (s1 :> 1 @@ s2 :> 1 @@ s3 :> 0)
    /\ acks = <<{s1, s2}, {s1, s2}, {}>>
    /\ applied = (s1 :> <<1>> @@ s2 :> <<>> @@ s3 :> <<>>)
    /\ commitWitness = <<{s1, s2}, {s1, s2}, {}>>
    /\ committed = (s1 :> <<1, 2>> @@ s2 :> <<>> @@ s3 :> <<>>)
    /\ counters = [snapshots |-> 0, rounds |-> 0, crashes |-> 0, exits |-> 2]
    /\ currentEpoch = (s1 :> 1 @@ s2 :> 1 @@ s3 :> 0)
    /\ durabilityEvidence = <<{s1, s2}, {s1, s2}, {}>>
    /\ durable = (s1 :> <<1, 2>> @@ s2 :> <<1>> @@ s3 :> <<>>)
    /\ electionRound = 0
    /\ electionVotes = (s1 :> {s1, s2, s3} @@ s2 :> {} @@ s3 :> {})
    /\ epochAcks = (s1 :> {s1, s2} @@ s2 :> {} @@ s3 :> {})
    /\ epochProposal = (s1 :> 1 @@ s2 :> 1 @@ s3 :> 0)
    /\ globalCommitted = <<1, 2>>
    /\ leaderOf = (s1 :> s1 @@ s2 :> NoServer @@ s3 :> s1)
    /\ logPos = (s1 :> 2 @@ s2 :> 0 @@ s3 :> 0)
    /\ memDb = (s1 :> <<1>> @@ s2 :> <<1, 2>> @@ s3 :> <<>>)
    /\ memInit = (s1 :> TRUE @@ s2 :> TRUE @@ s3 :> TRUE)
    /\ newLeaderAcks = (s1 :> {s1, s2} @@ s2 :> {} @@ s3 :> {})
    /\ newLeaderReady = (s1 :> TRUE @@ s2 :> FALSE @@ s3 :> FALSE)
    /\ nextTxn = 3
    /\ pending = (s1 :> <<>> @@ s2 :> <<>> @@ s3 :> <<>>)
    /\ phase = (s1 :> "BROADCAST" @@ s2 :> "SYNCHRONIZATION" @@ s3 :> "ELECTION")
    /\ prepared = (s1 :> <<1, 2>> @@ s2 :> <<>> @@ s3 :> <<>>)
    /\ role = (s1 :> "LEADING" @@ s2 :> "LOOKING" @@ s3 :> "FOLLOWING")
    /\ running = (s1 :> TRUE @@ s2 :> TRUE @@ s3 :> TRUE)
    /\ seen = {}
    /\ snapZ = (s1 :> 0 @@ s2 :> 0 @@ s3 :> 0)
    /\ snapshotBusy = (s1 :> FALSE @@ s2 :> FALSE @@ s3 :> FALSE)
    /\ snapshotImage = (s1 :> <<>> @@ s2 :> <<>> @@ s3 :> <<>>)
    /\ snapshotPublished = (s1 :> <<>> @@ s2 :> <<>> @@ s3 :> <<>>)
    /\ syncBuf = (s1 :> <<>> @@ s2 :> <<>> @@ s3 :> <<>>)
    /\ syncCommits = (s1 :> <<>> @@ s2 :> <<>> @@ s3 :> <<>>)
    /\ syncComplete = (s1 :> FALSE @@ s2 :> FALSE @@ s3 :> FALSE)
    /\ syncCut = (s1 :> 0 @@ s2 :> 2 @@ s3 :> 0)
    /\ syncMode = (s1 :> "NONE" @@ s2 :> "TRUNC" @@ s3 :> "NONE")
    /\ syncPos = (s1 :> 0 @@ s2 :> 2 @@ s3 :> 0)
    /\ syncQueued = (s1 :> <<>> @@ s2 :> <<>> @@ s3 :> <<>>)
    /\ syncStage = (s1 :> "IDLE" @@ s2 :> "IDLE" @@ s3 :> "IDLE")
    /\ votedFor = (s1 :> s1 @@ s2 :> NoServer @@ s3 :> s1)

====
