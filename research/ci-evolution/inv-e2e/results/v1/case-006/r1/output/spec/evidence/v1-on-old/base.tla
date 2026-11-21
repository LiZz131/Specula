------------------------------ MODULE base ------------------------------
(***************************************************************************
 * etcd Raft core reference model, updated for the supplied `update` revision.
 * Category A: distributed/message-passing, crash faults.
 *
 * Incremental revision (V1):
 *   - source update: read_only.go:100-104 now deletes every released request
 *     from pendingReadIndex (key = req.Entries[0].Data) instead of the
 *     never-matching req.Context key (old read_only.go:103).
 *   - repair: raft.go:489-511 reset() replaces readOnly on every
 *     becomeFollower/becomeCandidate/becomeLeader; the V0 model only cleared it
 *     on Restart.
 *   - repair: stepFollower MsgReadIndexResp (raft.go:1075-1080) honours the
 *     Step term rules (raft.go:679-734); the V0 action accepted any term/role.
 *   - ghost history (no behavioural effect): request-time commit watermark,
 *     post-enqueue heartbeat acknowledgers, and a release log, used only by
 *     the read properties in Update.tla.
 *************************************************************************)
EXTENDS Integers, Naturals, Sequences, FiniteSets, TLC

CONSTANTS Server, Values, ReadContexts, Nil, MaxTerm, MaxLogLen
CONSTANTS Follower, Candidate, Leader
CONSTANTS MsgVote, MsgVoteResp, MsgApp, MsgAppResp,
          MsgHeartbeat, MsgHeartbeatResp, MsgReadIndex, MsgReadIndexResp

ASSUME Cardinality(Server) > 0
ASSUME Nil \notin Server \cup Values \cup ReadContexts

Roles == {Follower, Candidate, Leader}
MessageTypes == {MsgVote, MsgVoteResp, MsgApp, MsgAppResp,
                 MsgHeartbeat, MsgHeartbeatResp, MsgReadIndex,
                 MsgReadIndexResp}
Quorum == (Cardinality(Server) \div 2) + 1
Min2(a, b) == IF a <= b THEN a ELSE b
Max2(a, b) == IF a >= b THEN a ELSE b

Entry(t, v) == [term |-> t, value |-> v]
\* Pending read state (read_only.go:29-33 readIndexStatus) plus two ghost
\* fields: floor = global commit watermark when the leader accepted the request
\* (checking only), fresh = peers that processed a heartbeat carrying this
\* context from this leader/term while THIS request instance was pending.
EmptyPending == [active |-> FALSE, index |-> 0, requester |-> Nil, acks |-> {},
                 floor |-> 0, fresh |-> {}]

Msg(mt, from, to, tm, idx, ltm, com, etm, val, ctx, rej) ==
    [mtype |-> mt, from |-> from, to |-> to, term |-> tm,
     index |-> idx, logTerm |-> ltm, commit |-> com,
     entryTerm |-> etm, value |-> val, ctx |-> ctx, reject |-> rej]

VARIABLES
    term, vote, role, leader, logs, commitIndex, appliedIndex,
    durableTerm, durableVote, durableLogs, durableCommit,
    matchIndex, nextIndex, votesGranted, recentActive,
    messages, pendingReads, readQueue, producedReads, publishedReads,
    readyOutstanding, alive, leaderHistory, commitHistory,
    readReleases, scenarioSeen

serverVars == <<term, vote, role, leader, logs, commitIndex, appliedIndex>>
durableVars == <<durableTerm, durableVote, durableLogs, durableCommit>>
leaderVars == <<matchIndex, nextIndex, votesGranted, recentActive>>
readVars == <<pendingReads, readQueue, producedReads, publishedReads>>
interfaceVars == <<readyOutstanding>>
\* readReleases is a ghost release log (one record per released read request)
\* used to justify forwarded responses; it never affects enabledness.
historyVars == <<leaderHistory, commitHistory, readReleases, scenarioSeen>>
vars == <<serverVars, durableVars, leaderVars, messages, readVars,
          interfaceVars, alive, historyVars>>

LastIndex(i) == Len(logs[i])
LastTerm(i) == IF LastIndex(i) = 0 THEN 0 ELSE logs[i][LastIndex(i)].term
TermAt(i, idx) == IF idx = 0 THEN 0 ELSE logs[i][idx].term
LogTerms(s) == [k \in 1..Len(s) |-> s[k].term]
IsUpToDate(i, idx, ltm) ==
    \/ ltm > LastTerm(i)
    \/ /\ ltm = LastTerm(i)
       /\ idx >= LastIndex(i)

LastPendingCtx(i) ==
    IF Len(readQueue[i]) = 0 THEN Nil ELSE readQueue[i][Len(readQueue[i])]

\* raft.go:489-511 reset(): r.readOnly = newReadOnly(r.readOnly.option)
\* (read_only.go:41-46).  Used at every modeled reset() call site.
\* UPDATE-MAP
\* code: raft.go:510 (reset), read_only.go:41-46
\* update: Update!InteractionActions (reset sites), Update!PendingMatchesQueue
EmptyReadOnly == [c \in ReadContexts |-> EmptyPending]

\* Ghost: highest index any leader has committed so far (commitHistory is
\* appended only by leader maybeCommit, raft.go:475-486).
\* Ghost release record = released read record plus the leader term.
ReleaseRec(rr, t) ==
    [owner |-> rr.owner, leader |-> rr.leader, index |-> rr.index,
     ctx |-> rr.ctx, justificationCtx |-> rr.justificationCtx,
     acks |-> rr.acks, floor |-> rr.floor, fresh |-> rr.fresh, term |-> t]

CommitWatermark ==
    LET idxs == {ch.index : ch \in commitHistory}
    IN IF idxs = {} THEN 0 ELSE CHOOSE x \in idxs : \A y \in idxs : x >= y

ActiveCount(i) ==
    Cardinality({j \in Server : j = i \/ recentActive[i][j]})

MsgWellFormed(m) ==
    /\ m.mtype \in MessageTypes
    /\ m.from \in Server
    /\ m.to \in Server
    /\ m.term \in 0..MaxTerm
    /\ m.index \in 0..MaxLogLen
    /\ m.logTerm \in 0..MaxTerm
    /\ m.commit \in 0..MaxLogLen
    /\ m.entryTerm \in 0..MaxTerm
    /\ m.value \in Values \cup {Nil}
    /\ m.ctx \in ReadContexts \cup {Nil}
    /\ m.reject \in BOOLEAN

