---- MODULE E2T ----
(* Evaluate the actual Update.tla properties along real trace replays (TraceSpec).
   MC counters are irrelevant to the evaluated predicates and are bound to constants. *)
EXTENDS Trace
CONSTANTS ElectionLimit, TransferLimit, AppendLimit, MembershipLimit, CrashLimit, StaleLimit,
          ElectNodes, TransferTargets, CrashNodes
U == INSTANCE Update WITH electionCount <- 0, transferCount <- 0, appendCount <- 0,
                          membershipCount <- 0, crashCount <- 0, staleCount <- 0
\* Same predicate as Update!ElectionInitiatorIsVoter, stepped over the trace variables.
ElectionInitiatorIsVoterAlongTrace ==
    [][\A n \in Server : U!ElectStep(n) => IsVoter(n, n)]_<<allVars, traceVars>>
NoCorePanicAlongTrace == U!NoCorePanic
====
