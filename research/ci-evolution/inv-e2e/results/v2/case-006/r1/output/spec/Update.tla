------------------------------ MODULE Update ------------------------------
(***************************************************************************
 * Update-focused checking lens for the `update` revision (artifact
 * c780d355).  All behavior is owned by base.tla/MC.tla; this module only
 * selects reference Actions, defines the omitted-context environment, and
 * states update-specific properties.
 *
 * Source delta (read_only.go:100-105, readOnly.advance):
 *   old: delete(ro.pendingReadIndex, string(rs.req.Context))
 *   new: delete(ro.pendingReadIndex, string(rs.req.Entries[0].Data))
 * addRequest keys the map by string(m.Entries[0].Data) (read_only.go:53), and
 * MsgReadIndex requests carry the caller context only in Entries[0].Data
 * (node.go:502-504, rawnode.go:262-264), so exact-old never freed a released
 * request while the update frees every released request.
 *
 * Consequences in the reference (base.tla UPDATE-MAP comments):
 *   - HandleHeartbeatResponse clears every released context (affected).
 *   - ProcessReadIndex's duplicate guard (read_only.go:54-56) no longer
 *     blocks a context released earlier in the same leader term, so the
 *     same caller context can be registered again (affected enablement).
 *   - a late acknowledgement for a released context is now ignored
 *     (read_only.go:65-68) unless the context was registered again, in which
 *     case it is counted for the new registration (interaction under test).
 *   - HandleReadIndexResponse no longer finds the leader's pending entry;
 *     its justification comes from servedReads (repair R2).
 *************************************************************************)
EXTENDS MC

SeqToSet(s) == {s[k] : k \in 1..Len(s)}

(***************************************************************************
 * Affected Actions.
 *************************************************************************)
\* reference: base!HandleHeartbeatResponse
\* code: read_only.go:78-109 advance (line 103 changed); raft.go:915-932
\* reference: base!ProcessReadIndex via ClientReadIndex/HandleReadIndexRequest
\* code: read_only.go:52-59 addRequest; raft.go:824-853
\* reference: base!HandleReadIndexResponse (repairs R2/R3)
\* code: raft.go:1075-1080; raft.go:679-735
AffectedActions ==
    \/ \E i \in Server, m \in messages : MCHandleHeartbeatResponse(i, m)
    \/ \E i \in Server, c \in ReadContexts, r \in Server :
          MCClientReadIndex(i, c, r)
    \/ \E i \in Server, m \in messages : MCHandleReadIndexRequest(i, m)
    \/ \E i \in Server, m \in messages : MCHandleReadIndexResponse(i, m)

(***************************************************************************
 * Interaction Actions (concrete): producers of acknowledgements and contexts,
 * consumers of released reads, delay/loss, and every role transition that
 * calls raft.reset() and therefore recreates readOnly (repair R1).
 *************************************************************************)
\* reference: base!HandleHeartbeat (ack producer, raft.go:1112-1115)
\* reference: base!BroadcastHeartbeat (lastPendingRequestCtx, raft.go:457-464)
\* reference: base!ForwardReadIndex (raft.go:1068-1074)
\* reference: base!ReadyPublish/ReadyAdvance (node.go:506-525)
\* reference: base!LoseMessage (rafttest/network.go:81-119)
\* reference: base!Campaign/HandleVoteRequest/HandleVoteResponse/BecomeLeader/
\*            HandleAppendEntries/HandleAppendResponse/CheckQuorum
\*            (raft.go:489-511 reset; raft.go:570-622; raft.go:791-796)
InteractionActions ==
    \/ \E i \in Server, m \in messages : MCHandleHeartbeat(i, m)
    \/ \E i \in Server : MCBroadcastHeartbeat(i)
    \/ \E i \in Server, c \in ReadContexts : MCForwardReadIndex(i, c)
    \/ \E i \in Server : MCReadyPublish(i)
    \/ \E i \in Server : MCReadyAdvance(i)
    \/ \E m \in messages : MCLoseMessage(m)
    \/ \E i \in Server : MCCampaign(i)
    \/ \E i \in Server, m \in messages : MCHandleVoteRequest(i, m)
    \/ \E i \in Server, m \in messages : MCHandleVoteResponse(i, m)
    \/ \E i \in Server : MCBecomeLeader(i)
    \/ \E i \in Server, m \in messages : MCHandleAppendEntries(i, m)
    \/ \E i \in Server, m \in messages : MCHandleAppendResponse(i, m)
    \/ \E i \in Server : MCCheckQuorum(i)