(***************************************************************************
 * Node Ready publication contract.  A direct call to a handler operator is
 * the raw raft.Step boundary used by Trace.  The composed Spec/MC network
 * admits delivery only after the sender's HardState/log dependency is durable,
 * matching node.go's persist-before-send requirement.
 *************************************************************************)
DurableTermAt(i, idx) ==
    IF idx = 0 THEN 0 ELSE durableLogs[i][idx].term

PublishedBySender(m) ==
    CASE m.mtype = MsgVote ->
           /\ durableTerm[m.from] >= m.term
           /\ durableVote[m.from] = m.from
      [] m.mtype = MsgVoteResp ->
           /\ durableTerm[m.from] >= m.term
           /\ (m.reject \/ durableVote[m.from] = m.to)
      [] m.mtype = MsgApp ->
           /\ durableTerm[m.from] >= m.term
           /\ durableCommit[m.from] >= m.commit
           /\ m.index <= Len(durableLogs[m.from])
           /\ DurableTermAt(m.from, m.index) = m.logTerm
           /\ IF m.entryTerm = 0 THEN TRUE ELSE
                /\ m.index + 1 <= Len(durableLogs[m.from])
                /\ durableLogs[m.from][m.index + 1].term = m.entryTerm
                /\ durableLogs[m.from][m.index + 1].value = m.value
      [] m.mtype = MsgAppResp ->
           /\ durableTerm[m.from] >= m.term
           /\ (m.reject \/ m.index <= Len(durableLogs[m.from]))
      [] m.mtype = MsgHeartbeat ->
           /\ durableTerm[m.from] >= m.term
           /\ durableCommit[m.from] >= m.commit
      [] m.mtype = MsgHeartbeatResp -> durableTerm[m.from] >= m.term
      [] m.mtype = MsgReadIndex -> TRUE
      [] m.mtype = MsgReadIndexResp -> durableTerm[m.from] >= m.term
      [] OTHER -> TRUE

Init ==
    /\ term = [i \in Server |-> 0]
    /\ vote = [i \in Server |-> Nil]
    /\ role = [i \in Server |-> Follower]
    /\ leader = [i \in Server |-> Nil]
    /\ logs = [i \in Server |-> <<>>]
    /\ commitIndex = [i \in Server |-> 0]
    /\ appliedIndex = [i \in Server |-> 0]
    /\ durableTerm = [i \in Server |-> 0]
    /\ durableVote = [i \in Server |-> Nil]
    /\ durableLogs = [i \in Server |-> <<>>]
    /\ durableCommit = [i \in Server |-> 0]
    /\ matchIndex = [i \in Server |-> [j \in Server |-> 0]]
    /\ nextIndex = [i \in Server |-> [j \in Server |-> 1]]
    /\ votesGranted = [i \in Server |-> {}]
    /\ recentActive = [i \in Server |-> [j \in Server |-> FALSE]]
    /\ messages = {}
    /\ pendingReads = [i \in Server |-> EmptyReadOnly]
    /\ readQueue = [i \in Server |-> <<>>]
    /\ producedReads = [i \in Server |-> <<>>]
    /\ publishedReads = <<>>
    /\ readyOutstanding = [i \in Server |-> FALSE]
    /\ alive = [i \in Server |-> TRUE]
    /\ leaderHistory = {}
    /\ commitHistory = {}
    /\ readReleases = {}
    /\ scenarioSeen = [election |-> FALSE, leader |-> FALSE,
                         proposal |-> FALSE, append |-> FALSE,
                         commit |-> FALSE, heartbeat |-> FALSE,
                         quorumCheck |-> FALSE, readRequest |-> FALSE,
                         readForward |-> FALSE, readResponse |-> FALSE,
                         readQuorum |-> FALSE, readyRead |-> FALSE,
                         loss |-> FALSE, crash |-> FALSE, restart |-> FALSE,
                         readFreed |-> FALSE, readReenqueue |-> FALSE,
                         reuseRelease |-> FALSE, resetDropsRead |-> FALSE]

(***************************************************************************
 * Election actions. raft.go:525-532, 570-580, 624-677.
 *************************************************************************)
Campaign(i) ==
    /\ alive[i]
    /\ role[i] /= Leader
    /\ term[i] < MaxTerm
    /\ term' = [term EXCEPT ![i] = @ + 1]
    /\ vote' = [vote EXCEPT ![i] = i]
    /\ role' = [role EXCEPT ![i] = Candidate]
    /\ leader' = [leader EXCEPT ![i] = Nil]
    /\ votesGranted' = [votesGranted EXCEPT ![i] = {i}]
    \* becomeCandidate -> reset(r.Term+1) clears readOnly (raft.go:570-576, 510).
    \* UPDATE-MAP
    \* code: raft.go:570-576, raft.go:510
    \* update: Update!InteractionActions (MCCampaign)
    /\ pendingReads' = [pendingReads EXCEPT ![i] = EmptyReadOnly]
    /\ readQueue' = [readQueue EXCEPT ![i] = <<>>]
    /\ messages' = messages \cup
         {Msg(MsgVote, i, j, term[i] + 1, LastIndex(i), LastTerm(i),
              0, 0, Nil, Nil, FALSE) : j \in Server \ {i}}
    /\ scenarioSeen' = [scenarioSeen EXCEPT !.election = TRUE,
                          !.resetDropsRead = @ \/ (Len(readQueue[i]) > 0)]
    /\ UNCHANGED <<logs, commitIndex, appliedIndex, durableVars,
                    matchIndex, nextIndex, recentActive, producedReads,
                    publishedReads, interfaceVars, alive, leaderHistory,
                    commitHistory, readReleases>>

(***************************************************************************
 * Step vote handling. raft.go:679-711, 759-775.
 *************************************************************************)
