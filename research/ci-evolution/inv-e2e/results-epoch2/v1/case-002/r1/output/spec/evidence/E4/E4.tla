---- MODULE E4 ----
EXTENDS UpdateProps
CONSTANTS s1, s2, t1
Old == INSTANCE OldBase
\* Source: state 22 of ../output/incremental/runs/hunt2s-NewLeaderAckIsFirstAck-bfs.log (mc)
EvInit ==
    /\ rollbackAuthorized = (s1 :> FALSE @@ s2 :> FALSE)
    /\ recovered = (s1 :> <<>> @@ s2 :> <<>>)
    /\ votes = (s1 :> {s1, s2} @@ s2 :> {s2})
    /\ leadersByEpoch = (0 :> {} @@ 1 :> {s1} @@ 2 :> {})
    /\ syncMode = (s1 :> "NONE" @@ s2 :> "NONE")
    /\ ackShadowed = (s1 :> FALSE @@ s2 :> TRUE)
    /\ commitCertified = (t1 :> FALSE)
    /\ syncSource = (s1 :> Nil @@ s2 :> s1)
    /\ applied = (s1 :> <<>> @@ s2 :> <<>>)
    /\ durable = (s1 :> <<>> @@ s2 :> <<[id |-> t1, epoch |-> 1]>>)
    /\ acked = (t1 :> {})
    /\ usedTxn = {t1}
    /\ syncKind = (s1 :> "NONE" @@ s2 :> "SNAP")
    /\ appended = (s1 :> <<>> @@ s2 :> <<[id |-> t1, epoch |-> 1]>>)
    /\ syncBuf = (s1 :> <<>> @@ s2 :> <<>>)
    /\ acceptedEpoch = (s1 :> 1 @@ s2 :> 1)
    /\ role = (s1 :> "leading" @@ s2 :> "following")
    /\ syncJustified = (s1 :> FALSE @@ s2 :> TRUE)
    /\ phase = (s1 :> "broadcast" @@ s2 :> "sync")
    /\ snapshot = (s1 :> <<>> @@ s2 :> <<>>)
    /\ currentEpoch = (s1 :> 1 @@ s2 :> 1)
    /\ queued = (s1 :> <<[id |-> t1, epoch |-> 1]>> @@ s2 :> <<[id |-> t1, epoch |-> 1]>>)
    /\ proposed = (s1 :> <<[id |-> t1, epoch |-> 1]>> @@ s2 :> <<[id |-> t1, epoch |-> 1]>>)
    /\ nlState = (s1 :> "NONE" @@ s2 :> "LOGGED")
    /\ committed = (s1 :> <<>> @@ s2 :> <<>>)
    /\ up = (s1 :> TRUE @@ s2 :> TRUE)
    /\ zkState = (s1 :> "RUNNING" @@ s2 :> "INITIAL")
    /\ messages = { [kind |-> "proposal", id |-> t1, from |-> s1, epoch |-> 1, to |-> s2],
      [kind |-> "ack", id |-> t1, from |-> s2, epoch |-> 1, to |-> s1] }
    /\ nlAckMsgs = {}
    /\ leaderOf = (s1 :> s1 @@ s2 :> s1)
    /\ certEpoch = (t1 :> 0)
    /\ nlAcks = (s1 :> {s2} @@ s2 :> {})
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
EvalReport == PrintT(<<"E4", "old-kept", OldKept, "new-kept", NewKept, "new-added(P1..P5)", NewAdded>>)
====
