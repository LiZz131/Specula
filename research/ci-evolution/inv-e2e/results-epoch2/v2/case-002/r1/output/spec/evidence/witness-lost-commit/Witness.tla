---- MODULE Witness ----
\* Two-phase Init-rooted witness search for UpdLeaderCompleteness.  Each phase
\* restricts which servers take steps (a subset of MCNext; no behaviour added).
EXTENDS Update
CONSTANTS Actors
CONSTANTS s1, s2, s3, t1   \* model values naming the servers in state-S.tla
ActorsNext ==
    /\ \/ \E s \in Actors : MCBeginElection(s)
       \/ \E v, c \in Actors : MCCastVote(v, c)
       \/ \E s \in Actors : MCWinElection(s)
       \/ \E s, l \in Actors : MCFollowLeader(s, l)
       \/ \E s \in Actors : MCAcceptEpoch(s)
       \/ \E l \in Actors : MCFinishDiscovery(l)
       \/ \E s, l \in Actors : MCEnterSyncPhase(s, l)
       \/ \E s, l \in Actors, mode \in SyncModes \ {"NONE"} : MCSelectSync(s, l, mode)
       \/ \E s \in Actors : MCCompleteSync(s)
       \/ \E s \in Actors : MCPersistCurrentEpoch(s)
       \/ \E s \in Actors : MCClearSyncMode(s)
       \/ \E s \in Actors : MCLogSyncProposal(s)
       \/ \E s \in Actors : MCAckNewLeader(s)
       \/ \E l, s \in Actors : MCCountNewLeaderAck(l, s)
       \/ \E l \in Actors : MCLeaderBroadcast(l)
       \/ \E s \in Actors : MCReceiveUpToDate(s)
       \/ \E s \in Actors : MCEnterBroadcast(s)
       \/ \E l \in Actors, t \in Txn : MCPropose(l, t)
       \/ \E s \in Actors : MCAppendOne(s)
       \/ \E s \in Actors : MCFsyncOne(s)
    /\ GhostNext
Phase1Spec == UpdInit /\ [][ActorsNext]_uvars
\* Phase 2 starts in the final state S of the phase-1 counterexample (state-S.tla).
SInit ==
/\ rollbackAuthorized = (s1 :> FALSE @@ s2 :> FALSE @@ s3 :> FALSE)
/\ recovered = (s1 :> <<[id |-> t1, epoch |-> 1]>> @@ s2 :> <<>> @@ s3 :> <<>>)
/\ votes = (s1 :> {s1, s2} @@ s2 :> {s2} @@ s3 :> {})
/\ leadersByEpoch = (0 :> {} @@ 1 :> {s1} @@ 2 :> {s1} @@ 3 :> {})
/\ syncMode = (s1 :> "NONE" @@ s2 :> "NONE" @@ s3 :> "NONE")
/\ commitCertified = (t1 :> TRUE)
/\ syncSource = (s1 :> Nil @@ s2 :> s1 @@ s3 :> Nil)
/\ applied = (s1 :> <<[id |-> t1, epoch |-> 1]>> @@ s2 :> <<>> @@ s3 :> <<>>)
/\ durable = (s1 :> <<[id |-> t1, epoch |-> 1]>> @@ s2 :> <<>> @@ s3 :> <<>>)
/\ acked = (t1 :> {})
/\ usedTxn = {t1}
/\ everCommitted = {[ent |-> [id |-> t1, epoch |-> 1], ep |-> 2]}
/\ appended = (s1 :> <<[id |-> t1, epoch |-> 1]>> @@ s2 :> <<>> @@ s3 :> <<>>)
/\ acceptedEpoch = (s1 :> 2 @@ s2 :> 2 @@ s3 :> 0)
/\ role = (s1 :> "leading" @@ s2 :> "following" @@ s3 :> "looking")
/\ seen = { "election",
  "sync",
  "broadcast",
  "DIFF",
  "leader",
  "diffpayload",
  "synclog",
  "nlack",
  "nlackBeforeDurable",
  "mutation" }
/\ syncJustified = (s1 :> FALSE @@ s2 :> TRUE @@ s3 :> FALSE)
/\ phase = (s1 :> "broadcast" @@ s2 :> "sync" @@ s3 :> "election")
/\ snapshot = (s1 :> <<>> @@ s2 :> <<>> @@ s3 :> <<>>)
/\ currentEpoch = (s1 :> 2 @@ s2 :> 2 @@ s3 :> 0)
/\ queued = ( s1 :> <<[id |-> t1, epoch |-> 1]>> @@
  s2 :> <<[id |-> t1, epoch |-> 1]>> @@
  s3 :> <<>> )
/\ proposed = ( s1 :> <<[id |-> t1, epoch |-> 1]>> @@
  s2 :> <<[id |-> t1, epoch |-> 1]>> @@
  s3 :> <<>> )
/\ leaderSummaryEpoch = (s1 :> 1 @@ s2 :> 0 @@ s3 :> 0)
/\ committed = (s1 :> <<[id |-> t1, epoch |-> 1]>> @@ s2 :> <<>> @@ s3 :> <<>>)
/\ counters = [snapshot |-> 0, crash |-> 0, drop |-> 0]
/\ newLeaderAcked = (s1 :> FALSE @@ s2 :> TRUE @@ s3 :> FALSE)
/\ up = (s1 :> TRUE @@ s2 :> TRUE @@ s3 :> TRUE)
/\ zkState = (s1 :> "running" @@ s2 :> "initial" @@ s3 :> "off")
/\ messages = { [id |-> t1, epoch |-> 1, kind |-> "proposal", from |-> s1, to |-> s2],
  [id |-> t1, epoch |-> 1, kind |-> "proposal", from |-> s1, to |-> s3] }
/\ leaderOf = (s1 :> s1 @@ s2 :> s1 @@ s3 :> Nil)
/\ nlAcks = (s1 :> {s1, s2} @@ s2 :> {} @@ s3 :> {})
Phase2Spec == SInit /\ [][ActorsNext]_uvars
\* Crash variant: same actors plus fail-stop Crash/Restart (bounded by MaxCrash);
\* leaving the protocol from State.INITIAL is excluded (ACTION_CONSTRAINT) so the
\* only way to lose the queued history is the crash after the NEWLEADER ACK.
CrashNext == \/ ActorsNext
             \/ (\E s \in Actors : MCCrash(s) \/ MCRestart(s)) /\ GhostNext
Phase2CrashSpec == SInit /\ [][CrashNext]_uvars
NoLeaveFromInitial == \A s \in Server : ~(zkState[s] = "initial" /\ zkState'[s] = "off" /\ up'[s])
====