HandleVoteRequest(i, m) ==
    LET nt == IF m.term > term[i] THEN m.term ELSE term[i]
        nv == IF m.term > term[i] THEN Nil ELSE vote[i]
        grant == /\ m.term >= term[i]
                 /\ (nv = Nil \/ nv = m.from)
                 /\ IsUpToDate(i, m.index, m.logTerm)
        resp == Msg(MsgVoteResp, i, m.from, nt, 0, 0, 0, 0,
                    Nil, Nil, ~grant)
    IN
    /\ alive[i]
    /\ m.mtype = MsgVote
    /\ m.to = i
    /\ m.term \in 1..MaxTerm
    /\ term' = [term EXCEPT ![i] = nt]
    /\ vote' = [vote EXCEPT ![i] = IF grant THEN m.from ELSE nv]
    /\ role' = [role EXCEPT ![i] = IF m.term > term[i] THEN Follower ELSE @]
    /\ leader' = [leader EXCEPT ![i] = IF m.term > term[i] THEN Nil ELSE @]
    \* m.Term > r.Term -> becomeFollower -> reset clears readOnly
    \* (raft.go:684-711, 561-567, 510).
    \* UPDATE-MAP
    \* code: raft.go:705-710, raft.go:510
    \* update: Update!InteractionActions (MCHandleVoteRequest)
    /\ pendingReads' = [pendingReads EXCEPT ![i] =
                          IF m.term > term[i] THEN EmptyReadOnly ELSE @]
    /\ readQueue' = [readQueue EXCEPT ![i] =
                       IF m.term > term[i] THEN <<>> ELSE @]
    /\ messages' = (messages \ {m}) \cup {resp}
    /\ scenarioSeen' = [scenarioSeen EXCEPT !.resetDropsRead =
                          @ \/ (m.term > term[i] /\ Len(readQueue[i]) > 0)]
    /\ UNCHANGED <<logs, commitIndex, appliedIndex, durableVars, leaderVars,
                    producedReads, publishedReads, interfaceVars, alive,
                    leaderHistory, commitHistory, readReleases>>

(***************************************************************************
 * Candidate poll. raft.go:986-1024.
 *************************************************************************)
HandleVoteResponse(i, m) ==
    /\ alive[i]
    /\ role[i] = Candidate
    /\ m.mtype = MsgVoteResp
    /\ m.to = i
    /\ m.term = term[i]
    /\ votesGranted' = [votesGranted EXCEPT
                          ![i] = IF m.reject THEN @ ELSE @ \cup {m.from}]
    /\ messages' = messages \ {m}
    /\ UNCHANGED <<serverVars, durableVars, matchIndex, nextIndex,
                    recentActive, readVars, interfaceVars, alive, historyVars>>

(***************************************************************************
 * becomeLeader plus immediate bcastAppend. raft.go:597-621, 1016-1021.
 *************************************************************************)
BecomeLeader(i) ==
    LET nl == Append(logs[i], Entry(term[i], Nil))
        li == Len(nl)
    IN
    /\ alive[i]
    /\ role[i] = Candidate
    /\ Cardinality(votesGranted[i]) >= Quorum
    /\ Len(logs[i]) < MaxLogLen
    /\ role' = [role EXCEPT ![i] = Leader]
    /\ leader' = [leader EXCEPT ![i] = i]
    /\ logs' = [logs EXCEPT ![i] = nl]
    /\ matchIndex' = [matchIndex EXCEPT ![i][i] = li]
    /\ nextIndex' = [nextIndex EXCEPT ![i] = [j \in Server |-> li + 1]]
    \* becomeLeader -> reset(r.Term) clears readOnly (raft.go:597-603, 510).
    \* UPDATE-MAP
    \* code: raft.go:597-603, raft.go:510
    \* update: Update!InteractionActions (MCBecomeLeader)
    /\ pendingReads' = [pendingReads EXCEPT ![i] = EmptyReadOnly]
    /\ readQueue' = [readQueue EXCEPT ![i] = <<>>]
    /\ messages' = messages \cup
         {Msg(MsgApp, i, j, term[i], li - 1,
              IF li = 1 THEN 0 ELSE nl[li-1].term,
              commitIndex[i], term[i], Nil, Nil, FALSE)
          : j \in Server \ {i}}
    /\ leaderHistory' = leaderHistory \cup {[node |-> i, term |-> term[i]]}
    /\ scenarioSeen' = [scenarioSeen EXCEPT !.leader = TRUE]
    /\ UNCHANGED <<term, vote, commitIndex, appliedIndex, durableVars,
                    votesGranted, recentActive, producedReads, publishedReads,
                    interfaceVars, alive, commitHistory, readReleases>>

(***************************************************************************
 * Client proposal. raft.go:797-823, 513-523.
 *************************************************************************)
ClientProposal(i, v) ==
    LET nl == Append(logs[i], Entry(term[i], v))
        li == Len(nl)
    IN
    /\ alive[i]
    /\ role[i] = Leader
    /\ v \in Values
    /\ Len(logs[i]) < MaxLogLen
    /\ logs' = [logs EXCEPT ![i] = nl]
    /\ matchIndex' = [matchIndex EXCEPT ![i][i] = li]
    /\ messages' = messages \cup
         {Msg(MsgApp, i, j, term[i], li - 1,
              IF li = 1 THEN 0 ELSE nl[li-1].term,
              commitIndex[i], term[i], v, Nil, FALSE)
          : j \in Server \ {i}}
    /\ scenarioSeen' = [scenarioSeen EXCEPT !.proposal = TRUE]
    /\ UNCHANGED <<term, vote, role, leader, commitIndex, appliedIndex,
                    durableVars, nextIndex, votesGranted, recentActive,
                    readVars, interfaceVars, alive, leaderHistory,
                    commitHistory, readReleases>>

(***************************************************************************
 * Follower AppendEntries. raft.go:1039-1042, 1084-1097;
 * log.go:74-102. Zero-or-one-entry bounded message representation.
 *************************************************************************)
