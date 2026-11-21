---------------------------- MODULE UpdateProps ----------------------------
(***************************************************************************)
(* Update-specific properties (single definition), used by Update.tla over *)
(* MCNext and by TraceUpdateEvidence.tla over validated traces.            *)
(***************************************************************************)
EXTENDS base

-----
(* Update properties.                                                      *)

(* A1. A history an active leader treats as committed is persisted on a    *)
(* quorum.  Requirement: zookeeperInternals.md:115-119 ("committed when a    *)
(* quorum of them acknowledge ... Acknowledgement means the server has       *)
(* recorded the proposal to persistent storage") and :192-197 (NEW_LEADER    *)
(* ACK after sync; the leader commits on a quorum of ACKs); updated code     *)
(* comment L:748 "make sure sync the uncommitted logs before commit them     *)
(* (ACK NEWLEADER)".  Interaction of SendNewLeaderAck (affected) with        *)
(* LeaderActivate (consumer) and FsyncOne (persistence).                    *)
CommittedPersistedOnQuorum ==
    \A l \in Server :
        ActiveLeader(l) =>
            Cardinality({s \in Server : IsPrefix(committed[l], Persisted(s))})
                >= Quorum

(* A2. Every transaction ever committed (certified by a leader) is in the  *)
(* committed history of every active leader.  Requirement:                 *)
(* zookeeperInternals.md:245-250 ("a new leader has seen all committed     *)
(* proposals ... any uncommitted proposals ... will be committed by that   *)
(* leader before it becomes active"); DIFFSyncConsistencyTest assertion    *)
(* "Data inconsistency detected!".  Consequence property crossing          *)
(* SendNewLeaderAck -> Crash/BeginElection -> CastVote -> LeaderActivate.  *)
LeaderCompleteness ==
    \A l \in Server :
        ActiveLeader(l) =>
            \A t \in Txn : commitCertified[t] => t \in TxnIds(committed[l])

UpdateProperties == CommittedPersistedOnQuorum /\ LeaderCompleteness

(* Unaffected control property kept enabled in every update cfg. *)
UpdateControl == CommittedHistoriesPrefix /\ ElectionSafety

=============================================================================
