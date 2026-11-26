---- MODULE E_U1_old ----
(* Divergence evidence E_U1_old: state 10 of output/incr/seed-oldcontrol-U1.log; edits: none *)
EXTENDS UpdateProps, TLC
CONSTANTS s1, s2, s3, t1
EvInit ==
    /\ rollbackAuthorized = (s1 :> FALSE @@ s2 :> FALSE @@ s3 :> FALSE)
    /\ recovered = (s1 :> <<>> @@ s2 :> <<>> @@ s3 :> <<>>)
    /\ votes = (s1 :> {s1, s2} @@ s2 :> {s2} @@ s3 :> {})
    /\ leadersByEpoch = (0 :> {} @@ 1 :> {s1} @@ 2 :> {s1} @@ 3 :> {})
    /\ syncMode = (s1 :> "NONE" @@ s2 :> "DIFF" @@ s3 :> "NONE")
    /\ commitCertified = (t1 :> FALSE)
    /\ syncSource = (s1 :> Nil @@ s2 :> s1 @@ s3 :> Nil)
    /\ applied = (s1 :> <<>> @@ s2 :> <<>> @@ s3 :> <<>>)
    /\ syncPending = (s1 :> <<>> @@ s2 :> <<[epoch |-> 1, id |-> t1]>> @@ s3 :> <<>>)
    /\ durable = (s1 :> <<[epoch |-> 1, id |-> t1]>> @@ s2 :> <<>> @@ s3 :> <<>>)
    /\ acked = (t1 :> {})
    /\ usedTxn = {t1}
    /\ everCommitted = {}
    /\ appended = (s1 :> <<[epoch |-> 1, id |-> t1]>> @@ s2 :> <<>> @@ s3 :> <<>>)
    /\ acceptedEpoch = (s1 :> 2 @@ s2 :> 2 @@ s3 :> 0)
    /\ role = (s1 :> "leading" @@ s2 :> "following" @@ s3 :> "looking")
    /\ syncJustified = (s1 :> FALSE @@ s2 :> TRUE @@ s3 :> FALSE)
    /\ phase = (s1 :> "sync" @@ s2 :> "sync" @@ s3 :> "election")
    /\ snapshot = (s1 :> <<>> @@ s2 :> <<>> @@ s3 :> <<>>)
    /\ currentEpoch = (s1 :> 2 @@ s2 :> 2 @@ s3 :> 0)
    /\ queued = (s1 :> <<[epoch |-> 1, id |-> t1]>> @@ s2 :> <<>> @@ s3 :> <<>>)
    /\ proposed = (s1 :> <<[epoch |-> 1, id |-> t1]>> @@ s2 :> <<>> @@ s3 :> <<>>)
    /\ committed = (s1 :> <<>> @@ s2 :> <<>> @@ s3 :> <<>>)
    /\ up = (s1 :> TRUE @@ s2 :> TRUE @@ s3 :> TRUE)
    /\ learnerStage = (s1 :> "idle" @@ s2 :> "acked" @@ s3 :> "idle")
    /\ messages = { [epoch |-> 1, id |-> t1, kind |-> "proposal", from |-> s1, to |-> s2],
      [epoch |-> 1, id |-> t1, kind |-> "proposal", from |-> s1, to |-> s3] }
    /\ leaderOf = (s1 :> s1 @@ s2 :> s1 @@ s3 :> Nil)
    /\ nlAcks = (s1 :> {s2} @@ s2 :> {} @@ s3 :> {})
EvSpec == EvInit /\ [][UNCHANGED allVars]_allVars
====