HandleAppendEntries(i, m) ==
    LET termOK == m.term >= term[i]
        prefixOK == /\ m.index <= LastIndex(i)
                    /\ TermAt(i, m.index) = m.logTerm
        hasEntry == m.entryTerm /= 0
        accept == termOK /\ prefixOK /\ (~hasEntry \/ m.entryTerm = m.term)
        nl == IF accept /\ hasEntry
              THEN SubSeq(logs[i], 1, m.index) \o <<Entry(m.entryTerm, m.value)>>
              ELSE logs[i]
        lastNew == m.index + IF hasEntry THEN 1 ELSE 0
        nc == IF accept THEN Max2(commitIndex[i], Min2(m.commit, lastNew))
              ELSE commitIndex[i]
        resp == Msg(MsgAppResp, i, m.from,
                    IF m.term > term[i] THEN m.term ELSE term[i],
                    IF accept THEN lastNew ELSE m.index,
                    0, 0, 0, Nil, Nil, ~accept)
        \* becomeFollower (and therefore reset) runs for a higher term in Step
        \* (raft.go:705-710) or for a same-term candidate in stepCandidate
        \* (raft.go:1005-1007); a same-term follower does not reset
        \* (raft.go:1046-1049).
        resets == \/ m.term > term[i]
                  \/ (m.term = term[i] /\ role[i] = Candidate)
    IN
    /\ alive[i]
    /\ m.mtype = MsgApp
    /\ m.to = i
    /\ term' = [term EXCEPT ![i] = IF m.term > @ THEN m.term ELSE @]
    /\ vote' = [vote EXCEPT ![i] = IF m.term > term[i] THEN Nil ELSE @]
    /\ role' = [role EXCEPT ![i] = IF termOK THEN Follower ELSE @]
    /\ leader' = [leader EXCEPT ![i] = IF termOK THEN m.from ELSE @]
    /\ logs' = [logs EXCEPT ![i] = nl]
    /\ commitIndex' = [commitIndex EXCEPT ![i] = nc]
    \* UPDATE-MAP
    \* code: raft.go:705-710, raft.go:1005-1007, raft.go:510
    \* update: Update!InteractionActions (MCHandleAppendEntries)
    /\ pendingReads' = [pendingReads EXCEPT ![i] =
                          IF resets THEN EmptyReadOnly ELSE @]
    /\ readQueue' = [readQueue EXCEPT ![i] = IF resets THEN <<>> ELSE @]
    /\ messages' = (messages \ {m}) \cup {resp}
    /\ scenarioSeen' = [scenarioSeen EXCEPT !.append = TRUE,
                          !.resetDropsRead =
                            @ \/ (resets /\ Len(readQueue[i]) > 0)]
    /\ UNCHANGED <<appliedIndex, durableVars, leaderVars, producedReads,
                    publishedReads, interfaceVars, alive, leaderHistory,
                    commitHistory, readReleases>>

CommitCandidate(i, newMatch) ==
    {k \in commitIndex[i]..LastIndex(i) :
       /\ Cardinality({j \in Server : newMatch[j] >= k}) >= Quorum
       /\ (k = 0 \/ logs[i][k].term = term[i])}

(***************************************************************************
 * Leader AppendResponse, including current-term-only maybeCommit.
 * raft.go:863-902; progress.go:112-153; log.go:279-285.
 *************************************************************************)
HandleAppendResponse(i, m) ==
    LET nm == IF m.reject
              THEN matchIndex[i]
              ELSE [matchIndex[i] EXCEPT ![m.from] = Max2(@, m.index)]
        cand == CommitCandidate(i, nm)
        nc == IF cand = {} THEN commitIndex[i] ELSE CHOOSE x \in cand :
                  \A y \in cand : x >= y
        added == { [index |-> k, entry |-> logs[i][k], commitTerm |-> term[i]]
                   : k \in (commitIndex[i]+1)..nc }
    IN
    /\ alive[i]
    /\ role[i] = Leader
    /\ m.mtype = MsgAppResp
    /\ m.to = i
    /\ m.term = term[i]
    /\ matchIndex' = [matchIndex EXCEPT ![i] = nm]
    /\ nextIndex' = [nextIndex EXCEPT ![i][m.from] =
         IF m.reject THEN Max2(1, @ - 1) ELSE Max2(@, m.index + 1)]
    /\ recentActive' = [recentActive EXCEPT ![i][m.from] = TRUE]
    /\ commitIndex' = [commitIndex EXCEPT ![i] = nc]
    /\ commitHistory' = commitHistory \cup added
    /\ messages' = messages \ {m}
    /\ scenarioSeen' = [scenarioSeen EXCEPT
                          !.commit = @ \/ (nc > commitIndex[i])]
    /\ UNCHANGED <<term, vote, role, leader, logs, appliedIndex,
                    durableVars, votesGranted, readVars, interfaceVars,
                    alive, leaderHistory, readReleases>>

(***************************************************************************
 * Heartbeat broadcast/receipt. raft.go:426-473, 1099-1102.
 *************************************************************************)
BroadcastHeartbeat(i) ==
    /\ alive[i]
    /\ role[i] = Leader
    /\ messages' = messages \cup
         {Msg(MsgHeartbeat, i, j, term[i], 0, 0,
              Min2(matchIndex[i][j], commitIndex[i]), 0, Nil,
              LastPendingCtx(i), FALSE) : j \in Server \ {i}}
    /\ scenarioSeen' = [scenarioSeen EXCEPT !.heartbeat = TRUE]
    /\ UNCHANGED <<serverVars, durableVars, leaderVars, readVars,
                    interfaceVars, alive, leaderHistory, commitHistory,
                    readReleases>>

HandleHeartbeat(i, m) ==
    LET termOK == m.term >= term[i]
        nt == IF m.term > term[i] THEN m.term ELSE term[i]
        nc == IF termOK THEN Max2(commitIndex[i], Min2(m.commit, LastIndex(i)))
              ELSE commitIndex[i]
        resp == Msg(MsgHeartbeatResp, i, m.from, nt, 0, 0, 0, 0,
                    Nil, m.ctx, FALSE)
        \* Same reset sites as HandleAppendEntries (raft.go:705-710,
        \* raft.go:1008-1010 stepCandidate MsgHeartbeat).
        resets == \/ m.term > term[i]
                  \/ (m.term = term[i] /\ role[i] = Candidate)
        \* Ghost only: this peer acknowledges leader m.from's authority after
        \* the currently pending request instance for m.ctx was enqueued.
        ghostAck == /\ termOK
                    /\ m.ctx \in ReadContexts
                    /\ m.from /= i
                    /\ term[m.from] = m.term
                    /\ pendingReads[m.from][m.ctx].active
        own == IF resets THEN EmptyReadOnly ELSE pendingReads[i]
    IN
    /\ alive[i]
    /\ m.mtype = MsgHeartbeat
    /\ m.to = i
    /\ term' = [term EXCEPT ![i] = nt]
    /\ vote' = [vote EXCEPT ![i] = IF m.term > term[i] THEN Nil ELSE @]
    /\ role' = [role EXCEPT ![i] = IF termOK THEN Follower ELSE @]
    /\ leader' = [leader EXCEPT ![i] = IF termOK THEN m.from ELSE @]
    /\ commitIndex' = [commitIndex EXCEPT ![i] = nc]
    \* UPDATE-MAP
    \* code: raft.go:705-710, raft.go:1008-1010, raft.go:510, raft.go:1099-1102
    \* update: Update!InteractionActions (MCHandleHeartbeat),
    \*         Update!ReadDeliveryJustifiedFresh (ghost fresh set)
    /\ pendingReads' =
         IF ghostAck
         THEN [pendingReads EXCEPT ![i] = own,
                                   ![m.from][m.ctx].fresh = @ \cup {i}]
         ELSE [pendingReads EXCEPT ![i] = own]
    /\ readQueue' = [readQueue EXCEPT ![i] = IF resets THEN <<>> ELSE @]
    /\ messages' = (messages \ {m}) \cup {resp}
    /\ scenarioSeen' = [scenarioSeen EXCEPT !.resetDropsRead =
                          @ \/ (resets /\ Len(readQueue[i]) > 0)]
    /\ UNCHANGED <<logs, appliedIndex, durableVars, leaderVars, producedReads,
                    publishedReads, interfaceVars, alive, leaderHistory,
                    commitHistory, readReleases>>

