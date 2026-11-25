------------------------ MODULE TraceUpdateEvidence ------------------------
(***************************************************************************)
(* Code-observation evidence: evaluates the update properties (owned by    *)
(* Update.tla, defined in UpdateProps.tla) on the states reached by       *)
(* replaying real new-version traces.  A violation here is an observed     *)
(* implementation state, not a model-checking counterexample.              *)
(***************************************************************************)
EXTENDS Trace, UpdateProps

\* Dump helpers for control states (violated on purpose to print the state).
StopAt11 == l /= 11
StopAt107 == l /= 107
StopAt114 == l /= 114
StopAt90 == l /= 90
StopAt15 == l /= 15
=============================================================================