(***************************************************************************
 * Omitted context: ClientProposal, Crash, Restart.
 *   - ClientProposal changes only the leader's log/progress and adds MsgApp;
 *     no update-visible variable.  Its only indirect update-relevant effect
 *     (new committed entries) is already produced concretely by leader no-op
 *     entries (BecomeLeader + replication + HandleAppendResponse).
 *   - Crash flips liveness only.  Restart reloads durable state and recreates
 *     all volatile read state (node restart -> newRaft -> newReadOnly).
 *************************************************************************)
OmittedContextActions ==
    \/ \E i \in Server, v \in Values : MCClientProposal(i, v)
    \/ \E i \in Server : MCCrash(i)
    \/ \E i \in Server : MCRestart(i)

ReadMsgTypes == {MsgHeartbeat, MsgHeartbeatResp, MsgReadIndex,
                 MsgReadIndexResp}

ReadStateOf(i) == <<pendingReads[i], readQueue[i], producedReads[i]>>
ServerVisible(i) == <<pendingReads[i], readQueue[i], producedReads[i],
                      role[i], leader[i], term[i], commitIndex[i]>>

\* Rely on omitted context, stated only over update-visible state.  An
\* omitted step either leaves every server's update-visible state unchanged,
\* or (restart) clears one server's volatile read state, demotes it to a
\* non-leader without a known leader, and does not raise its term or commit
\* index.  It never creates read-protocol messages, never consumes messages,
\* and never touches the global read history.
EnvRely ==
    /\ UNCHANGED <<publishedReads, servedReads, readStamp>>
    /\ messages \subseteq messages'
    /\ \A m \in messages' \ messages : m.mtype \notin ReadMsgTypes
    /\ \E i \in Server :
         /\ \A j \in Server \ {i} : ServerVisible(j)' = ServerVisible(j)
         /\ \/ ServerVisible(i)' = ServerVisible(i)
            \/ /\ pendingReads'[i] = EmptyPendingMap
               /\ readQueue'[i] = <<>>
               /\ producedReads'[i] = <<>>
               /\ role'[i] = Follower
               /\ leader'[i] = Nil
               /\ term'[i] <= term[i]
               /\ commitIndex'[i] <= commitIndex[i]

\* Constructive environment for the open focused spec: an atomic, counter-
\* bounded crash-restart that recovers from the last Ready-persisted state.
\* It over-approximates Crash;Restart on update-visible state (the dead window
\* is subsumed by concrete message delay/loss).
EnvCrashRestart(i) ==
    /\ faultCounters.crash < MaxCrashLimit
    /\ alive[i]
    /\ term' = [term EXCEPT ![i] = durableTerm[i]]
    /\ vote' = [vote EXCEPT ![i] = durableVote[i]]
    /\ role' = [role EXCEPT ![i] = Follower]
    /\ leader' = [leader EXCEPT ![i] = Nil]
    /\ logs' = [logs EXCEPT ![i] = durableLogs[i]]
    /\ commitIndex' = [commitIndex EXCEPT ![i] = durableCommit[i]]
    /\ appliedIndex' = [appliedIndex EXCEPT ![i] = Min2(@, durableCommit[i])]
    /\ votesGranted' = [votesGranted EXCEPT ![i] = {}]
    /\ recentActive' = [recentActive EXCEPT ![i] = [j \in Server |-> FALSE]]
    /\ pendingReads' = [pendingReads EXCEPT ![i] = EmptyPendingMap]
    /\ readQueue' = [readQueue EXCEPT ![i] = <<>>]
    /\ producedReads' = [producedReads EXCEPT ![i] = <<>>]
    /\ readyOutstanding' = [readyOutstanding EXCEPT ![i] = FALSE]
    /\ scenarioSeen' = [scenarioSeen EXCEPT !.crash = TRUE, !.restart = TRUE]
    /\ faultCounters' = [faultCounters EXCEPT !.crash = @ + 1]
    /\ UNCHANGED <<durableVars, matchIndex, nextIndex, messages,
                    publishedReads, alive, leaderHistory, commitHistory,
                    readGhostVars>>