(***************************************************************************
 * ReadIndex enqueue. raft.go:824-853; read_only.go:48-59.
 *************************************************************************)
ProcessReadIndex(i, c, requester, consumed) ==
    LET multi == Cardinality(Server) > 1
        eligible == ~multi \/
                    (commitIndex[i] > 0 /\ TermAt(i, commitIndex[i]) = term[i])
        \* read_only.go:53-56: an active pending context is ignored.  After the
        \* update a released context is no longer active, so the same context
        \* can be enqueued again in the same term.
        \* UPDATE-MAP
        \* code: read_only.go:52-58 (unchanged), enabled by read_only.go:100-104
        \* update: Update!InteractionActions (MCClientReadIndex,
        \*         MCHandleReadIndexRequest), Update!PendingMatchesQueue
        duplicate == pendingReads[i][c].active
        enqueue == eligible /\ multi /\ ~duplicate
        np == IF enqueue
              THEN [pendingReads EXCEPT ![i][c] =
                     [active |-> TRUE, index |-> commitIndex[i],
                      requester |-> requester, acks |-> {},
                      floor |-> CommitWatermark, fresh |-> {}]]
              ELSE pendingReads
        nq == IF enqueue
              THEN [readQueue EXCEPT ![i] = Append(@, c)] ELSE readQueue
        oneRead == [owner |-> requester, leader |-> i,
                    index |-> commitIndex[i], ctx |-> c,
                    justificationCtx |-> c, acks |-> {i},
                    floor |-> CommitWatermark, fresh |-> {i}]
        \* Ghost: the same leader already released this context in this term,
        \* so the request is a same-term re-enqueue (possible only after the
        \* update deletes released entries, read_only.go:100-104).
        reenqueue == /\ enqueue
                     /\ \E r \in readReleases :
                          r.leader = i /\ r.term = term[i] /\ r.ctx = c
    IN
    /\ alive[i]
    /\ role[i] = Leader
    /\ c \in ReadContexts
    /\ requester \in Server
    /\ eligible
    /\ pendingReads' = np
    /\ readQueue' = nq
    /\ producedReads' = IF multi THEN producedReads
                         ELSE [producedReads EXCEPT ![i] = Append(@, oneRead)]
    /\ messages' = IF multi
         THEN (messages \ consumed) \cup
              {Msg(MsgHeartbeat, i, j, term[i], 0, 0,
                   Min2(matchIndex[i][j], commitIndex[i]), 0, Nil,
                   c, FALSE) : j \in Server \ {i}}
         ELSE messages \ consumed
    /\ readReleases' = IF multi THEN readReleases
                        ELSE readReleases \cup {ReleaseRec(oneRead, term[i])}
    /\ scenarioSeen' = [scenarioSeen EXCEPT
                          !.readRequest = TRUE,
                          !.readForward = TRUE,
                          !.readReenqueue = @ \/ reenqueue]
    /\ UNCHANGED <<serverVars, durableVars, leaderVars, publishedReads,
                    interfaceVars, alive, leaderHistory, commitHistory>>

ClientReadIndex(i, c, requester) ==
    ProcessReadIndex(i, c, requester, {})

ForwardReadIndex(i, c) ==
    /\ alive[i]
    /\ role[i] /= Leader
    /\ leader[i] \in Server
    /\ c \in ReadContexts
    /\ messages' = messages \cup
         {Msg(MsgReadIndex, i, leader[i], 0, 0, 0, 0, 0,
              Nil, c, FALSE)}
    /\ scenarioSeen' = [scenarioSeen EXCEPT !.readRequest = TRUE]
    /\ UNCHANGED <<serverVars, durableVars, leaderVars, readVars,
                    interfaceVars, alive, leaderHistory, commitHistory,
                    readReleases>>

HandleReadIndexRequest(i, m) ==
    /\ m.mtype = MsgReadIndex
    /\ m.to = i
    /\ m.ctx \in ReadContexts
    /\ ProcessReadIndex(i, m.ctx, m.from, {m})

ReleasedReadSeq(i, pos, jctx, jacks, jfresh) ==
    [k \in 1..pos |->
       LET c == readQueue[i][k] IN
       [owner |-> pendingReads[i][c].requester,
        leader |-> i,
        index |-> pendingReads[i][c].index,
        ctx |-> c,
        justificationCtx |-> jctx,
        acks |-> jacks,
        floor |-> pendingReads[i][c].floor,
        fresh |-> jfresh]]

(***************************************************************************
 * Heartbeat response: progress activity plus context ack and FIFO-prefix
 * advance. raft.go:903-932; read_only.go:61-109.
 *
 * UPDATE (read_only.go:100-104): advance now deletes every released request
 * under its real key string(req.Entries[0].Data), so every released context
 * leaves pendingReadIndex together with readIndexQueue.  Consequences in this
 * model: a later ack for a released context is unknown (recvAck returns 0,
 * read_only.go:64-68), and the same context may be enqueued again by a later
 * MsgReadIndex in the same term (read_only.go:52-58).
 *************************************************************************)
