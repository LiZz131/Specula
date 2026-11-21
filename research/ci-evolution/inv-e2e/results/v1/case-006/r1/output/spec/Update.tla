---------------------------- MODULE Update ----------------------------
(***************************************************************************
 * Update-focused checking lens for the `update` revision.
 *
 * Source delta (read_only.go:100-104): readOnly.advance now deletes each
 * released request from pendingReadIndex using its real key
 * string(req.Entries[0].Data); the old code used string(req.Context), which
 * never matches a MsgReadIndex key, so released entries used to stay pending.
 *
 * Behaviour lives only in base.tla/MC.tla.  This module selects the changed
 * MC Action, the unchanged Actions that produce, consume, reset, or expose its
 * result, an explicit environment for the omitted fault Actions, and the
 * update-specific read properties.
 *************************************************************************)
EXTENDS MC, UpdateProps

(***************************************************************************
 * Affected Actions.
 * reference: base!HandleHeartbeatResponse
 * code: read_only.go:78-109 (advance, changed delete key),
 *       read_only.go:64-73 (recvAck), raft.go:903-932
 *************************************************************************)
AffectedActions ==
    \E i \in Server, m \in messages : MCHandleHeartbeatResponse(i, m)

(***************************************************************************
 * Interaction Actions (concrete).
 *  - producers of pending read state / acknowledgements:
 *      base!ClientReadIndex, base!HandleReadIndexRequest, base!ForwardReadIndex
 *      (raft.go:824-838, 1068-1074; read_only.go:52-58 dedup now re-admits a
 *      released context), base!BroadcastHeartbeat (raft.go:457-464, last
 *      pending ctx), base!HandleHeartbeat (raft.go:1099-1102 echoes ctx).
 *  - consumers of released reads: base!HandleReadIndexResponse
 *    (raft.go:1075-1080), base!ReadyPublish (node.go:506-525),
 *    base!ReadyAdvance (Ready re-arm, node.go:374-383).
 *  - readOnly reset sites (raft.go:510 via becomeFollower/Candidate/Leader):
 *      base!Campaign, base!HandleVoteRequest, base!BecomeLeader,
 *      base!HandleAppendEntries, base!HandleHeartbeat, base!CheckQuorum.
 *  - leadership/commit context that makes a stale acknowledgement harmful:
 *      base!HandleVoteResponse, base!ClientProposal,
 *      base!HandleAppendResponse (raft.go:475-486 commit watermark).
 *************************************************************************)
InteractionActions ==
    \/ \E i \in Server, c \in ReadContexts, r \in Server :
          MCClientReadIndex(i, c, r)
    \/ \E i \in Server, c \in ReadContexts : MCForwardReadIndex(i, c)
    \/ \E i \in Server, m \in messages : MCHandleReadIndexRequest(i, m)
    \/ \E i \in Server : MCBroadcastHeartbeat(i)
    \/ \E i \in Server, m \in messages : MCHandleHeartbeat(i, m)
    \/ \E i \in Server, m \in messages : MCHandleReadIndexResponse(i, m)
    \/ \E i \in Server : MCReadyPublish(i)
    \/ \E i \in Server : MCReadyAdvance(i)
    \/ \E i \in Server : MCCampaign(i)
    \/ \E i \in Server, m \in messages : MCHandleVoteRequest(i, m)
    \/ \E i \in Server, m \in messages : MCHandleVoteResponse(i, m)
    \/ \E i \in Server : MCBecomeLeader(i)
    \/ \E i \in Server, v \in Values : MCClientProposal(i, v)
    \/ \E i \in Server, m \in messages : MCHandleAppendEntries(i, m)
    \/ \E i \in Server, m \in messages : MCHandleAppendResponse(i, m)
    \/ \E i \in Server : MCCheckQuorum(i)

(***************************************************************************
 * Omitted context: crash, restart, and message loss.  They do not touch the
 * changed advance path, but Restart also clears readOnly (newRaft,
 * raft.go:297) and loss can strand acknowledgements, so the open spec keeps
 * their effect on update-visible state as EnvUpdate.
 * reference: base!Crash, base!Restart, base!LoseMessage
 *************************************************************************)
OmittedContextActions ==
    \/ \E i \in Server : MCCrash(i)
    \/ \E i \in Server : MCRestart(i)
    \/ \E m \in messages : MCLoseMessage(m)

(***************************************************************************
 * EnvUpdate: rely for the omitted context.  Any set of live nodes may stop,
 * any set of stopped nodes may come back with only their Ready-persisted state
 * (no readOnly, no produced reads, follower), and any subset of in-flight
 * messages may disappear.  The environment never persists, commits, elects,
 * publishes, or releases reads, and never adds messages.  It is weaker than
 * the concrete Actions (simultaneous faults), not a copy of them.
 *************************************************************************)
