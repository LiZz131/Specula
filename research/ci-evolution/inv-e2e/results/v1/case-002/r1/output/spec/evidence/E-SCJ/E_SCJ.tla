---- MODULE E_SCJ ----
(* follower s2 in broadcast with syncJustified but no NEWLEADER ACK *)
EXTENDS UpdateProps
CONSTANTS s1, s2, s3, t1, t2
Old == INSTANCE OldBase WITH recovered <- applied
H == <<EntryFor(t1, 1)>>
EvInit ==
    /\ up = [s \in Server |-> TRUE]
    /\ role = [s \in Server |-> IF s = s1 THEN "leading" ELSE IF s = s2 THEN "following" ELSE "looking"]
    /\ phase = [s \in Server |-> IF s \in {s1, s2} THEN "broadcast" ELSE "election"]
    /\ leaderOf = [s \in Server |-> IF s \in {s1, s2} THEN s1 ELSE Nil]
    /\ acceptedEpoch = [s \in Server |-> 1]
    /\ currentEpoch = [s \in Server |-> 1]
    /\ votes = [s \in Server |-> {s}]
    /\ leadersByEpoch = [e \in Epoch |-> IF e = 1 THEN {s1} ELSE {}]
    /\ proposed = [s \in Server |-> H]
    /\ queued = [s \in Server |-> H]
    /\ appended = [s \in Server |-> H]
    /\ durable = [s \in Server |-> H]
    /\ committed = [s \in Server |-> H]
    /\ applied = [s \in Server |-> H]
    /\ snapshot = [s \in Server |-> <<>>]
    /\ acked = [t \in Txn |-> Server]
    /\ commitCertified = [t \in Txn |-> t \in TxnIds(H)]
    /\ messages = {}
    /\ syncMode = [s \in Server |-> "NONE"]
    /\ syncSource = [s \in Server |-> Nil]
    /\ syncJustified = [s \in Server |-> s = s2]
    /\ usedTxn = TxnIds(H)
    /\ rollbackAuthorized = [s \in Server |-> FALSE]
    /\ epochSet = [s \in Server |-> s \in {s1, s2}]
    /\ syncBuf = [s \in Server |-> <<>>]
    /\ syncCommits = [s \in Server |-> <<>>]
    /\ syncStarted = [s \in Server |-> FALSE]
    /\ pending = [s \in Server |-> <<>>]
    /\ nlAckSent = [s \in Server |-> FALSE]
    /\ nlAcks = [s \in Server |-> {}]
    /\ zkState = [s \in Server |-> IF s \in {s1, s2} THEN "RUNNING" ELSE "NONE"]
EvNext == UNCHANGED allVars
EvSpec == EvInit /\ [][EvNext]_allVars
Report == PrintT(<<"E-SCJ", <<"SyncCompletionJustified", Old!SyncCompletionJustified, SyncCompletionJustified>>>>)
====