\* UPDATE-MAP
\* code: read_only.go:78-109 (advance), read_only.go:64-73 (recvAck),
\*       raft.go:915-932 (stepLeader MsgHeartbeatResp)
\* update: Update!AffectedActions (MCHandleHeartbeatResponse)
HandleHeartbeatResponse(i, m) ==
    LET \* raft.go:915-917: only ReadOnlySafe with a non-empty Context acks.
        known == m.ctx \in ReadContexts /\ pendingReads[i][m.ctx].active
        \* read_only.go:70-72: record m.From, count plus one for the leader.
        newAcks == IF known
                   THEN pendingReads[i][m.ctx].acks \cup {m.from}
                   ELSE {}
        \* raft.go:919-922: ackCount >= quorum
        quorum == known /\ Cardinality(newAcks \cup {i}) >= Quorum
        \* read_only.go:87-98: queue prefix ending at m.Context
        positions == IF known THEN {k \in 1..Len(readQueue[i]) :
                                      readQueue[i][k] = m.ctx} ELSE {}
        pos == IF positions = {} THEN 0 ELSE CHOOSE k \in positions : TRUE
        releasedCtxs == IF quorum THEN {readQueue[i][k] : k \in 1..pos}
                        ELSE {}
        \* read_only.go:100-104 (UPDATE): every released request is deleted.
        np == [c \in ReadContexts |->
                IF c \in releasedCtxs THEN EmptyPending
                ELSE IF c = m.ctx /\ known
                     THEN [pendingReads[i][c] EXCEPT !.acks = newAcks]
                     ELSE pendingReads[i][c]]
        released == IF quorum
                    THEN ReleasedReadSeq(i, pos, m.ctx, newAcks \cup {i},
                                         pendingReads[i][m.ctx].fresh \cup {i})
                    ELSE <<>>
        releasedSet == {released[k] : k \in 1..Len(released)}
        \* raft.go:926-931: local requester -> readStates, else MsgReadIndexResp
        localReads == SelectSeq(released, LAMBDA rr : rr.owner = i)
        remoteReads == {rr \in releasedSet : rr.owner /= i}
        responses ==
            {Msg(MsgReadIndexResp, i, rr.owner, term[i], rr.index,
                 0, 0, 0, Nil, rr.ctx, FALSE) : rr \in remoteReads}
        reuse == \E rr \in releasedSet, r \in readReleases :
                    r.leader = i /\ r.term = term[i] /\ r.ctx = rr.ctx
    IN
    /\ alive[i]
    /\ role[i] = Leader
    /\ m.mtype = MsgHeartbeatResp
    /\ m.to = i
    /\ m.term = term[i]
    /\ recentActive' = [recentActive EXCEPT ![i][m.from] = TRUE]
    /\ pendingReads' = [pendingReads EXCEPT ![i] = np]
    /\ readQueue' = [readQueue EXCEPT ![i] =
                       IF quorum THEN SubSeq(@, pos + 1, Len(@)) ELSE @]
    /\ producedReads' = [producedReads EXCEPT ![i] =
         IF quorum THEN @ \o localReads
         ELSE @]
    /\ readReleases' = readReleases \cup
         {ReleaseRec(rr, term[i]) : rr \in releasedSet}
    /\ messages' = (messages \ {m}) \cup responses
    /\ scenarioSeen' = [scenarioSeen EXCEPT
                          !.readQuorum = @ \/ quorum,
                          !.readFreed = @ \/ (releasedCtxs /= {}),
                          !.reuseRelease = @ \/ (quorum /\ reuse)]
    /\ UNCHANGED <<serverVars, durableVars, matchIndex, nextIndex,
                    votesGranted, publishedReads, interfaceVars, alive,
                    leaderHistory, commitHistory>>

(***************************************************************************
 * Follower receipt of MsgReadIndexResp. raft.go:1075-1080 (stepFollower).
 * Step term handling applies (raft.go:679-734): a lower-term response is
 * ignored; a higher-term response first makes this node a follower of the
 * sender (becomeFollower -> reset); stepCandidate/stepLeader have no
 * MsgReadIndexResp case, so a same-term response is consumed only by a
 * follower.  Repair of the V0 action, which accepted any term and role.
 * The justification fields are ghost data copied from the leader's release
 * record (readReleases); they never affect enabledness.
 *************************************************************************)
\* UPDATE-MAP
\* code: raft.go:1075-1080, raft.go:705-710, raft.go:926-931
\* update: Update!InteractionActions (MCHandleReadIndexResponse)
HandleReadIndexResponse(i, m) ==
    LET higher == m.term > term[i]
        matching == {r \in readReleases :
                        /\ r.leader = m.from /\ r.owner = i
                        /\ r.ctx = m.ctx /\ r.index = m.index
                        /\ r.term = m.term}
        \* Identical responses collapse in the message set; use the most
        \* conservative evidence of all matching releases.
        evidence == IF matching = {} THEN {}
                    ELSE {s \in Server : \A r \in matching : s \in r.acks}
        freshEv == IF matching = {} THEN {}
                   ELSE {s \in Server : \A r \in matching : s \in r.fresh}
        floorEv == IF matching = {} THEN 0
                   ELSE CHOOSE f \in {r.floor : r \in matching} :
                          \A r \in matching : f >= r.floor
        rr == [owner |-> i, leader |-> m.from, index |-> m.index,
               ctx |-> m.ctx, justificationCtx |-> m.ctx,
               acks |-> evidence, floor |-> floorEv, fresh |-> freshEv]
    IN
    /\ alive[i]
    /\ m.mtype = MsgReadIndexResp
    /\ m.to = i
    /\ m.ctx \in ReadContexts
    /\ \/ higher
       \/ m.term = term[i] /\ role[i] = Follower
    /\ term' = [term EXCEPT ![i] = IF higher THEN m.term ELSE @]
    /\ vote' = [vote EXCEPT ![i] = IF higher THEN Nil ELSE @]
    /\ role' = [role EXCEPT ![i] = Follower]
    /\ leader' = [leader EXCEPT ![i] = IF higher THEN m.from ELSE @]
    /\ pendingReads' = [pendingReads EXCEPT ![i] =
                          IF higher THEN EmptyReadOnly ELSE @]
    /\ readQueue' = [readQueue EXCEPT ![i] = IF higher THEN <<>> ELSE @]
    /\ producedReads' = [producedReads EXCEPT ![i] = Append(@, rr)]
    /\ messages' = messages \ {m}
    /\ scenarioSeen' = [scenarioSeen EXCEPT !.readResponse = TRUE,
                          !.resetDropsRead =
                            @ \/ (higher /\ Len(readQueue[i]) > 0)]
    /\ UNCHANGED <<logs, commitIndex, appliedIndex, durableVars, leaderVars,
                    publishedReads, interfaceVars, alive,
                    leaderHistory, commitHistory, readReleases>>

