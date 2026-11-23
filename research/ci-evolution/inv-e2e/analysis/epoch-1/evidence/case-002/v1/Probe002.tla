------------------------------ MODULE Probe002 ------------------------------
(* Decision probe for case-002 (v1). State predicates only; no actions are  *)
(* added or changed.                                                        *)
(* NPE trigger state: learner s has handled NEWLEADER (syncJustified) and   *)
(* sent its ACK (nlAckSent), its packetsNotCommitted buffer (syncBuf) is    *)
(* empty, and a COMMIT for s can be consumed now (ReceiveSyncCommit         *)
(* enabled). The implementation then runs                                   *)
(* `pif = packetsNotCommitted.peekFirst(); if (pif.hdr...` (Learner.java:   *)
(* 645-646) with pif == null.                                               *)
EXTENDS MC

NPETrigger(m) ==
    /\ m.kind = "commit"
    /\ syncJustified[m.to] /\ nlAckSent[m.to]
    /\ syncBuf[m.to] = <<>>
    /\ ENABLED ReceiveSyncCommit(m)

ProbeNoNPE == ~\E m \in messages : NPETrigger(m)
=============================================================================
