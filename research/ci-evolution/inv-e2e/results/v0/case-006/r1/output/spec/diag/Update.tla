------------------------------- MODULE Update -------------------------------
(***************************************************************************
 * Update-focused checking lens over the V1 reference (base) and MC suite.
 * It defines no implementation behavior of its own: every concrete step is
 * an MC wrapper of a reference Action.
 *
 * Source delta: read_only.go:100-105 (advance) now deletes released pending
 * requests by their real key string(Entries[0].Data) instead of
 * string(req.Context).  Reference: base!HandleHeartbeatResponse.
 * Behavioral consequences captured by the reference:
 *   - pendingReads entries of a released FIFO prefix become inactive;
 *   - the addRequest duplicate guard (read_only.go:54-56) no longer blocks a
 *     context whose earlier request was released, so a context can be
 *     enqueued again (base!ProcessReadIndex);
 *   - recvAck (read_only.go:64-73) matches a heartbeat response only by its
 *     context, so a delayed response produced for an earlier incarnation of a
 *     reused context is counted for the newest one.
 * Related repair (no source change): raft.reset installs a new readOnly
 * (raft.go:489-511); base Campaign/BecomeLeader/HandleVoteRequest/
 * HandleAppendEntries/HandleHeartbeat/CheckQuorum now clear read state.
 *************************************************************************)
EXTENDS MC, UpdateProps

(***************************************************************************
 * Affected Actions: MC forms of directly changed reference Actions.
 *************************************************************************)
\* reference: base!HandleHeartbeatResponse
\* code: read_only.go:78-109 advance (delete key), raft.go:903-932
AffectedHeartbeatResponse ==
    \E i \in Server, m \in messages : MCHandleHeartbeatResponse(i, m)

\* reference: base!ProcessReadIndex via ClientReadIndex / HandleReadIndexRequest
\* code: read_only.go:52-58 addRequest duplicate guard, raft.go:824-853
AffectedReadEnqueue ==
    \/ \E i \in Server, c \in ReadContexts, r \in Server :
          MCClientReadIndex(i, c, r)
    \/ \E i \in Server, m \in messages : MCHandleReadIndexRequest(i, m)

AffectedActions ==
    \/ AffectedHeartbeatResponse
    \/ AffectedReadEnqueue

(***************************************************************************
 * Interaction Actions: unchanged reference Actions that establish the
 * affected preconditions, produce acknowledgements, reset read state, or
 * consume released reads.  Kept concrete.
 *************************************************************************)
InteractionActions ==
    \* leadership and term changes; reset() clears read state (raft.go:510)
    \/ \E i \in Server : MCCampaign(i)
    \/ \E i \in Server, m \in messages : MCHandleVoteRequest(i, m)
    \/ \E i \in Server, m \in messages : MCHandleVoteResponse(i, m)
    \/ \E i \in Server : MCBecomeLeader(i)
    \* current-term commit gates ReadIndex eligibility (raft.go:825-829)
    \/ \E i \in Server, v \in Values : MCClientProposal(i, v)
    \/ \E i \in Server, m \in messages : MCHandleAppendEntries(i, m)
    \/ \E i \in Server, m \in messages : MCHandleAppendResponse(i, m)
    \* acknowledgement producers (raft.go:457-473, 1099-1102)
    \/ \E i \in Server : MCBroadcastHeartbeat(i)
    \/ \E i \in Server, m \in messages : MCHandleHeartbeat(i, m)
    \* released-read consumers (node.go:506-525, raft.go:1075-1080)
    \/ \E i \in Server : MCReadyPublish(i)
    \/ \E i \in Server : MCReadyAdvance(i)
    \/ \E i \in Server, m \in messages : MCHandleReadIndexResponse(i, m)
    \* volatile-state loss (Restart clears readOnly)
    \/ \E i \in Server : MCCrash(i)
    \/ \E i \in Server : MCRestart(i)

(***************************************************************************
 * Omitted context: CheckQuorum, ForwardReadIndex, LoseMessage.
 * EnvUpdate is a weaker rely for their update-visible effects:
 *   EnvStepDown/EnvActivityReset need no quorum evidence (CheckQuorum is
 *   never stronger), EnvForward needs no known leader (ForwardReadIndex is
 *   never stronger), EnvLoss removes any message.
 * Frame: the rely never changes logs, terms, votes, commit state, progress
 * other than recentActive, Ready/durable state, produced/published reads,
 * ghost histories, or a pending entry/queue except by clearing it on a
 * leader that stops leading.
 *************************************************************************)
EnvLoss(m) ==
    /\ m \in messages
    /\ messages' = messages \ {m}
    /\ scenarioSeen' = [scenarioSeen EXCEPT !.loss = TRUE]
    /\ UNCHANGED <<serverVars, durableVars, leaderVars, readVars,
                    interfaceVars, alive, leaderHistory, commitHistory,
                    readGhostVars>>