(***************************************************************************
 * node Ready/Advance boundary. node.go:286-296, 355-383, 506-525.
 *************************************************************************)
ReadyPublish(i) ==
    /\ alive[i]
    /\ ~readyOutstanding[i]
    /\ \/ durableTerm[i] /= term[i]
       \/ durableVote[i] /= vote[i]
       \/ durableLogs[i] /= logs[i]
       \/ durableCommit[i] /= commitIndex[i]
       \/ Len(producedReads[i]) > 0
    /\ durableTerm' = [durableTerm EXCEPT ![i] = term[i]]
    /\ durableVote' = [durableVote EXCEPT ![i] = vote[i]]
    /\ durableLogs' = [durableLogs EXCEPT ![i] = logs[i]]
    /\ durableCommit' = [durableCommit EXCEPT ![i] = commitIndex[i]]
    /\ publishedReads' = publishedReads \o producedReads[i]
    /\ producedReads' = [producedReads EXCEPT ![i] = <<>>]
    /\ readyOutstanding' = [readyOutstanding EXCEPT ![i] = TRUE]
    /\ scenarioSeen' = [scenarioSeen EXCEPT
                          !.readyRead = @ \/ (Len(producedReads[i]) > 0)]
    /\ UNCHANGED <<serverVars, leaderVars, messages, pendingReads,
                    readQueue, alive, leaderHistory, commitHistory,
                    readReleases>>

ReadyAdvance(i) ==
    /\ alive[i]
    /\ readyOutstanding[i]
    /\ appliedIndex' = [appliedIndex EXCEPT ![i] = commitIndex[i]]
    /\ readyOutstanding' = [readyOutstanding EXCEPT ![i] = FALSE]
    /\ UNCHANGED <<term, vote, role, leader, logs, commitIndex,
                    durableVars, leaderVars, messages, readVars, alive,
                    historyVars>>

(***************************************************************************
 * CheckQuorum. raft.go:535-559, 791-796, 1214-1235.
 *************************************************************************)
CheckQuorum(i) ==
    LET active == ActiveCount(i) >= Quorum
    IN
    /\ alive[i]
    /\ role[i] = Leader
    /\ role' = [role EXCEPT ![i] = IF active THEN @ ELSE Follower]
    /\ leader' = [leader EXCEPT ![i] = IF active THEN @ ELSE Nil]
    /\ recentActive' = [recentActive EXCEPT
                          ![i] = [j \in Server |-> FALSE]]
    \* Step-down is becomeFollower(r.Term, None) -> reset clears readOnly
    \* (raft.go:791-796, 561-567, 510).
    \* UPDATE-MAP
    \* code: raft.go:791-796, raft.go:510
    \* update: Update!InteractionActions (MCCheckQuorum)
    /\ pendingReads' = [pendingReads EXCEPT ![i] =
                          IF active THEN @ ELSE EmptyReadOnly]
    /\ readQueue' = [readQueue EXCEPT ![i] = IF active THEN @ ELSE <<>>]
    /\ scenarioSeen' = [scenarioSeen EXCEPT !.quorumCheck = TRUE,
                          !.resetDropsRead =
                            @ \/ (~active /\ Len(readQueue[i]) > 0)]
    /\ UNCHANGED <<term, vote, logs, commitIndex, appliedIndex,
                    durableVars, matchIndex, nextIndex, votesGranted,
                    messages, producedReads, publishedReads, interfaceVars,
                    alive, leaderHistory, commitHistory, readReleases>>

(***************************************************************************
 * Crash/restart and network loss. node.go Ready durability; rafttest network.
 *************************************************************************)
Crash(i) ==
    /\ alive[i]
    /\ alive' = [alive EXCEPT ![i] = FALSE]
    /\ scenarioSeen' = [scenarioSeen EXCEPT !.crash = TRUE]
    /\ UNCHANGED <<serverVars, durableVars, leaderVars, messages, readVars,
                    interfaceVars, leaderHistory, commitHistory, readReleases>>

Restart(i) ==
    /\ ~alive[i]
    /\ alive' = [alive EXCEPT ![i] = TRUE]
    /\ term' = [term EXCEPT ![i] = durableTerm[i]]
    /\ vote' = [vote EXCEPT ![i] = durableVote[i]]
    /\ role' = [role EXCEPT ![i] = Follower]
    /\ leader' = [leader EXCEPT ![i] = Nil]
    /\ logs' = [logs EXCEPT ![i] = durableLogs[i]]
    /\ commitIndex' = [commitIndex EXCEPT ![i] = durableCommit[i]]
    /\ appliedIndex' = [appliedIndex EXCEPT ![i] = Min2(@, durableCommit[i])]
    /\ votesGranted' = [votesGranted EXCEPT ![i] = {}]
    /\ recentActive' = [recentActive EXCEPT ![i] = [j \in Server |-> FALSE]]
    /\ pendingReads' = [pendingReads EXCEPT ![i] = EmptyReadOnly]
    /\ readQueue' = [readQueue EXCEPT ![i] = <<>>]
    /\ producedReads' = [producedReads EXCEPT ![i] = <<>>]
    /\ readyOutstanding' = [readyOutstanding EXCEPT ![i] = FALSE]
    /\ scenarioSeen' = [scenarioSeen EXCEPT !.restart = TRUE]
    /\ UNCHANGED <<durableVars, matchIndex, nextIndex, messages,
                    publishedReads, leaderHistory, commitHistory,
                    readReleases>>

LoseMessage(m) ==
    /\ m \in messages
    /\ messages' = messages \ {m}
    /\ scenarioSeen' = [scenarioSeen EXCEPT !.loss = TRUE]
    /\ UNCHANGED <<serverVars, durableVars, leaderVars, readVars,
                    interfaceVars, alive, leaderHistory, commitHistory,
                    readReleases>>

