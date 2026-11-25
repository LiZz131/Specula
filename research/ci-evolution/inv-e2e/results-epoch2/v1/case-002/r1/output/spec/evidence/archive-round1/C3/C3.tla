---- MODULE C3 ----
EXTENDS UpdateProps
CONSTANTS s1, s2, s3, t1
Old == INSTANCE OldBase
\* Source: state 29 of ../output/incremental/runs-round1/huntU1-P3-bfs.log (mc)
EvInit ==
    /\ rollbackAuthorized = (s1 :> FALSE @@ s2 :> TRUE @@ s3 :> FALSE)
    /\ recovered = (s1 :> <<>> @@ s2 :> <<[id |-> t1, epoch |-> 1]>> @@ s3 :> <<>>)
    /\ votes = (s1 :> {s1} @@ s2 :> {s1, s2} @@ s3 :> {})
    /\ leadersByEpoch = (0 :> {} @@ 1 :> {s2} @@ 2 :> {s2} @@ 3 :> {})
    /\ syncMode = (s1 :> "NONE" @@ s2 :> "NONE" @@ s3 :> "NONE")
    /\ ackShadowed = (s1 :> FALSE @@ s2 :> FALSE @@ s3 :> FALSE)
    /\ commitCertified = (t1 :> TRUE)
    /\ syncSource = (s1 :> Nil @@ s2 :> Nil @@ s3 :> Nil)
    /\ applied = (s1 :> <<>> @@ s2 :> <<[id |-> t1, epoch |-> 1]>> @@ s3 :> <<>>)
    /\ durable = (s1 :> <<>> @@ s2 :> <<[id |-> t1, epoch |-> 1]>> @@ s3 :> <<>>)
    /\ acked = (t1 :> {})
    /\ usedTxn = {t1}
    /\ syncKind = (s1 :> "NONE" @@ s2 :> "NONE" @@ s3 :> "NONE")
    /\ appended = (s1 :> <<>> @@ s2 :> <<[id |-> t1, epoch |-> 1]>> @@ s3 :> <<>>)
    /\ syncBuf = (s1 :> <<>> @@ s2 :> <<>> @@ s3 :> <<>>)
    /\ acceptedEpoch = (s1 :> 2 @@ s2 :> 2 @@ s3 :> 0)
    /\ role = (s1 :> "looking" @@ s2 :> "leading" @@ s3 :> "looking")
    /\ syncJustified = (s1 :> FALSE @@ s2 :> FALSE @@ s3 :> FALSE)
    /\ phase = (s1 :> "election" @@ s2 :> "broadcast" @@ s3 :> "election")
    /\ snapshot = (s1 :> <<>> @@ s2 :> <<>> @@ s3 :> <<>>)
    /\ currentEpoch = (s1 :> 2 @@ s2 :> 2 @@ s3 :> 0)
    /\ queued = (s1 :> <<>> @@ s2 :> <<[id |-> t1, epoch |-> 1]>> @@ s3 :> <<>>)
    /\ proposed = (s1 :> <<>> @@ s2 :> <<[id |-> t1, epoch |-> 1]>> @@ s3 :> <<>>)
    /\ nlState = (s1 :> "NONE" @@ s2 :> "NONE" @@ s3 :> "NONE")
    /\ committed = (s1 :> <<>> @@ s2 :> <<[id |-> t1, epoch |-> 1]>> @@ s3 :> <<>>)
    /\ up = (s1 :> TRUE @@ s2 :> TRUE @@ s3 :> TRUE)
    /\ zkState = (s1 :> "OFF" @@ s2 :> "RUNNING" @@ s3 :> "OFF")
    /\ messages = { [kind |-> "proposal", id |-> t1, from |-> s2, epoch |-> 1, to |-> s1],
      [kind |-> "proposal", id |-> t1, from |-> s2, epoch |-> 1, to |-> s3] }
    /\ nlAckMsgs = {}
    /\ leaderOf = (s1 :> Nil @@ s2 :> s2 @@ s3 :> Nil)
    /\ certEpoch = (t1 :> 2)
    /\ nlAcks = (s1 :> {} @@ s2 :> {s1} @@ s3 :> {})
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
