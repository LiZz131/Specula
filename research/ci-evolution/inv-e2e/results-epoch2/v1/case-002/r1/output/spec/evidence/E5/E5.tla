---- MODULE E5 ----
EXTENDS UpdateProps
Old == INSTANCE OldBase
\* Source: state 105 of ../output/incremental/runs/final-ev-VotingHistoryCoversDurable-diff-sync-uptodate-failure.log (trace)
EvInit ==
    /\ rollbackAuthorized = [s0 |-> FALSE, s1 |-> FALSE, s2 |-> FALSE]
    /\ recovered = [ s0 |-> <<[id |-> 1, epoch |-> 1]>>,
      s1 |-> <<[id |-> 1, epoch |-> 1]>>,
      s2 |-> <<[id |-> 1, epoch |-> 1], [id |-> 2, epoch |-> 1]>> ]
    /\ votes = [s0 |-> {}, s1 |-> {}, s2 |-> {}]
    /\ leadersByEpoch = (0 :> {} @@ 1 :> {"s2"} @@ 2 :> {"s2"} @@ 3 :> {} @@ 4 :> {})
    /\ syncMode = [s0 |-> "NONE", s1 |-> "NONE", s2 |-> "NONE"]
    /\ ackShadowed = [s0 |-> FALSE, s1 |-> FALSE, s2 |-> FALSE]
    /\ commitCertified = ( 0 :> FALSE @@
      1 :> TRUE @@
      2 :> TRUE @@
      3 :> FALSE @@
      4 :> FALSE @@
      5 :> FALSE @@
      6 :> FALSE @@
      7 :> FALSE @@
      1000 :> FALSE )
    /\ syncSource = [s0 |-> "Nil", s1 |-> "Nil", s2 |-> "Nil"]
    /\ applied = [ s0 |-> <<[id |-> 1, epoch |-> 1]>>,
      s1 |-> <<[id |-> 1, epoch |-> 1]>>,
      s2 |-> <<[id |-> 1, epoch |-> 1]>> ]
    /\ durable = [ s0 |-> <<[id |-> 1, epoch |-> 1], [id |-> 2, epoch |-> 1]>>,
      s1 |-> <<[id |-> 1, epoch |-> 1]>>,
      s2 |-> <<[id |-> 1, epoch |-> 1], [id |-> 2, epoch |-> 1]>> ]
    /\ acked = ( 0 :> {} @@
      1 :> {} @@
      2 :> {} @@
      3 :> {} @@
      4 :> {} @@
      5 :> {} @@
      6 :> {} @@
      7 :> {} @@
      1000 :> {} )
    /\ usedTxn = {1, 2}
    /\ syncKind = [s0 |-> "NONE", s1 |-> "NONE", s2 |-> "NONE"]
    /\ appended = [ s0 |-> <<[id |-> 1, epoch |-> 1], [id |-> 2, epoch |-> 1]>>,
      s1 |-> <<[id |-> 1, epoch |-> 1], [id |-> 2, epoch |-> 1]>>,
      s2 |-> <<[id |-> 1, epoch |-> 1], [id |-> 2, epoch |-> 1]>> ]
    /\ syncBuf = [s0 |-> <<>>, s1 |-> <<>>, s2 |-> <<>>]
    /\ acceptedEpoch = [s0 |-> 2, s1 |-> 2, s2 |-> 2]
    /\ role = [s0 |-> "looking", s1 |-> "looking", s2 |-> "leading"]
    /\ syncJustified = [s0 |-> FALSE, s1 |-> FALSE, s2 |-> FALSE]
    /\ phase = [s0 |-> "election", s1 |-> "election", s2 |-> "broadcast"]
    /\ snapshot = [s0 |-> <<>>, s1 |-> <<>>, s2 |-> <<>>]
    /\ currentEpoch = [s0 |-> 2, s1 |-> 2, s2 |-> 2]
    /\ queued = [ s0 |-> <<[id |-> 1, epoch |-> 1], [id |-> 2, epoch |-> 1]>>,
      s1 |-> <<[id |-> 1, epoch |-> 1], [id |-> 2, epoch |-> 1]>>,
      s2 |-> <<[id |-> 1, epoch |-> 1], [id |-> 2, epoch |-> 1]>> ]
    /\ proposed = [ s0 |-> <<[id |-> 1, epoch |-> 1], [id |-> 2, epoch |-> 1]>>,
      s1 |-> <<[id |-> 1, epoch |-> 1], [id |-> 2, epoch |-> 1]>>,
      s2 |-> <<[id |-> 1, epoch |-> 1], [id |-> 2, epoch |-> 1]>> ]
    /\ nlState = [s0 |-> "NONE", s1 |-> "NONE", s2 |-> "NONE"]
    /\ committed = [ s0 |-> <<[id |-> 1, epoch |-> 1]>>,
      s1 |-> <<[id |-> 1, epoch |-> 1]>>,
      s2 |-> <<[id |-> 1, epoch |-> 1]>> ]
    /\ up = [s0 |-> TRUE, s1 |-> TRUE, s2 |-> TRUE]
    /\ zkState = [s0 |-> "OFF", s1 |-> "OFF", s2 |-> "RUNNING"]
    /\ messages = {}
    /\ nlAckMsgs = {}
    /\ leaderOf = [s0 |-> "Nil", s1 |-> "Nil", s2 |-> "s2"]
    /\ certEpoch = ( 0 :> 0 @@
      1 :> 1 @@
      2 :> 2 @@
      3 :> 0 @@
      4 :> 0 @@
      5 :> 0 @@
      6 :> 0 @@
      7 :> 0 @@
      1000 :> 0 )
    /\ nlAcks = [s0 |-> {}, s1 |-> {}, s2 |-> {"s0", "s2"}]
EvNext == UNCHANGED allVars
OldKept == <<Old!TypeOK, Old!ElectionSafety, Old!OneActiveLeaderPerEpoch,
             Old!CommittedHistoriesPrefix, Old!ApplyRequiresCommitCertificate,
             Old!PipelinePrefix, Old!EpochHistoryConsistency, Old!SyncCompletionJustified>>
NewKept == <<TypeOK, ElectionSafety, OneActiveLeaderPerEpoch,
             CommittedHistoriesPrefix, ApplyRequiresCommitCertificate,
             PipelinePrefix, EpochHistoryConsistency, SyncCompletionJustified>>
NewAdded == <<NewLeaderAckImpliesDurableSync, CertifiedDurableOnQuorum,
              CertifiedRetainedByLaterLeaders, NewLeaderAckIsFirstAck,
              VotingHistoryCoversDurable>>
EvalReport == PrintT(<<"E5", "old-kept", OldKept, "new-kept", NewKept, "new-added(P1..P5)", NewAdded>>)
====