EnvUpdate == \E i \in Server : EnvCrashRestart(i)

FocusedNext ==
    /\ Cardinality(messages) <= MaxMsgBufferLimit
    /\ \/ AffectedActions
       \/ InteractionActions

OpenUpdateNext ==
    /\ Cardinality(messages) <= MaxMsgBufferLimit
    /\ \/ AffectedActions
       \/ InteractionActions
       \/ EnvUpdate

FocusedSpec == MCInit /\ [][FocusedNext]_mcVars
OpenSpec == MCInit /\ [][OpenUpdateNext]_mcVars

\* Discharge: every omitted real context step satisfies the rely.  Checked
\* over the complete MCSpec, so all reachable omitted steps are covered.
DischargeContext == [][OmittedContextActions => EnvRely]_mcVars
\* Consistency: the constructive environment stays within the rely.
EnvWithinRely == [][EnvUpdate => EnvRely]_mcVars

(***************************************************************************
 * Scenario U3 directed hunt.  U3Next only RESTRICTS which MC wrapper steps
 * are enabled (phase guards); it defines no behavior, so every path it finds
 * is an MCNext path (checked again by spec/tools/make_admit.py).  Roles are
 * fixed by CHOOSE, so configs using it must not declare SYMMETRY.
 *   phase 1: OldLdr is elected and serves one read (some ack may stay in
 *            flight);
 *   phase 2: NewLdr campaigns in a higher term while OldLdr receives no
 *            message of a higher term (partition), and commits;
 *   phase 3: OldLdr registers the read context again.
 *************************************************************************)
OldLdr == CHOOSE s \in Server : TRUE
NewLdr == CHOOSE s \in Server \ {OldLdr} : TRUE
HigherTermCommitted == \E ch \in commitHistory : ch.commitTerm > term[OldLdr]

U3Next ==
    /\ Cardinality(messages) <= MaxMsgBufferLimit
    /\ \/ /\ term[OldLdr] = 0
          /\ MCCampaign(OldLdr)
       \/ /\ servedReads /= {}
          /\ MCCampaign(NewLdr)
       \/ /\ (servedReads = {} \/ HigherTermCommitted)
          /\ \E c \in ReadContexts : MCClientReadIndex(OldLdr, c, OldLdr)
       \/ \E i \in Server, m \in messages :
            /\ ~(i = OldLdr /\ m.term > term[OldLdr])
            /\ \/ MCHandleVoteRequest(i, m)
               \/ MCHandleVoteResponse(i, m)
               \/ MCHandleAppendEntries(i, m)
               \/ MCHandleAppendResponse(i, m)
               \/ MCHandleHeartbeat(i, m)
               \/ MCHandleHeartbeatResponse(i, m)
       \/ \E i \in Server : MCBecomeLeader(i)
       \/ \E i \in Server : MCReadyPublish(i)
       \/ \E i \in Server : MCReadyAdvance(i)

U3Spec == MCInit /\ [][U3Next]_mcVars

(***************************************************************************
 * Update-specific properties.
 *************************************************************************)

