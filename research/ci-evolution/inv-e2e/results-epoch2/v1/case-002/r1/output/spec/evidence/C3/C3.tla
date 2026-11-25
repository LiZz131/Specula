---- MODULE C3 ----
EXTENDS UpdateProps
CONSTANTS s1, s2, s3, t1
Old == INSTANCE OldBase
\* Source: state 28 of ../output/incremental/runs/huntU1-P3-bfs.log (mc)
EvInit ==
    /\ rollbackAuthorized = (s1 :> TRUE @@ s2 :> FALSE @@ s3 :> FALSE)
    /\ recovered = (s1 :> <<[id |-> t1, epoch |-> 1]>> @@ s2 :> <<>> @@ s3 :> <<>>)
    /\ votes = (s1 :> {s1, s2} @@ s2 :> {s2} @@ s3 :> {})
    /\ leadersByEpoch = (0 :> {} @@ 1 :> {s1} @@ 2 :> {s1} @@ 3 :> {})
    /\ syncMode = (s1 :> "NONE" @@ s2 :> "NONE" @@ s3 :> "NONE")
    /\ ackShadowed = (s1 :> FALSE @@ s2 :> FALSE @@ s3 :> FALSE)
    /\ commitCertified = (t1 :> TRUE)
    /\ syncSource = (s1 :> Nil @@ s2 :> Nil @@ s3 :> Nil)
    /\ applied = (s1 :> <<[id |-> t1, epoch |-> 1]>> @@ s2 :> <<>> @@ s3 :> <<>>)
    /\ durable = (s1 :> <<[id |-> t1, epoch |-> 1]>> @@ s2 :> <<>> @@ s3 :> <<>>)
    /\ acked = (t1 :> {})
    /\ usedTxn = {t1}
    /\ syncKind = (s1 :> "NONE" @@ s2 :> "NONE" @@ s3 :> "NONE")
    /\ appended = (s1 :> <<[id |-> t1, epoch |-> 1]>> @@ s2 :> <<>> @@ s3 :> <<>>)
    /\ syncBuf = (s1 :> <<>> @@ s2 :> <<>> @@ s3 :> <<>>)
    /\ acceptedEpoch = (s1 :> 2 @@ s2 :> 2 @@ s3 :> 0)
    /\ role = (s1 :> "leading" @@ s2 :> "looking" @@ s3 :> "looking")
    /\ syncJustified = (s1 :> FALSE @@ s2 :> FALSE @@ s3 :> FALSE)
    /\ phase = (s1 :> "broadcast" @@ s2 :> "election" @@ s3 :> "election")
    /\ snapshot = (s1 :> <<>> @@ s2 :> <<>> @@ s3 :> <<>>)
    /\ currentEpoch = (s1 :> 2 @@ s2 :> 2 @@ s3 :> 0)
    /\ queued = (s1 :> <<[id |-> t1, epoch |-> 1]>> @@ s2 :> <<>> @@ s3 :> <<>>)
    /\ proposed = (s1 :> <<[id |-> t1, epoch |-> 1]>> @@ s2 :> <<>> @@ s3 :> <<>>)
    /\ nlState = (s1 :> "NONE" @@ s2 :> "NONE" @@ s3 :> "NONE")
    /\ committed = (s1 :> <<[id |-> t1, epoch |-> 1]>> @@ s2 :> <<>> @@ s3 :> <<>>)
    /\ up = (s1 :> TRUE @@ s2 :> TRUE @@ s3 :> TRUE)
    /\ zkState = (s1 :> "RUNNING" @@ s2 :> "OFF" @@ s3 :> "OFF")
    /\ messages = { [kind |-> "proposal", id |-> t1, from |-> s1, epoch |-> 1, to |-> s2],
      [kind |-> "proposal", id |-> t1, from |-> s1, epoch |-> 1, to |-> s3] }
    /\ nlAckMsgs = {}
    /\ leaderOf = (s1 :> s1 @@ s2 :> Nil @@ s3 :> Nil)
    /\ certEpoch = (t1 :> 2)
    /\ nlAcks = (s1 :> {s2} @@ s2 :> {} @@ s3 :> {})
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
EvalReport == PrintT(<<"C3", "old-kept", OldKept, "new-kept", NewKept, "new-added(P1..P5)", NewAdded>>)
====
