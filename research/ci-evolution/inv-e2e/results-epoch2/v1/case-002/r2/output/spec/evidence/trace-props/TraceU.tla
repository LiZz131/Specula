------------------------------ MODULE TraceU ------------------------------
(* Divergence-evidence wrapper: replays a real trace with Trace.tla and     *)
(* evaluates the actual UpdateProps operators on every replayed state.      *)
EXTENDS Trace, UpdateProps
=============================================================================
