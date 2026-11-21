------------------------- MODULE DischargeNegControl -------------------------
(* Negative control for Update!DischargeContext: the same rely without the
   restart/reset disjunct must be violated by a real omitted Restart step,
   showing the discharge action property is actually evaluated. *)
EXTENDS Update
EnvRelyNoReset ==
    /\ UNCHANGED <<publishedReads, servedReads, readStamp>>
    /\ messages \subseteq messages'
    /\ \A m \in messages' \ messages : m.mtype \notin ReadMsgTypes
    /\ \A j \in Server : ServerVisible(j)' = ServerVisible(j)
DischargeNegative == [][OmittedContextActions => EnvRelyNoReset]_mcVars
=============================================================================
