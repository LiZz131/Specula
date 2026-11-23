------------------------------ MODULE Probe002 ------------------------------
(* Decision probe for case-002 (v2). State predicates only.                 *)
(* v2 has no action that consumes a COMMIT while the learner is in its      *)
(* synchronization phase (ReceiveCommit requires phase = "broadcast",       *)
(* base.tla:633), so the NPE trigger state (COMMIT consumable with an empty *)
(* packetsNotCommitted after NEWLEADER) cannot be written as "an action is  *)
(* enabled". These probes measure how close the model gets:                *)
(*  - CommitWindow: a COMMIT from its leader is in flight to a learner that *)
(*    is still in SYNCHRONIZATION and has sent its NEWLEADER ACK            *)
(*    (pendingSync already logged and cleared);                            *)
(*  - NPETrigger: same, and the committed entry is one the learner received *)
(*    in its pre-NEWLEADER stream (recovered[s]) -- the real NPE pattern.   *)
EXTENDS MC

CommitWindow(m) ==
    /\ m.kind = "commit" /\ leaderOf[m.to] = m.from
    /\ up[m.to] /\ phase[m.to] = "sync" /\ nlAckSent[m.to]
    /\ pendingSync[m.to] = <<>>
NPETrigger(m) ==
    /\ CommitWindow(m)
    /\ EntryFor(m.id, m.epoch) \in {recovered[m.to][k] : k \in 1..Len(recovered[m.to])}

ProbeNoCommitWindow == ~\E m \in messages : CommitWindow(m)
ProbeNoNPE == ~\E m \in messages : NPETrigger(m)
=============================================================================
