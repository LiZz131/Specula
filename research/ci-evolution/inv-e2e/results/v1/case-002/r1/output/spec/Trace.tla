------------------------------ MODULE Trace ------------------------------
(***************************************************************************)
(* Action-based trace validation for the updated reference (Category A,   *)
(* single linear NDJSON trace per scenario).  Every probe event is matched *)
(* by calling the reference action named in instrumentation-spec.md and    *)
(* then comparing the captured post-state.  Silent steps are restricted to *)
(* unprobed FLE votes, ACKs that Leader.processAck ignores before addAck,  *)
(* the Zab1_0Test fixture leader's packet I/O, and in-JVM peer restarts    *)
(* whose reload is visible in the next event of the same peer.             *)
(***************************************************************************)
EXTENDS base, Json, IOUtils, Sequences, TLC, FiniteSets, Integers

JsonFile == IF "JSON" \in DOMAIN IOEnv THEN IOEnv.JSON
            ELSE "../traces/follower-diff.ndjson"

AllLines == TLCEval(ndJsonDeserialize(JsonFile))
TraceLog == TLCEval(SelectSeq(AllLines, LAMBDA x :
                      "tag" \in DOMAIN x /\ x.tag = "trace" /\ "event" \in DOMAIN x))
ConfigLog == TLCEval(SelectSeq(AllLines, LAMBDA x :
                      "tag" \in DOMAIN x /\ x.tag = "config"))
ASSUME Len(TraceLog) > 0 /\ Len(ConfigLog) > 0

TraceScenario == TraceLog[1].scenario
\* Zab1_0Test ConversableFollower scenarios: the leader is a test double.
Fixture == TraceScenario \in {"follower-snap", "follower-diff"}
FixtureLeader == "s1"
FixtureFollower == "s0"

TxnIdOf(ep, ctr) == ep * 100000 + ctr

\* ---- constant overrides (see Trace.cfg) ----
TraceServers == UNION {{ConfigLog[k].servers[j] : j \in DOMAIN ConfigLog[k].servers}
                         : k \in 1..Len(ConfigLog)}
FixtureSeedTxns == IF Fixture THEN {TxnIdOf(1, 1), TxnIdOf(1, 2)} ELSE {}
TraceTxns == {TxnIdOf(TraceLog[k].event.txnEpoch, TraceLog[k].event.txnCounter) :
                 k \in {i \in 1..Len(TraceLog) : TraceLog[i].event.txnCounter > 0}}
             \cup FixtureSeedTxns
TraceMaxEpoch == LET es == {TraceLog[k].event.txnEpoch : k \in 1..Len(TraceLog)}
                           \cup {TraceLog[k].event.state.acceptedEpoch : k \in 1..Len(TraceLog)}
                 IN CHOOSE m \in es : \A x \in es : x <= m

TraceInputOK ==
    \A k \in 1..Len(TraceLog) :
        LET r == TraceLog[k] IN
        /\ r.scenario = TraceScenario
        /\ {"name", "node", "zxid", "txnCounter", "txnEpoch", "state", "peer", "aux"}
              \subseteq DOMAIN r.event
        /\ r.event.node \in TraceServers
        /\ {"acceptedEpoch", "currentEpoch", "role", "phase", "syncMode"}
              \subseteq DOMAIN r.event.state
ASSUME TraceInputOK

VARIABLE l
traceVars == <<allVars, l>>

Ev == TraceLog[l].event
IsEv(n) == l <= Len(TraceLog) /\ Ev.name = n
Node == Ev.node
Peer == Ev.peer
Aux == Ev.aux
St == Ev.state
Ctr == Ev.txnCounter
Ep == Ev.txnEpoch
TxnId == TxnIdOf(Ep, Ctr)
TxnEntry == EntryFor(TxnId, Ep)

\* zxid position of a history: counter 0 is an epoch marker (e.g. the
\* leader's lastProcessedZxid after Ldr:1536 setlastProcessedZxid).
PosMatches(h) == IF Ctr = 0 THEN LastEpoch(h) <= Ep
                 ELSE Len(h) > 0 /\ h[Len(h)] = TxnEntry
LastIs(h) == Len(h) > 0 /\ h[Len(h)] = TxnEntry

TraceRole(r) == IF Fixture /\ r = "looking" /\ Node = FixtureFollower
                THEN "following" ELSE r
TracePhase(p) == IF p = "synchronization" THEN "sync" ELSE p
PeerProbe == St.role /= "unknown"

\* Post-state comparison of every captured peer field.
PeerCheck ==
    PeerProbe =>
        /\ acceptedEpoch'[Node] = St.acceptedEpoch
        /\ currentEpoch'[Node] = St.currentEpoch
        /\ role'[Node] = TraceRole(St.role)
        /\ phase'[Node] = TracePhase(St.phase)
        /\ syncMode'[Node] = St.syncMode

Advance == l' = l + 1
Stutter == UNCHANGED allVars

MsgTo(kind, n, from, id) ==
    {m \in messages : m.kind = kind /\ m.to = n /\ m.from = from /\ m.id = id}

-----------------------------------------------------------------------------
(* Event wrappers *)

\* FLE.setPeerState emits PeerRoleChanged (QuorumPeer) and then ElectionWon
\* carrying the chosen leader id in the same call.
ChosenLeader ==
    LET ks == {k \in (l + 1)..Len(TraceLog) :
                  /\ TraceLog[k].event.node = Node
                  /\ TraceLog[k].event.name = "ElectionWon"}
    IN IF ks = {} THEN Nil
       ELSE TraceLog[CHOOSE k \in ks : \A j \in ks : k <= j].event.peer

TPeerRoleChanged ==
    /\ IsEv("PeerRoleChanged")
    /\ CASE TraceRole(St.role) = "leading" -> WinElection(Node)
         [] TraceRole(St.role) = "following" ->
              \E ld \in Server : /\ ChosenLeader \in {Nil, ld}
                                 /\ FollowLeader(Node, ld)
         [] OTHER -> /\ role[Node] = "looking" /\ Stutter
    /\ PeerCheck
    /\ Ctr >= 0 => PosMatches(applied'[Node])

TElectionWon ==
    /\ IsEv("ElectionWon")
    /\ Stutter
    /\ role[Node] = TraceRole(St.role)
    /\ leaderOf[Node] \in Server
    /\ Peer /= "" => leaderOf[Node] = Peer
    \* proposedZxid: the elected leader's vote zxid after a normal quorum, or
    \* the peer's own proposal when it adopts an existing leader
    \* (FLE:1055-1080 outofelection path).
    /\ PosMatches(applied[leaderOf[Node]]) \/ PosMatches(applied[Node])
    /\ PeerCheck

TPhaseChanged ==
    /\ IsEv("PhaseChanged")
    /\ CASE TracePhase(St.phase) = "election" ->
              IF role[Node] /= "looking" THEN BeginElection(Node)
              ELSE RestartElectionRound(Node)
         [] TracePhase(St.phase) = "discovery" ->
              IF role[Node] = "leading" THEN StartLeading(Node) ELSE StartFollowing(Node)
         [] TracePhase(St.phase) = "sync" ->
              IF role[Node] = "leading" THEN LeaderStartSync(Node) ELSE EnterSyncPhase(Node)
         [] TracePhase(St.phase) = "broadcast" ->
              IF role[Node] = "leading" THEN LeaderEnterBroadcast(Node) ELSE EnterBroadcast(Node)
         [] OTHER -> FALSE
    /\ PeerCheck
    /\ Ctr >= 0 => PosMatches(applied'[Node])

TAcceptedEpochPersisted ==
    /\ IsEv("AcceptedEpochPersisted")
    /\ IF role[Node] = "leading" THEN LeaderProposeEpoch(Node) ELSE AcceptEpoch(Node)
    /\ acceptedEpoch'[Node] = Ep
    /\ PeerCheck

TFollowerRegistered ==
    /\ IsEv("FollowerRegistered")
    /\ SendAckEpoch(Node)
    /\ PosMatches(applied[Node])
    /\ PeerCheck

TSyncModeChanged ==
    /\ IsEv("SyncModeChanged")
    /\ CASE St.syncMode = "DIFF" -> SyncDiff(Node)
         [] St.syncMode = "TRUNC" -> SyncTrunc(Node)
         [] St.syncMode = "SNAP" -> SyncSnap(Node)
         [] OTHER -> ClearSyncMode(Node)
    /\ PeerCheck

TSyncSelected ==
    /\ IsEv("SyncSelected")
    /\ Stutter
    /\ syncStarted[Node]
    /\ \/ Fixture
       \/ LET ld == syncSource[Node] IN
          \/ PosMatches(LeaderCommitHist(ld))
          \/ PosMatches(applied[ld])
          \/ PosMatches(applied[Node])
    /\ PeerCheck

TSnapshotInstalled ==
    /\ IsEv("SnapshotInstalled")
    /\ Stutter
    /\ syncMode[Node] = "SNAP"
    /\ PosMatches(applied[Node])
    /\ PeerCheck

\* Directive content was consumed by SyncDiff/SyncTrunc/SyncSnap; any other
\* proposal is a forwarded packet (ReceiveSyncProposal).
TSyncProposalReceived ==
    /\ IsEv("SyncProposalReceived")
    /\ IF Known(Node, TxnEntry)
       THEN Stutter
       ELSE \E m \in MsgTo("proposal", Node, syncSource[Node], TxnId) :
              ReceiveSyncProposal(m)
    /\ TxnEntry \in Range(applied'[Node]) \cup Range(proposed'[Node]) \cup Range(syncBuf'[Node])
    /\ PeerCheck

TSyncCommitReceived ==
    /\ IsEv("SyncCommitReceived")
    /\ CASE Aux = "buffered" ->
              IF TxnEntry \in Range(syncCommits[Node]) THEN Stutter
              ELSE \E m \in MsgTo("commit", Node, syncSource[Node], TxnId) :
                     ReceiveSyncCommit(m)
         [] Aux = "applied" ->
              IF TxnEntry \in Range(applied[Node]) THEN Stutter
              ELSE \E m \in MsgTo("commit", Node, syncSource[Node], TxnId) :
                     ReceiveSyncCommit(m)
         [] OTHER -> Stutter
    /\ Aux = "buffered" => TxnEntry \in Range(syncCommits'[Node])
    /\ Aux = "applied" => TxnEntry \in Range(applied'[Node])
    /\ PeerCheck

TCurrentEpochPersisted ==
    /\ IsEv("CurrentEpochPersisted")
    /\ IF role[Node] = "leading" THEN LeaderPersistEpoch(Node) ELSE PersistCurrentEpoch(Node)
    /\ currentEpoch'[Node] = Ep
    /\ PeerCheck

TZkStartup ==
    /\ IsEv("ZkStartup")
    /\ CASE Aux = "INITIAL" -> StartupWithoutServing(Node)
         [] Aux = "RUNNING" -> LeaderActivate(Node)
         [] OTHER -> FALSE
    /\ zkState'[Node] = Aux
    /\ PosMatches(applied[Node])

TProposalQueued ==
    /\ IsEv("ProposalQueued")
    /\ IF phase[Node] = "sync"
       THEN /\ syncBuf[Node] /= <<>> /\ Head(syncBuf[Node]) = TxnEntry
            /\ LogSyncProposal(Node)
       ELSE \E m \in MsgTo("proposal", Node, leaderOf[Node], TxnId) : ReceiveProposal(m)
    /\ TxnEntry \in Range(proposed'[Node])
    /\ PeerCheck

TNewLeaderAckSent ==
    /\ IsEv("NewLeaderAckSent")
    /\ SendNewLeaderAck(Node)
    /\ Ctr = 0 /\ Ep = acceptedEpoch[Node]
    /\ nlAckSent'[Node]
    /\ PeerCheck

TNewLeaderAckReceived ==
    /\ IsEv("NewLeaderAckReceived")
    /\ \E m \in messages :
          /\ m.kind = "nlack" /\ m.to = Node /\ m.from = Peer
          /\ Ctr = 0 /\ Ep = m.epoch
          /\ ReceiveNewLeaderAck(m)
    /\ zkState[Node] = "NONE" => Peer \in nlAcks'[Node]
    /\ PeerCheck

TUpToDateReceived ==
    /\ IsEv("UpToDateReceived")
    /\ Stutter
    /\ nlAckSent[Node] /\ zkState[Node] = "INITIAL"
    /\ UpToDateReady(Node)
    /\ PeerCheck

TBroadcastReady ==
    /\ IsEv("BroadcastReady")
    /\ StartServing(Node)
    /\ zkState'[Node] = "RUNNING"
    /\ PosMatches(applied[Node])
    /\ PeerCheck

TCommitDelivered ==
    /\ IsEv("CommitDelivered")
    /\ IF phase[Node] = "sync"
       THEN /\ syncCommits[Node] /= <<>> /\ Head(syncCommits[Node]) = TxnEntry
            /\ CommitSyncPacket(Node)
       ELSE \E m \in MsgTo("commit", Node, leaderOf[Node], TxnId) : ReceiveCommit(m)
    /\ LastIs(committed'[Node])
    /\ PeerCheck

TTxnAppended == IsEv("TxnAppended") /\ AppendOne(Node) /\ LastIs(appended'[Node])
TTxnDurable == IsEv("TxnDurable") /\ FsyncOne(Node) /\ LastIs(durable'[Node])
TTxnApplied == IsEv("TxnApplied") /\ ApplyOne(Node) /\ LastIs(applied'[Node])

TLeaderProposed ==
    /\ IsEv("LeaderProposed")
    /\ Propose(Node, TxnId)
    /\ LastIs(proposed'[Node])
    /\ PeerCheck

TAckReceived ==
    /\ IsEv("AckReceived")
    /\ IF Peer = Node
       THEN /\ Stutter /\ Node \in acked[TxnId]
       ELSE /\ \E m \in MsgTo("ack", Node, Peer, TxnId) : DeliverAck(m)
            /\ Peer \in acked'[TxnId]
    /\ PeerCheck

TLeaderCommitted ==
    /\ IsEv("LeaderCommitted")
    /\ Commit(Node, TxnId)
    /\ LastIs(committed'[Node])
    /\ PeerCheck

TraceStep ==
    /\ \/ TPeerRoleChanged \/ TElectionWon \/ TPhaseChanged
       \/ TAcceptedEpochPersisted \/ TFollowerRegistered
       \/ TSyncModeChanged \/ TSyncSelected \/ TSnapshotInstalled
       \/ TSyncProposalReceived \/ TSyncCommitReceived
       \/ TCurrentEpochPersisted \/ TZkStartup \/ TProposalQueued
       \/ TNewLeaderAckSent \/ TNewLeaderAckReceived \/ TUpToDateReceived
       \/ TBroadcastReady \/ TCommitDelivered
       \/ TTxnAppended \/ TTxnDurable \/ TTxnApplied
       \/ TLeaderProposed \/ TAckReceived \/ TLeaderCommitted
    /\ Advance

-----------------------------------------------------------------------------
(* Silent steps (never advance l) *)

\* FastLeaderElection notifications are not probed: votes may be cast only
\* while the current event is the FLE decision of some peer.
SilentVote ==
    /\ IsEv("PeerRoleChanged") /\ TraceRole(St.role) \in {"leading", "following"}
    /\ \E v, c \in Server : CastVote(v, c)

\* Leader.processAck returns before addAck (no probe) for acks of already
\* committed zxids or acks the leader does not count.
SilentIgnoredAck ==
    \E m \in messages :
        /\ m.kind = "ack"
        /\ \/ EntryFor(m.id, m.epoch) \in Range(committed[m.to])
           \/ ~(role[m.to] = "leading" /\ zkState[m.to] = "RUNNING"
                /\ currentEpoch[m.to] = m.epoch)
        /\ DeliverAck(m)

\* In-JVM QuorumPeer shutdown + new QuorumPeer start (QuorumPeerTestBase
\* MainThread.shutdown/start): no probe; visible as a reloaded data tree in
\* the next event of the same peer.
NeedsReboot(n) ==
    /\ l <= Len(TraceLog) /\ Node = n
    /\ Ev.name = "PeerRoleChanged" /\ TraceRole(St.role) \in {"leading", "following"}
    /\ Ctr >= 0 /\ ~PosMatches(applied[n])
SilentReboot ==
    \/ \E n \in Server : /\ up[n] /\ role[n] = "looking" /\ NeedsReboot(n)
                         /\ Crash(n)
    \/ \E n \in Server : /\ ~up[n] /\ NeedsReboot(n) /\ Restart(n)

\* Zab1_0Test fixture leader: it writes PROPOSAL/COMMIT packets itself and
\* reads the learner's ACKs in test code.  This is a test-double environment
\* step (no implementation code runs on the fixture side).
FixtureLeaderSend ==
    /\ Fixture
    /\ IsEv("SyncProposalReceived")
    /\ ~Known(Node, TxnEntry)
    /\ MsgTo("proposal", Node, FixtureLeader, TxnId) = {}
    /\ proposed' = [proposed EXCEPT ![FixtureLeader] = Append(@, TxnEntry)]
    /\ queued' = [queued EXCEPT ![FixtureLeader] = Append(@, TxnEntry)]
    /\ committed' = [committed EXCEPT ![FixtureLeader] = Append(@, TxnEntry)]
    /\ commitCertified' = [commitCertified EXCEPT ![TxnId] = TRUE]
    /\ usedTxn' = usedTxn \cup {TxnId}
    /\ messages' = messages \cup
         {[kind |-> k, from |-> FixtureLeader, to |-> Node, id |-> TxnId,
           epoch |-> Ep] : k \in {"proposal", "commit"}}
    /\ UNCHANGED <<up, electionVars, appended, durable, applied, snapshot,
                    acked, syncVars, rollbackAuthorized, zkState>>
FixtureLeaderReads ==
    /\ Fixture
    /\ \E m \in messages :
         /\ m.to = FixtureLeader /\ m.kind \in {"nlack", "ack"}
         /\ IF m.kind = "nlack" THEN ReceiveNewLeaderAck(m) ELSE DeliverAck(m)

TraceSilent ==
    /\ l <= Len(TraceLog)
    /\ \/ SilentVote \/ SilentIgnoredAck \/ SilentReboot
       \/ FixtureLeaderSend \/ FixtureLeaderReads
    /\ UNCHANGED l

TraceNext == TraceStep \/ TraceSilent

-----------------------------------------------------------------------------
(* Initial state: Init for real ensembles; seeded fixture leader for the    *)
(* Zab1_0Test conversations (established epoch-1 leader that is serving).   *)
FixtureHist ==
    IF TraceScenario = "follower-diff"
    THEN <<EntryFor(TxnIdOf(1, 2), 1)>>   \* the only record the fixture sends
    ELSE <<EntryFor(TxnIdOf(1, 1), 1)>>   \* snapshot content (SNAP zxid 0x100000001)

TraceInit ==
    /\ l = 1
    /\ IF ~Fixture THEN Init
       ELSE
         LET ld == FixtureLeader
             fo == FixtureFollower
             h == FixtureHist IN
         /\ up = [s \in Server |-> TRUE]
         /\ role = [s \in Server |-> IF s = ld THEN "leading"
                                     ELSE IF s = fo THEN "following" ELSE "looking"]
         /\ phase = [s \in Server |-> IF s = ld THEN "broadcast" ELSE "election"]
         /\ leaderOf = [s \in Server |-> IF s \in {ld, fo} THEN ld ELSE Nil]
         /\ acceptedEpoch = [s \in Server |-> IF s = ld THEN 1 ELSE 0]
         /\ currentEpoch = [s \in Server |-> IF s = ld THEN 1 ELSE 0]
         /\ votes = [s \in Server |-> {s}]
         /\ leadersByEpoch = [e \in Epoch |-> IF e = 1 THEN {ld} ELSE {}]
         /\ proposed = [s \in Server |-> IF s = ld THEN h ELSE <<>>]
         /\ queued = [s \in Server |-> IF s = ld THEN h ELSE <<>>]
         /\ appended = [s \in Server |-> IF s = ld THEN h ELSE <<>>]
         /\ durable = [s \in Server |-> IF s = ld THEN h ELSE <<>>]
         /\ committed = [s \in Server |-> IF s = ld THEN h ELSE <<>>]
         /\ applied = [s \in Server |-> IF s = ld THEN h ELSE <<>>]
         /\ snapshot = [s \in Server |-> <<>>]
         /\ acked = [t \in Txn |-> IF t \in TxnIds(h) THEN {ld} ELSE {}]
         /\ commitCertified = [t \in Txn |-> t \in TxnIds(h)]
         /\ messages = {}
         /\ syncMode = [s \in Server |-> "NONE"]
         /\ syncSource = [s \in Server |-> Nil]
         /\ syncJustified = [s \in Server |-> FALSE]
         /\ usedTxn = TxnIds(h)
         /\ rollbackAuthorized = [s \in Server |-> FALSE]
         /\ epochSet = [s \in Server |-> s = ld]
         /\ syncBuf = [s \in Server |-> <<>>]
         /\ syncCommits = [s \in Server |-> <<>>]
         /\ syncStarted = [s \in Server |-> FALSE]
         /\ pending = [s \in Server |-> <<>>]
         /\ nlAckSent = [s \in Server |-> FALSE]
         /\ nlAcks = [s \in Server |-> {}]
         /\ zkState = [s \in Server |-> IF s = ld THEN "RUNNING" ELSE "NONE"]

TraceSpec == TraceInit /\ [][TraceNext]_traceVars /\ WF_traceVars(TraceNext)

TraceMatched == <>(l > Len(TraceLog))

\* Diagnostic: furthest consumed event.  With STOP=<k> in the environment,
\* a violation of CursorBelowStop proves event k-1 was consumed.
StopAt == IF "STOP" \in DOMAIN IOEnv THEN atoi(IOEnv.STOP) ELSE Len(TraceLog) + 1
CursorBelowStop == l < StopAt

=============================================================================
