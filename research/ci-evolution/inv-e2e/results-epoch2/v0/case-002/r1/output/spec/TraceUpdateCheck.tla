--------------------------- MODULE TraceUpdateCheck ---------------------------
(* Replays a validated implementation trace (Trace!TraceNext) while checking *)
(* the update properties of Update.tla.  A violation here means the real     *)
(* execution itself reached the property-violating state.  MC bookkeeping    *)
(* variables are frozen.                                                     *)
EXTENDS Trace, Update

TUInit == /\ TraceInit
          /\ counters = [crash |-> 0, drop |-> 0, snapshot |-> 0, shutdown |-> 0]
          /\ seen = {}
TUNext == TraceNext /\ UNCHANGED <<counters, seen>>
TUSpec == TUInit /\ [][TUNext]_<<allVars, traceVars, counters, seen>>
               /\ WF_<<allVars, traceVars, counters, seen>>(TUNext)
=============================================================================
