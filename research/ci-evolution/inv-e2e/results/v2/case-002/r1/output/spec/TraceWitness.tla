--------------------------- MODULE TraceWitness ---------------------------
(* Evaluates the update property predicates (UpdateProps) on the observer
   states of a validated real trace.  Used only as trace-derived evidence; the
   observer approximations of Trace.tla (e.g. commit certification epochs) are
   documented there. *)
EXTENDS Trace, UpdateProps
=============================================================================