\* REQ-EVIDENCE UpdPendingMatchesQueue
\* intent:   on every server, the contexts held in pendingReadIndex are exactly the contexts queued in readIndexQueue; a released read request leaves both structures.
\* status:   requirement
\* evidence: test new-source/raft_test.go:1249-1250 TestRaftFreesReadOnlyMem "ensures raft will free read request from readOnly readIndexQueue and pendingReadIndex map" -> a released request is removed from both the queue and the map
\* evidence: test new-source/raft_test.go:1287-1295 TestRaftFreesReadOnlyMem "len(pendingReadIndex) = %v, want 0" / "found context %v in pendingReadIndex, want none" -> after the quorum acknowledgement the map holds no entry for the released context
\* evidence: impl source/read_only.go:89-92 "panic(\"cannot find corresponding read state from pending map\")" -> the queue must never name a context absent from the map
\* evidence: impl source/read_only.go:103 "delete(ro.pendingReadIndex, string(rs.req.Entries[0].Data))"
\* watch:    read_only.go:addRequest; read_only.go:advance; raft.go:reset; raft.go:stepLeader
\* verified: update (c780d355)
\* note:     new property added by the update's own test; the exact-old suite intentionally preserved stale map entries, which this property rejects (separating state E1 in spec/invariant-evidence.json).
\* review:   ok
UpdPendingMatchesQueue ==
    \A i \in Server :
        {c \in ReadContexts : pendingReads[i][c].active} = SeqToSet(readQueue[i])

\* REQ-EVIDENCE UpdReadAckFresh
\* intent:   with the safe read-only option, every read request a leader releases is confirmed by a quorum of acknowledgements generated at or after that request's own registration (the leader's own acknowledgement included); an acknowledgement produced for an earlier request with the same context does not count.
\* status:   requirement
\* evidence: contract source/raft.go:47-48 "ReadOnlySafe guarantees the linearizability of the read only request by communicating with the quorum." -> the quorum communication must confirm this request
\* evidence: doc source/README.md:28 "leader checks with quorum and bypasses Raft log before processing read-only queries" -> the quorum check happens for the query being processed
\* evidence: test new-source/raft_test.go:1260-1261 TestRaftFreesReadOnlyMem "leader starts linearizable read request. more info: raft dissertation 6.4, step 2." -> the read request is registered first
\* evidence: test new-source/raft_test.go:1283-1285 TestRaftFreesReadOnlyMem "heartbeat responses from majority of followers ... acknowledge the authority of the leader. more info: raft dissertation 6.4, step 3." -> acknowledgements that confirm the request come after its registration
\* evidence: contract source/node.go:155-157 "Once the application advances further than the read index, any linearizable read requests issued before the read request can be processed safely." -> the read index is safe only if leadership was confirmed after the request was issued
\* evidence: impl source/read_only.go:64-73 recvAck keys acknowledgements only by string(m.Context)
\* watch:    read_only.go:addRequest; read_only.go:recvAck; read_only.go:advance; raft.go:stepLeader; raft.go:handleHeartbeat; raft.go:bcastHeartbeatWithCtx; raft.go:reset
\* verified: update (c780d355)
\* note:     instance-bound strengthening of ReadDeliveryJustified (which only counts acknowledgements). Ghost: the response's gstamp is the global registration stamp at generation; a registration takes the next stamp.
\* review:   ok
UpdReadAckFresh ==
    \A sr \in servedReads : Cardinality(sr.freshAcks) >= Quorum

\* REQ-EVIDENCE UpdReadIndexLinearizable
\* intent:   with the safe read-only option, the read index a leader returns for a request is at least the index of every log entry committed anywhere before that request was registered at the leader.
\* status:   requirement
\* evidence: contract source/node.go:155-157 "Once the application advances further than the read index, any linearizable read requests issued before the read request can be processed safely." -> applying through the read index must cover every write committed before the read was issued
\* evidence: contract source/raft.go:47-48 "ReadOnlySafe guarantees the linearizability of the read only request by communicating with the quorum."
\* evidence: doc source/README.md:27 "Efficient linearizable read-only queries served by both the leader and followers"
\* evidence: impl source/raft.go:836 "r.readOnly.addRequest(r.raftLog.committed, m)"
\* watch:    read_only.go:addRequest; read_only.go:recvAck; read_only.go:advance; raft.go:stepLeader; raft.go:reset; log.go:maybeCommit
\* verified: update (c780d355)
\* note:     registration time is later than the caller's issue time, so this is at least as strong as the contract for forwarded reads. Ghost gcommit = MaxCommitted at registration, from the leader-side commitHistory.
\* review:   ok
UpdReadIndexLinearizable ==
    \A sr \in servedReads : sr.index >= sr.gcommit

