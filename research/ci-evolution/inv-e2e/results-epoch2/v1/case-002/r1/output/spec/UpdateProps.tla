--------------------------- MODULE UpdateProps ---------------------------
(***************************************************************************)
(* Update properties (owned by Update.tla; factored out so that the trace   *)
(* evidence module can evaluate the same definitions on real traces).      *)
(* Requirement evidence R1-R5 is listed in Update.tla.                      *)
(***************************************************************************)
EXTENDS base

\* P1 (new; R1, R2): a learner that has written its NEWLEADER ACK has made
\* the history it logged in the NEWLEADER branch durable.
NewLeaderAckImpliesDurableSync ==
    \A s \in Server :
        (up[s] /\ role[s] = "following" /\ phase[s] = "sync"
            /\ nlState[s] = "ACKED") => durable[s] = queued[s]

\* P2 (new; R2, R3): every certified (committed) transaction is in the
\* restorable history (log or snapshot) of a quorum.
CertifiedDurableOnQuorum ==
    \A t \in Txn :
        commitCertified[t] =>
          Cardinality({s \in Server : t \in TxnIds(durable[s]) \cup TxnIds(snapshot[s])})
             >= Quorum

\* P3 (new; R2): an established leader of the certifying epoch or a later
\* epoch serves every certified transaction.
CertifiedRetainedByLaterLeaders ==
    \A t \in Txn :
        certEpoch[t] > 0 =>
          \A l \in Server :
             (up[l] /\ role[l] = "leading" /\ phase[l] = "broadcast"
                 /\ currentEpoch[l] >= certEpoch[t])
               => t \in TxnIds(proposed[l])

\* P4 (new; R4): the first ACK a learner writes after NEWLEADER is the
\* NEWLEADER ACK (otherwise the leader rejects it and never counts it).
NewLeaderAckIsFirstAck == \A s \in Server : ~ackShadowed[s]

\* P5 (new; R5): the in-memory history used for votes and Leader.loadData
\* covers the server's durable log whenever the server is electing.
VotingHistoryCoversDurable ==
    \A s \in Server :
        (up[s] /\ role[s] = "looking") => IsPrefix(durable[s], recovered[s])

UpdateSafety ==
    /\ NewLeaderAckImpliesDurableSync
    /\ CertifiedDurableOnQuorum
    /\ CertifiedRetainedByLaterLeaders
    /\ NewLeaderAckIsFirstAck
    /\ VotingHistoryCoversDurable

\* Scenario monitors (observe only; never restrict behavior).
NotCertifiedLossReached ==
    ~(\E t \in Txn : certEpoch[t] > 0 /\
        \E l \in Server : up[l] /\ role[l] = "leading" /\ phase[l] = "broadcast"
                          /\ currentEpoch[l] > certEpoch[t])


=============================================================================