EnvUpdate ==
    \E down \in SUBSET {i \in Server : alive[i]},
       up \in SUBSET {i \in Server : ~alive[i]},
       kept \in SUBSET messages :
        /\ alive' = [i \in Server |->
                       IF i \in down THEN FALSE
                       ELSE IF i \in up THEN TRUE ELSE alive[i]]
        /\ term' = [i \in Server |-> IF i \in up THEN durableTerm[i] ELSE term[i]]
        /\ vote' = [i \in Server |-> IF i \in up THEN durableVote[i] ELSE vote[i]]
        /\ role' = [i \in Server |-> IF i \in up THEN Follower ELSE role[i]]
        /\ leader' = [i \in Server |-> IF i \in up THEN Nil ELSE leader[i]]
        /\ logs' = [i \in Server |-> IF i \in up THEN durableLogs[i] ELSE logs[i]]
        /\ commitIndex' = [i \in Server |->
                             IF i \in up THEN durableCommit[i] ELSE commitIndex[i]]
        /\ appliedIndex' = [i \in Server |->
                              IF i \in up
                              THEN Min2(appliedIndex[i], durableCommit[i])
                              ELSE appliedIndex[i]]
        /\ votesGranted' = [i \in Server |->
                              IF i \in up THEN {} ELSE votesGranted[i]]
        /\ recentActive' = [i \in Server |->
                              IF i \in up THEN [j \in Server |-> FALSE]
                              ELSE recentActive[i]]
        /\ pendingReads' = [i \in Server |->
                              IF i \in up THEN EmptyReadOnly ELSE pendingReads[i]]
        /\ readQueue' = [i \in Server |->
                           IF i \in up THEN <<>> ELSE readQueue[i]]
        /\ producedReads' = [i \in Server |->
                               IF i \in up THEN <<>> ELSE producedReads[i]]
        /\ readyOutstanding' = [i \in Server |->
                                  IF i \in up THEN FALSE ELSE readyOutstanding[i]]
        /\ messages' = kept
        /\ scenarioSeen' = [scenarioSeen EXCEPT
                              !.crash = @ \/ (down /= {}),
                              !.restart = @ \/ (up /= {}),
                              !.loss = @ \/ (kept /= messages)]
        /\ UNCHANGED <<durableVars, matchIndex, nextIndex, publishedReads,
                        leaderHistory, commitHistory, readReleases>>

(***************************************************************************
 * Update properties: PendingMatchesQueue, ReadQueueDistinct,
 * ReadDeliveryJustifiedFresh, ReadIndexFreshness, UpdateSafety.
 * They are defined in UpdateProps.tla (EXTENDS base only) so that Trace.tla can
 * evaluate the same definitions during replay; this module owns them.
 *************************************************************************)

(***************************************************************************
 * Entry points.
 *************************************************************************)
\* Full: update properties over the complete MCNext (MCSpec), see
\* Update_full.cfg.  No separate definition is needed.

\* Concrete focused: changed Action plus concrete interactions only.
FocusedNext ==
    /\ Cardinality(messages) <= MaxMsgBufferLimit
    /\ \/ AffectedActions
       \/ InteractionActions

FocusedSpec == MCInit /\ [][FocusedNext]_mcVars

\* Open focused: concrete focus plus the bounded environment rely.
OpenEnv ==
    /\ faultCounters.crash < MaxCrashLimit
    /\ EnvUpdate
    /\ faultCounters' = [faultCounters EXCEPT !.crash = @ + 1]

OpenNext ==
    /\ Cardinality(messages) <= MaxMsgBufferLimit
    /\ \/ AffectedActions
       \/ InteractionActions
       \/ OpenEnv

OpenSpec == MCInit /\ [][OpenNext]_mcVars

\* Discharge: every omitted real context step satisfies the rely (frame
\* conditions are the UNCHANGED clauses of EnvUpdate).  Checked over MCSpec.
DischargeContext ==
    [][OmittedContextActions => EnvUpdate]_mcVars

\* Negative control for the discharge check (non-vacuity only, never a rely):
\* a deliberately too-strong rely that forbids message loss must be refuted by
\* the omitted LoseMessage Action.  Expected result: action property violated.
DischargeNegativeControl ==
    [][OmittedContextActions => (EnvUpdate /\ messages' = messages)]_mcVars

\* Scenario-guided hunt constraint for US4 (search pruning only; it never adds
\* behaviour, so every path TLC reports is an ordinary MCSpec/FocusedSpec
\* behaviour from MCInit).  It keeps only paths shaped like the US4 question:
\* local reads, at most two leaderships, the second leadership only after a
\* read was released, and the second read only after a newer-term commit.
US4Guide ==
    /\ StateConstraint
    /\ \A m \in messages : m.mtype \notin {MsgReadIndex, MsgReadIndexResp}
    /\ Cardinality(leaderHistory) <= 2
    /\ Cardinality(leaderHistory) = 2 => scenarioSeen.readQuorum
    /\ faultCounters.read = 2 =>
          /\ Cardinality(leaderHistory) = 2
          /\ CommitWatermark >= 2

\* Scenario monitor for the update interaction (observation only).
UpdateScenarioStage ==
    [freed |-> scenarioSeen.readFreed,
     reenqueue |-> scenarioSeen.readReenqueue,
     reuseRelease |-> scenarioSeen.reuseRelease,
     resetDropsRead |-> scenarioSeen.resetDropsRead]

=============================================================================
