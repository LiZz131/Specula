---------------------------- MODULE TraceSync ----------------------------
(* Action-level trace validation of the UPDATED learner synchronization path.
   Unlike the inherited observer-style Trace.tla, every event here is replayed
   through the REFERENCE actions of base.tla (no observer assignments):
     AcceptedEpochPersisted -> AcceptEpoch
     PhaseChanged(sync)     -> EnterSyncPhase
     SyncModeChanged(mode)  -> SelectSync / ClearSyncMode
     SyncSelected           -> ReceiveSyncPayload (stream fixed by the leader)
     CurrentEpochPersisted  -> PersistCurrentEpoch
     NewLeaderAckSent       -> AckNewLeader         (UPDATE)
     BroadcastReady         -> EnterBroadcast       (UPDATE; leader activation
                               LeaderBroadcast is a constrained silent step)
     TxnAppended/TxnDurable/TxnApplied -> AppendOne/FsyncOne/ApplyOne
   Remaining follower events are observation-only and compare their captured
   fields with the reference state.

   Scope: Zab1_0Test ConversableFollower DIFF conversations (follower "s0",
   uninstrumented fixture leader "s1").  Fixture projection: the fixture leader
   history is the sequence of proposals it streams before NEWLEADER (the
   conversation's DIFF marker zxid is not part of that stream); its NEWLEADER
   quorum is {s1, s0}. *)
EXTENDS base, Json, IOUtils, Sequences, TLC

JsonFile == IF "JSON" \in DOMAIN IOEnv
            THEN IOEnv.JSON
            ELSE "../traces/follower-diff.ndjson"

TraceLog == TLCEval(
    LET all == ndJsonDeserialize(JsonFile)
    IN SelectSeq(all, LAMBDA x : "tag" \in DOMAIN x /\ x.tag = "trace"))

Fol == "s0"
Ldr == "s1"

ASSUME Len(TraceLog) > 0
ASSUME \A k \in 1..Len(TraceLog) : TraceLog[k].event.node = Fol

EntOf(rec) == EntryFor(rec.event.txnCounter, rec.event.txnEpoch)

FirstAck == CHOOSE k \in 1..Len(TraceLog) :
               /\ TraceLog[k].event.name = "NewLeaderAckSent"
               /\ \A j \in 1..(k-1) : TraceLog[j].event.name /= "NewLeaderAckSent"

\* Proposals streamed before NEWLEADER = the fixture leader's history.
StreamIdx == SelectSeq([k \in 1..(FirstAck - 1) |-> k],
                       LAMBDA k : TraceLog[k].event.name = "SyncProposalReceived")
LeaderHist == [i \in 1..Len(StreamIdx) |-> EntOf(TraceLog[StreamIdx[i]])]

VARIABLE l
logline == TraceLog[l]
E == logline.event
Ev == E.name
Ent == EntOf(logline)
HasEntry(h, ent) == \E k \in 1..Len(h) : h[k] = ent
Last(h) == h[Len(h)]

TraceInit ==
    /\ l = 1
    /\ up = [s \in Server |-> TRUE]
    /\ role = [s \in Server |-> IF s = Ldr THEN "leading" ELSE "following"]
    /\ phase = [s \in Server |-> IF s = Ldr THEN "sync" ELSE "discovery"]
    /\ leaderOf = [s \in Server |-> Ldr]
    /\ acceptedEpoch = [s \in Server |-> IF s = Ldr THEN 1 ELSE 0]
    /\ currentEpoch = [s \in Server |-> IF s = Ldr THEN 1 ELSE 0]
    /\ votes = [s \in Server |-> IF s = Ldr THEN Server ELSE {}]
    /\ leadersByEpoch = [e \in Epoch |-> IF e = 1 THEN {Ldr} ELSE {}]
    /\ proposed = [s \in Server |-> IF s = Ldr THEN LeaderHist ELSE <<>>]
    /\ queued = proposed
    /\ appended = proposed
    /\ durable = proposed
    /\ committed = [s \in Server |-> <<>>]
    /\ applied = [s \in Server |-> <<>>]
    /\ snapshot = [s \in Server |-> <<>>]
    /\ recovered = [s \in Server |-> IF s = Ldr THEN LeaderHist ELSE <<>>]
    /\ acked = [t \in Txn |-> IF t \in TxnIds(LeaderHist) THEN {Ldr} ELSE {}]
    /\ commitCertified = [t \in Txn |-> FALSE]
    /\ messages = {}
    /\ syncMode = [s \in Server |-> "NONE"]
    /\ syncSource = [s \in Server |-> Nil]
    /\ syncJustified = [s \in Server |-> FALSE]
    /\ usedTxn = TxnIds(LeaderHist)
    /\ rollbackAuthorized = [s \in Server |-> FALSE]
    /\ pendingSync = [s \in Server |-> <<>>]
    /\ nlAckSent = [s \in Server |-> FALSE]
    /\ nlAcks = [s \in Server |-> IF s = Ldr THEN {Ldr} ELSE {}]
    /\ certEpoch = [t \in Txn |-> 0]
    /\ memHist = [s \in Server |-> IF s = Ldr THEN LeaderHist ELSE <<>>]

Observe == UNCHANGED allVars

\* Captured peer fields of follower probes (unknown sentinels from generic probes).
CommonCheck ==
    /\ E.state.acceptedEpoch >= 0 => acceptedEpoch'[Fol] = E.state.acceptedEpoch
    /\ E.state.currentEpoch >= 0 => currentEpoch'[Fol] = E.state.currentEpoch
    /\ syncMode'[Fol] = E.state.syncMode

EventStep ==
    /\ l <= Len(TraceLog)
    /\ CASE Ev = "PhaseChanged" /\ E.state.phase = "synchronization"
                /\ phase[Fol] = "discovery" ->
              EnterSyncPhase(Fol, Ldr)
         [] Ev = "PhaseChanged" ->
              /\ Observe
              /\ E.state.phase = "discovery" => phase[Fol] = "discovery"
              /\ E.state.phase = "broadcast" => phase[Fol] = "broadcast"
         [] Ev = "AcceptedEpochPersisted" ->
              /\ AcceptEpoch(Fol)
              /\ acceptedEpoch'[Fol] = E.txnEpoch
         [] Ev = "FollowerRegistered" ->
              /\ Observe
              /\ Len(durable[Fol]) = 0 => E.txnCounter = 0
         [] Ev = "SyncModeChanged" /\ E.state.syncMode /= "NONE" ->
              SelectSync(Fol, Ldr, E.state.syncMode)
         [] Ev = "SyncModeChanged" ->
              ClearSyncMode(Fol)
         [] Ev = "SyncSelected" ->
              ReceiveSyncPayload(Fol)
         [] Ev = "SyncProposalReceived" ->
              \* the k-th buffered proposal is the k-th entry of the stream
              /\ Observe
              /\ E.detail.pending \in 1..Len(pendingSync[Fol])
              /\ pendingSync[Fol][E.detail.pending] = Ent
         [] Ev = "SyncCommitReceived" ->
              /\ Observe
              /\ E.detail.writeToTxnLog = TRUE
              /\ HasEntry(pendingSync[Fol], Ent)
         [] Ev = "CurrentEpochPersisted" ->
              /\ PersistCurrentEpoch(Fol)
              /\ currentEpoch'[Fol] = E.txnEpoch
         [] Ev = "ProposalQueued" /\ ~nlAckSent[Fol] ->
              \* logRequest inside the NEWLEADER handler: about to be queued by AckNewLeader
              /\ Observe
              /\ HasEntry(pendingSync[Fol], Ent)
         [] Ev = "NewLeaderAckSent" ->
              /\ AckNewLeader(Fol)
              /\ E.detail.logged = Len(pendingSync[Fol])
              /\ E.detail.running = FALSE
              /\ pendingSync'[Fol] = <<>>
              /\ queued'[Fol] = recovered[Fol]
              \* field check of the durable position at the ACK
              /\ IF E.detail.durableCounter < 0
                 THEN durable'[Fol] = <<>>
                 ELSE /\ Len(durable'[Fol]) > 0
                      /\ Last(durable'[Fol]).epoch = E.detail.durableEpoch
                      /\ Last(durable'[Fol]).id = E.detail.durableCounter
         [] Ev = "NewLeaderAckWritten" ->
              /\ Observe
              /\ nlAckSent[Fol]
              /\ E.detail.durableCounter < 0 => durable[Fol] = <<>>
         [] Ev = "BroadcastReady" ->
              /\ EnterBroadcast(Fol)
              /\ E.detail.running = TRUE
              /\ E.detail.pending = 0
         [] Ev = "CommitDelivered" ->
              /\ Observe
              /\ HasEntry(committed[Fol], Ent)
              /\ commitCertified[Ent.id]
         [] Ev = "TxnAppended" ->
              /\ AppendOne(Fol)
              /\ Last(appended'[Fol]) = Ent
         [] Ev = "TxnDurable" ->
              /\ FsyncOne(Fol)
              /\ Last(durable'[Fol]) = Ent
         [] Ev = "TxnApplied" ->
              /\ ApplyOne(Fol)
              /\ Last(applied'[Fol]) = Ent
    /\ CommonCheck
    /\ l' = l + 1

\* Fixture leader activation after the NEWLEADER quorum; enabled only right
\* before the follower consumes UPTODATE.
SilentLeaderActivation ==
    /\ l <= Len(TraceLog)
    /\ Ev = "BroadcastReady"
    /\ LeaderBroadcast(Ldr)
    /\ UNCHANGED l

TraceNext == EventStep \/ SilentLeaderActivation

TraceSpec == TraceInit /\ [][TraceNext]_<<allVars, l>> /\ WF_<<allVars, l>>(TraceNext)

TraceMatched == <>(l > Len(TraceLog))

\* Reference invariants that must hold on the replayed real execution.
TraceSafety == TypeOK /\ PipelinePrefix /\ ApplyRequiresCommitCertificate
               /\ SyncCompletionJustified /\ EpochHistoryConsistency

\* Update observation: the replay reaches a state in which the follower has
\* sent its NEWLEADER ACK while the streamed history is not durable (expected
\* to be VIOLATED on DIFF traces; used as a code-observation witness).
NotAckBeforeDurable ==
    ~(nlAckSent[Fol] /\ ~IsPrefix(recovered[Fol], durable[Fol]))

\* Evidence helper (expected VIOLATED at the end of the trace): prints the final
\* replayed state, used as the trace-derived keep state in spec/evidence/K1.
NotFinished == l <= Len(TraceLog)

=============================================================================
