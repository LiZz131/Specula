---- MODULE E_A2 ----
(* constructed separating state: active leader s2 (epoch 2) lacks certified t1 *)
EXTENDS UpdateProps
CONSTANTS s1, s2, s3, t1, t2
Old == INSTANCE OldBase WITH recovered <- applied
H == <<EntryFor(t1, 1)>>
EvInit ==
    /\ up = [s \in Server |-> TRUE]
    /\ role = [s \in Server |-> IF s = s2 THEN "leading" ELSE "looking"]
    /\ phase = [s \in Server |-> "election"]
    /\ leaderOf = [s \in Server |-> Nil]
    /\ acceptedEpoch = [s \in Server |-> 2]
    /\ currentEpoch = [s \in Server |-> 2]
    /\ votes = [s \in Server |-> {s}]
    /\ leadersByEpoch = [e \in Epoch |-> IF e = 1 THEN {s1} ELSE IF e = 2 THEN {s2} ELSE {}]
    /\ proposed = [s \in Server |-> IF s = s2 THEN <<>> ELSE H]
    /\ queued = [s \in Server |-> IF s = s2 THEN <<>> ELSE H]
    /\ appended = [s \in Server |-> IF s = s2 THEN <<>> ELSE H]
    /\ durable = [s \in Server |-> IF s = s2 THEN <<>> ELSE H]
    /\ committed = [s \in Server |-> IF s = s2 THEN <<>> ELSE H]
    /\ applied = [s \in Server |-> IF s = s2 THEN <<>> ELSE H]
    /\ snapshot = [s \in Server |-> <<>>]
    /\ acked = [t \in Txn |-> Server]
    /\ commitCertified = [t \in Txn |-> t \in TxnIds(H)]
    /\ messages = {}
    /\ syncMode = [s \in Server |-> "NONE"]
    /\ syncSource = [s \in Server |-> Nil]
    /\ syncJustified = [s \in Server |-> FALSE]
    /\ usedTxn = TxnIds(H)
    /\ rollbackAuthorized = [s \in Server |-> FALSE]
    /\ epochSet = [s \in Server |-> s = s2]
    /\ syncBuf = [s \in Server |-> <<>>]
    /\ syncCommits = [s \in Server |-> <<>>]
    /\ syncStarted = [s \in Server |-> FALSE]
    /\ pending = [s \in Server |-> <<>>]
    /\ nlAckSent = [s \in Server |-> FALSE]
    /\ nlAcks = [s \in Server |-> {}]
    /\ zkState = [s \in Server |-> IF s = s2 THEN "RUNNING" ELSE "NONE"]
EvNext == UNCHANGED allVars
EvSpec == EvInit /\ [][EvNext]_allVars
Report == PrintT(<<"E-A2", <<"-:LeaderCompleteness", "not-checked", LeaderCompleteness>>>>)
====
