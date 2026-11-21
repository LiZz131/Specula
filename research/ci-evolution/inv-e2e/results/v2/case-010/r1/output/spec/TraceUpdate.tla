---------------------------- MODULE TraceUpdate ----------------------------
(* Trace replay that additionally evaluates the update properties on every *)
(* replayed implementation state (divergence/keep evidence).               *)
EXTENDS Trace, UpdateProps
=============================================================================