Next ==
    \/ \E i \in Server : Campaign(i)
    \/ \E i \in Server, m \in messages :
          PublishedBySender(m) /\ HandleVoteRequest(i, m)
    \/ \E i \in Server, m \in messages :
          PublishedBySender(m) /\ HandleVoteResponse(i, m)
    \/ \E i \in Server : BecomeLeader(i)
    \/ \E i \in Server, v \in Values : ClientProposal(i, v)
    \/ \E i \in Server, m \in messages :
          PublishedBySender(m) /\ HandleAppendEntries(i, m)
    \/ \E i \in Server, m \in messages :
          PublishedBySender(m) /\ HandleAppendResponse(i, m)
    \/ \E i \in Server : BroadcastHeartbeat(i)
    \/ \E i \in Server, m \in messages :
          PublishedBySender(m) /\ HandleHeartbeat(i, m)
    \/ \E i \in Server, c \in ReadContexts, r \in Server :
          ClientReadIndex(i, c, r)
    \/ \E i \in Server, c \in ReadContexts : ForwardReadIndex(i, c)
    \/ \E i \in Server, m \in messages :
          PublishedBySender(m) /\ HandleReadIndexRequest(i, m)
    \/ \E i \in Server, m \in messages :
          PublishedBySender(m) /\ HandleHeartbeatResponse(i, m)
    \/ \E i \in Server, m \in messages :
          PublishedBySender(m) /\ HandleReadIndexResponse(i, m)
    \/ \E i \in Server : ReadyPublish(i)
    \/ \E i \in Server : ReadyAdvance(i)
    \/ \E i \in Server : CheckQuorum(i)
    \/ \E i \in Server : Crash(i)
    \/ \E i \in Server : Restart(i)
    \/ \E m \in messages : LoseMessage(m)

Spec == Init /\ [][Next]_vars

ReadRecordType ==
    [owner : Server, leader : Server, index : 0..MaxLogLen,
     ctx : ReadContexts, justificationCtx : ReadContexts,
     acks : SUBSET Server, floor : 0..MaxLogLen, fresh : SUBSET Server]
ReleaseRecordType ==
    [owner : Server, leader : Server, index : 0..MaxLogLen,
     ctx : ReadContexts, justificationCtx : ReadContexts,
     acks : SUBSET Server, floor : 0..MaxLogLen, fresh : SUBSET Server,
     term : 0..MaxTerm]

TypeOK ==
    /\ term \in [Server -> 0..MaxTerm]
    /\ vote \in [Server -> Server \cup {Nil}]
    /\ role \in [Server -> Roles]
    /\ leader \in [Server -> Server \cup {Nil}]
    /\ logs \in [Server -> Seq([term : 0..MaxTerm,
                                  value : Values \cup {Nil}])]
    /\ \A i \in Server : Len(logs[i]) <= MaxLogLen
    /\ commitIndex \in [Server -> 0..MaxLogLen]
    /\ appliedIndex \in [Server -> 0..MaxLogLen]
    /\ durableTerm \in [Server -> 0..MaxTerm]
    /\ durableVote \in [Server -> Server \cup {Nil}]
    /\ durableLogs \in [Server -> Seq([term : 0..MaxTerm,
                                         value : Values \cup {Nil}])]
    /\ durableCommit \in [Server -> 0..MaxLogLen]
    /\ matchIndex \in [Server -> [Server -> 0..MaxLogLen]]
    /\ nextIndex \in [Server -> [Server -> 0..(MaxLogLen+1)]]
    /\ votesGranted \in [Server -> SUBSET Server]
    /\ recentActive \in [Server -> [Server -> BOOLEAN]]
    /\ messages \subseteq {m \in [mtype : MessageTypes,
                                     from : Server, to : Server,
                                     term : 0..MaxTerm,
                                     index : 0..MaxLogLen,
                                     logTerm : 0..MaxTerm,
                                     commit : 0..MaxLogLen,
                                     entryTerm : 0..MaxTerm,
                                     value : Values \cup {Nil},
                                     ctx : ReadContexts \cup {Nil},
                                     reject : BOOLEAN] : MsgWellFormed(m)}
    /\ pendingReads \in [Server -> [ReadContexts ->
         [active : BOOLEAN, index : 0..MaxLogLen,
          requester : Server \cup {Nil}, acks : SUBSET Server,
          floor : 0..MaxLogLen, fresh : SUBSET Server]]]
    /\ readQueue \in [Server -> Seq(ReadContexts)]
    /\ producedReads \in [Server -> Seq(ReadRecordType)]
    /\ publishedReads \in Seq(ReadRecordType)
    /\ readReleases \subseteq ReleaseRecordType
    /\ readyOutstanding \in [Server -> BOOLEAN]
    /\ alive \in [Server -> BOOLEAN]

ElectionSafety ==
    \A t \in 1..MaxTerm :
        Cardinality({i \in Server : [node |-> i, term |-> t] \in leaderHistory}) <= 1

CommitWithinLog ==
    \A i \in Server :
        /\ appliedIndex[i] <= commitIndex[i]
        /\ commitIndex[i] <= Len(logs[i])
        /\ durableCommit[i] <= Len(durableLogs[i])

LogMatching ==
    \A i, j \in Server : \A k \in 1..Min2(Len(logs[i]), Len(logs[j])) :
        logs[i][k].term = logs[j][k].term =>
            SubSeq(logs[i], 1, k) = SubSeq(logs[j], 1, k)

CommittedPrefixAgreement ==
    \A i, j \in Server :
        SubSeq(logs[i], 1, Min2(commitIndex[i], commitIndex[j])) =
        SubSeq(logs[j], 1, Min2(commitIndex[i], commitIndex[j]))

LeaderCompleteness ==
    \A lh \in leaderHistory : \A ch \in commitHistory :
        ch.commitTerm < lh.term =>
          /\ ch.index <= Len(logs[lh.node])
          /\ logs[lh.node][ch.index] = ch.entry

MessagesWellFormed == \A m \in messages : MsgWellFormed(m)

ReadDeliveryJustified ==
    \A k \in 1..Len(publishedReads) :
        Cardinality(publishedReads[k].acks) >= Quorum

ReadyNoInvention ==
    \A k \in 1..Len(publishedReads) :
        /\ publishedReads[k].ctx \in ReadContexts
        /\ publishedReads[k].justificationCtx \in ReadContexts
        /\ publishedReads[k].index <= Len(logs[publishedReads[k].leader])

Safety == /\ TypeOK
          /\ ElectionSafety
          /\ CommitWithinLog
          /\ LogMatching
          /\ CommittedPrefixAgreement
          /\ LeaderCompleteness
          /\ MessagesWellFormed
          /\ ReadDeliveryJustified
          /\ ReadyNoInvention

=============================================================================