\* Control: an unaffected core safety property kept enabled in update checks.
UpdControlElectionSafety == ElectionSafety

(***************************************************************************
 * Reachability canaries (expected violations are witnesses, not bugs).
 *************************************************************************)
\* REQ-EVIDENCE HuntReadFreed
\* intent:   reachability canary: no release has yet freed a pending read; expected to be violated.
\* status:   model-internal
\* verified: update (c780d355)
\* review:   ok
HuntReadFreed == ~scenarioSeen.readFreed
\* REQ-EVIDENCE HuntReadReuse
\* intent:   reachability canary: no leader has yet registered a context it already released in the same term; expected to be violated.
\* status:   model-internal
\* verified: update (c780d355)
\* review:   ok
HuntReadReuse == ~scenarioSeen.readReuse
\* REQ-EVIDENCE HuntReuseServed
\* intent:   reachability canary: no leader has yet released the same context twice in one term; expected to be violated.
\* status:   model-internal
\* verified: update (c780d355)
\* review:   ok
HuntReuseServed ==
    ~\E a, b \in servedReads :
        /\ a /= b /\ a.leader = b.leader /\ a.term = b.term /\ a.ctx = b.ctx
\* REQ-EVIDENCE HuntStaleAck
\* intent:   reachability canary: no acknowledgement generated before its pending request's registration has yet been recorded; expected to be violated where context reuse and delay are enabled.
\* status:   model-internal
\* verified: update (c780d355)
\* review:   ok
HuntStaleAck == ~scenarioSeen.staleAck
\* REQ-EVIDENCE HuntForwardedFreedRead
\* intent:   reachability canary: no forwarded read response has yet been received after a release freed pending state; expected to be violated.
\* status:   model-internal
\* verified: update (c780d355)
\* review:   ok
HuntForwardedFreedRead ==
    ~(scenarioSeen.readResponse /\ scenarioSeen.readFreed)
\* REQ-EVIDENCE HuntReadLeaderSteppedDown
\* intent:   reachability canary: no server that broadcast a read-context heartbeat in its current term has yet stopped being leader in that same term; expected to be violated, witnessing that a read-carrying leader can step down (repair R1 reset path).
\* status:   model-internal
\* verified: update (c780d355)
\* review:   ok
HuntReadLeaderSteppedDown ==
    ~\E i \in Server :
        /\ role[i] /= Leader
        /\ \E m \in messages :
              /\ m.mtype = MsgHeartbeat /\ m.from = i
              /\ m.ctx \in ReadContexts /\ m.term = term[i]

\* REQ-EVIDENCE UpdReadStateOnlyAtLeader
\* intent:   only a leader holds queued or pending read requests; every role change away from leader recreates the read-only state.
\* status:   impl-abstraction
\* evidence: impl source/raft.go:510 "r.readOnly = newReadOnly(r.readOnly.option)" (inside reset, called by becomeFollower/becomeCandidate/becomeLeader)
\* watch:    raft.go:reset; raft.go:becomeFollower; raft.go:becomeCandidate; raft.go:becomeLeader; read_only.go:newReadOnly
\* verified: update (c780d355)
\* note:     structural guard for repair R1; V0 never cleared read state on a role change, so stale read state could survive into a later leadership term in the model only.
\* review:   ok
UpdReadStateOnlyAtLeader ==
    \A i \in Server :
        role[i] /= Leader =>
            /\ readQueue[i] = <<>>
            /\ \A c \in ReadContexts : ~pendingReads[i][c].active

=============================================================================
