---------------------------- MODULE TraceOracle ----------------------------
(* Update properties evaluated on reference behaviors that replay real      *)
(* implementation traces (Trace.tla fires base Actions from Init).  A       *)
(* violation here is a full-reference behavior admitted by an observed      *)
(* execution of the updated implementation.                                *)
EXTENDS Trace, UpdateProps
=============================================================================
