------------------------------- MODULE HuntU1 -------------------------------
(***************************************************************************)
(* Scenario hunt for U1/U2/U4 consequences (P3).  Exploration-only        *)
(* constraints (never redefine reference behavior; every explored step is  *)
(* an MCNext/FocusedNext step):                                            *)
(*  - server `Idle` takes no step until some transaction has been certified *)
(*    by an epoch-2 leader (it plays the peer that was absent from the      *)
(*    epoch-2 NEWLEADER quorum);                                            *)
(*  - crashes happen only after that certification.                        *)
(***************************************************************************)
EXTENDS Update
CONSTANT Idle
ASSUME Idle \in Server

Certified2 == \E t \in Txn : certEpoch[t] = 2

IdleUntilCertified ==
    Certified2 \/
      /\ role[Idle] = "looking" /\ phase[Idle] = "election"
      /\ acceptedEpoch[Idle] = 0 /\ currentEpoch[Idle] = 0
      /\ \A c \in Server : Idle \notin votes[c]
      /\ votes[Idle] = {}

CrashAfterCertified == Certified2 \/ counters.crash = 0

HuntConstraintU1 == IdleUntilCertified /\ CrashAfterCertified

\* Crash-only variant (U1/U2): exclude INITIAL-state exits so the
\* consequence must come from a learner crash before its fsync.
HuntConstraintU1Crash == HuntConstraintU1 /\ "initial-exit" \notin seen

OthersSymmetry == Permutations(Server \ {Idle})
=============================================================================
