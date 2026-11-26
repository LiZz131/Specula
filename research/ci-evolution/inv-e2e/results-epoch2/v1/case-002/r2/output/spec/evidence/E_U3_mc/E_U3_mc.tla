---- MODULE E_U3_mc ----
(* Divergence evidence E_U3_mc: state 23 of output/incr/seed-focused-U1U3.log; edits: none *)
EXTENDS UpdateProps, TLC
CONSTANTS s1, s2, s3, t1
EvInit ==
    /\ rollbackAuthorized = (s1 :> FALSE @@ s2 :> FALSE @@ s3 :> FALSE)
    /\ recovered = (s1 :> <<>> @@ s2 :> <<>> @@ s3 :> <<>>)
    /\ votes = (s1 :> {s1, s2} @@ s2 :> {s2, s3} @@ s3 :> {})
    /\ leadersByEpoch = (0 :> {} @@ 1 :> {s1} @@ 2 :> {s1} @@ 3 :> {s2})
    /\ syncMode = (s1 :> "NONE" @@ s2 :> "NONE" @@ s3 :> "NONE")
    /\ commitCertified = (t1 :> TRUE)
    /\ syncSource = (s1 :> Nil @@ s2 :> Nil @@ s3 :> s2)
    /\ applied = (s1 :> <<[epoch |-> 1, id |-> t1]>> @@ s2 :> <<>> @@ s3 :> <<>>)
    /\ syncPending = (s1 :> <<>> @@ s2 :> <<>> @@ s3 :> <<>>)
    /\ durable = (s1 :> <<[epoch |-> 1, id |-> t1]>> @@ s2 :> <<>> @@ s3 :> <<>>)
    /\ acked = (t1 :> {})
    /\ usedTxn = {t1}
    /\ everCommitted = {[cepoch |-> 2, entry |-> [epoch |-> 1, id |-> t1]]}
    /\ appended = (s1 :> <<[epoch |-> 1, id |-> t1]>> @@ s2 :> <<>> @@ s3 :> <<>>)
    /\ acceptedEpoch = (s1 :> 2 @@ s2 :> 3 @@ s3 :> 3)
    /\ role = (s1 :> "leading" @@ s2 :> "leading" @@ s3 :> "following")
    /\ syncJustified = (s1 :> FALSE @@ s2 :> FALSE @@ s3 :> TRUE)
    /\ phase = (s1 :> "broadcast" @@ s2 :> "broadcast" @@ s3 :> "sync")
    /\ snapshot = (s1 :> <<>> @@ s2 :> <<>> @@ s3 :> <<>>)
    /\ currentEpoch = (s1 :> 2 @@ s2 :> 3 @@ s3 :> 3)
    /\ queued = (s1 :> <<[epoch |-> 1, id |-> t1]>> @@ s2 :> <<>> @@ s3 :> <<>>)
    /\ proposed = (s1 :> <<[epoch |-> 1, id |-> t1]>> @@ s2 :> <<>> @@ s3 :> <<>>)
    /\ committed = (s1 :> <<[epoch |-> 1, id |-> t1]>> @@ s2 :> <<>> @@ s3 :> <<>>)
    /\ up = (s1 :> TRUE @@ s2 :> TRUE @@ s3 :> TRUE)
    /\ learnerStage = (s1 :> "idle" @@ s2 :> "idle" @@ s3 :> "acked")
    /\ messages = { [epoch |-> 1, id |-> t1, kind |-> "proposal", from |-> s1, to |-> s2],
      [epoch |-> 1, id |-> t1, kind |-> "proposal", from |-> s1, to |-> s3] }
    /\ leaderOf = (s1 :> s1 @@ s2 :> s2 @@ s3 :> s2)
    /\ nlAcks = (s1 :> {s2} @@ s2 :> {s3} @@ s3 :> {})
EvSpec == EvInit /\ [][UNCHANGED allVars]_allVars
====
