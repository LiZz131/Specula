------------------------------- MODULE FixSketch -------------------------------
(* Model-only check of the MC-1 recommendation: accept an Abci subrecord that
   repeats the current enable height before the height checks.  Not part of the
   reference suite; it overrides ValidateUpdateOK via the cfg. *)
EXTENDS Update

FixedValidateUpdateOK(E, u, h) ==
    \/ (u.present /\ u.abciPresent /\ u.abci = E)
    \/ ValidateUpdateRow(E, u, h) \in AcceptRows
=============================================================================
