------------------------------ MODULE Probe002 ------------------------------
(* Decision probe for case-002 (v0). State predicates only.                 *)
(* NPE trigger state: learner s has sent its NEWLEADER ACK (syncStage =     *)
(* "nlAcked"), packetsNotCommitted (pnc) is empty, and the next packet in   *)
(* its leader stream is a COMMIT that LearnerCommit can consume now.        *)
EXTENDS Update

NPETrigger(s) ==
    /\ syncStage[s] = "nlAcked"
    /\ pnc[s] = <<>>
    /\ LearnerReading(s) /\ Head(lq[s]).type = "COMMIT"

ProbeNoNPE == ~\E s \in Server : NPETrigger(s)

(* PipelinePrefix snapshot clause, as it stood between [84] and [302]       *)
(* (weaken #1), and the final clause (weaken #2, base.tla:933).            *)
OldSnapClause(s) == \/ IsPrefix(snapshot[s], applied[s])
                    \/ phase[s] = "sync" /\ IsPrefix(snapshot[s], recovered[s])
NewSnapClause(s) == zkState[s] = "running" => IsPrefix(snapshot[s], applied[s])
ProbeOldSnap == \A s \in Server : OldSnapClause(s)
\* States admitted by weaken #2 but rejected by weaken #1.
Admitted(s) == ~OldSnapClause(s) /\ NewSnapClause(s)
\* Admitted state whose extra snapshot entries are not the persisted history:
\* if the snapshot is always a prefix of the forced log (durable), the restart
\* path reloads exactly what was persisted and nothing outside the log is lost
\* or invented.
ProbeAdmittedSnapInLog == \A s \in Server : Admitted(s) => IsPrefix(snapshot[s], durable[s])
\* Admitted state whose snapshot holds an entry that was never committed anywhere.
ProbeAdmittedOnlyCommitted == \A s \in Server : Admitted(s) => IsPrefix(snapshot[s], everCommitted)
=============================================================================