EnvStepDown(i) ==
    /\ alive[i]
    /\ role[i] = Leader
    /\ role' = [role EXCEPT ![i] = Follower]
    /\ leader' = [leader EXCEPT ![i] = Nil]
    /\ recentActive' = [recentActive EXCEPT ![i] = [j \in Server |-> FALSE]]
    /\ pendingReads' = [pendingReads EXCEPT ![i] = ClearedPending]
    /\ readQueue' = [readQueue EXCEPT ![i] = <<>>]
    /\ scenarioSeen' = [scenarioSeen EXCEPT !.quorumCheck = TRUE]
    /\ UNCHANGED <<term, vote, logs, commitIndex, appliedIndex,
                    durableVars, matchIndex, nextIndex, votesGranted,
                    messages, producedReads, publishedReads, interfaceVars,
                    alive, leaderHistory, commitHistory, readGhostVars>>

EnvActivityReset(i) ==
    /\ alive[i]
    /\ role[i] = Leader
    /\ recentActive' = [recentActive EXCEPT ![i] = [j \in Server |-> FALSE]]
    /\ scenarioSeen' = [scenarioSeen EXCEPT !.quorumCheck = TRUE]
    /\ UNCHANGED <<serverVars, durableVars, matchIndex, nextIndex,
                    votesGranted, messages, readVars, interfaceVars,
                    alive, leaderHistory, commitHistory, readGhostVars>>

EnvForward(j, k, c) ==
    /\ alive[j]
    /\ c \in ReadContexts
    /\ messages' = messages \cup
         {Msg(MsgReadIndex, j, k, 0, 0, 0, 0, 0, Nil, c, FALSE)}
    /\ scenarioSeen' = [scenarioSeen EXCEPT !.readRequest = TRUE]
    /\ UNCHANGED <<serverVars, durableVars, leaderVars, readVars,
                    interfaceVars, alive, leaderHistory, commitHistory,
                    readGhostVars>>

\* Rely over reference variables only (MC counters are private framing).
EnvUpdateBase ==
    \/ \E m \in messages : EnvLoss(m)
    \/ \E i \in Server : EnvStepDown(i)
    \/ \E i \in Server : EnvActivityReset(i)
    \/ \E j, k \in Server, c \in ReadContexts : EnvForward(j, k, c)

EnvUpdate ==
    /\ EnvUpdateBase
    /\ UNCHANGED faultVars

(***************************************************************************
 * Focused and open next-state relations.
 *************************************************************************)
FocusedNext ==
    /\ Cardinality(messages) <= MaxMsgBufferLimit
    /\ \/ AffectedActions
       \/ InteractionActions

FocusedSpec == MCInit /\ [][FocusedNext]_mcVars

OpenUpdateNext ==
    /\ Cardinality(messages) <= MaxMsgBufferLimit
    /\ \/ AffectedActions
       \/ InteractionActions
       \/ EnvUpdate

OpenSpec == MCInit /\ [][OpenUpdateNext]_mcVars


(***************************************************************************
 * Search guide for the S6b linearizability hunt (MC_hunt_s6_linearizable_
 * guided.cfg).  A CONSTRAINT only prunes which reachable states are expanded;
 * it never adds behavior, so any violation found is a real MCSpec behavior.
 * It keeps at most one node between Ready and Advance, and restricts reads to
 * leader-local requests (forwarded reads are covered by other campaigns).
 *************************************************************************)
S6GuideConstraint ==
    /\ StateConstraint
    /\ Cardinality({i \in Server : readyOutstanding[i]}) <= 1
    /\ \A i \in Server, c \in ReadContexts :
          pendingReads[i][c].active => pendingReads[i][c].requester = i
    /\ \A m \in messages : m.mtype \notin {MsgReadIndex, MsgReadIndexResp}

\* Tighter search guide (v2); every conjunct holds along the 38-step S6b path
\* checked in diag/PathCheck.tla (max 7 in-flight messages, no rejected
\* responses, one candidate at a time).
S6GuideConstraintV2 ==
    /\ S6GuideConstraint
    /\ Cardinality(messages) <= 7
    /\ \A m \in messages : ~m.reject
    /\ Cardinality({i \in Server : role[i] = Candidate}) <= 1

(***************************************************************************
 * Discharge: every omitted real context step satisfies the rely.
 * Checked as an action property over the full MCSpec.
 *************************************************************************)
OmittedContext ==
    \/ \E i \in Server : MCCheckQuorum(i)
    \/ \E i \in Server, c \in ReadContexts : MCForwardReadIndex(i, c)
    \/ \E m \in messages : MCLoseMessage(m)

DischargeContext == [][OmittedContext => EnvUpdateBase]_mcVars

\* The rely must not be vacuous: each omitted Action is actually taken.
\* Negated canary (expected violation = witness) for Update_discharge_reach.cfg:
\* a CheckQuorum step-down with cleared read state, a loss, and a forwarded
\* request have all occurred.
DischargeReachOmitted ==
    ~ /\ scenarioSeen.quorumCheck
      /\ scenarioSeen.loss
      /\ \E m \in messages : m.mtype = MsgReadIndex
      /\ \E i \in Server : role[i] = Follower /\ leader[i] = Nil
                           /\ [node |-> i, term |-> term[i]] \in leaderHistory

=============================================================================
