------------------------------ MODULE base ------------------------------
(***************************************************************************
 * etcd Raft core, V1 reference for the supplied updated source tree.
 * Category A: distributed/message-passing, crash faults.
 *
 * V0 -> V1 source delta (read_only.go:100-105, advance):
 *   exact-old: delete(ro.pendingReadIndex, string(rs.req.Context))
 *   updated  : delete(ro.pendingReadIndex, string(rs.req.Entries[0].Data))
 * Requests are keyed by Entries[0].Data (read_only.go:52-58), and the request
 * messages built by node.go:502-504, rawnode.go:262-263 and the follower
 * forwarding path raft.go:1068-1074 carry no Context, so the old delete never
 * removed a released request; the updated delete removes exactly the released
 * FIFO prefix.  Consequences in this vocabulary: pendingReads entries become
 * inactive on release, a released context may be enqueued again, and a
 * response echoing a reused context is matched to the newest incarnation.
 *
 * Repair of an existing V0 model defect (source unchanged): raft.reset
 * (raft.go:489-511), reached from becomeFollower/becomeCandidate/becomeLeader,
 * replaces r.readOnly with an empty readOnly (raft.go:510) and rebuilds
 * progress and vote state (raft.go:501-508).  V0 kept read state across those
 * transitions and kept stale leader progress in BecomeLeader.
 *
 * Ghost evidence (no implementation counterpart, never read by a guard):
 *   pendingReads[i][c].inc/bound/freshAcks, Msg.rinc, readInc, readReleases.
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

\* readIndexStatus{index, req, acks} (read_only.go:29-33) projected to the
\* request owner (req.From) and acknowledgement set.  inc, bound and
\* freshAcks are ghost evidence for Update.tla properties.
EmptyPending == [active |-> FALSE, index |-> 0, requester |-> Nil, acks |-> {},
                 inc |-> 0, bound |-> 0, freshAcks |-> {}]
\* newReadOnly(option) (read_only.go:41-46), installed by raft.reset (raft.go:510).
ClearedPending == [c \in ReadContexts |-> EmptyPending]

\* rinc is a ghost tag on MsgHeartbeatResp only: the requesting leader's
\* incarnation counter for the echoed context when the follower generated the
\* response.  0 for all other messages.
MsgR(mt, from, to, tm, idx, ltm, com, etm, val, ctx, rej, rinc) ==
    [mtype |-> mt, from |-> from, to |-> to, term |-> tm,
     index |-> idx, logTerm |-> ltm, commit |-> com,
     entryTerm |-> etm, value |-> val, ctx |-> ctx, reject |-> rej,
     rinc |-> rinc]

Msg(mt, from, to, tm, idx, ltm, com, etm, val, ctx, rej) ==
    MsgR(mt, from, to, tm, idx, ltm, com, etm, val, ctx, rej, 0)

VARIABLES
    term, vote, role, leader, logs, commitIndex, appliedIndex,
    durableTerm, durableVote, durableLogs, durableCommit,
    matchIndex, nextIndex, votesGranted, recentActive,
    messages, pendingReads, readQueue, producedReads, publishedReads,
    readyOutstanding, alive, leaderHistory, commitHistory,
    scenarioSeen, readInc, readReleases

serverVars == <<term, vote, role, leader, logs, commitIndex, appliedIndex>>
durableVars == <<durableTerm, durableVote, durableLogs, durableCommit>>
leaderVars == <<matchIndex, nextIndex, votesGranted, recentActive>>
readVars == <<pendingReads, readQueue, producedReads, publishedReads>>
interfaceVars == <<readyOutstanding>>
historyVars == <<leaderHistory, commitHistory, scenarioSeen>>
\* Ghost read-lifecycle evidence used only by update properties.
readGhostVars == <<readInc, readReleases>>
vars == <<serverVars, durableVars, leaderVars, messages, readVars,
          interfaceVars, alive, historyVars, readGhostVars>>

LastIndex(i) == Len(logs[i])
LastTerm(i) == IF LastIndex(i) = 0 THEN 0 ELSE logs[i][LastIndex(i)].term
TermAt(i, idx) == IF idx = 0 THEN 0 ELSE logs[i][idx].term
LogTerms(s) == [k \in 1..Len(s) |-> s[k].term]
IsUpToDate(i, idx, ltm) ==
    \/ ltm > LastTerm(i)
    \/ /\ ltm = LastTerm(i)
       /\ idx >= LastIndex(i)

\* lastPendingRequestCtx (read_only.go:111-118).
LastPendingCtx(i) ==
    IF Len(readQueue[i]) = 0 THEN Nil ELSE readQueue[i][Len(readQueue[i])]

ActiveCount(i) ==
    Cardinality({j \in Server : j = i \/ recentActive[i][j]})

\* Ghost: largest index any leader has committed so far.
MaxCommittedIndex ==
    IF commitHistory = {} THEN 0
    ELSE (CHOOSE ch \in commitHistory :
             \A o \in commitHistory : o.index <= ch.index).index

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
    /\ m.rinc \in Nat

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
    /\ pendingReads = [i \in Server |-> ClearedPending]
    /\ readQueue = [i \in Server |-> <<>>]
    /\ producedReads = [i \in Server |-> <<>>]
    /\ publishedReads = <<>>
    /\ readyOutstanding = [i \in Server |-> FALSE]
    /\ alive = [i \in Server |-> TRUE]
    /\ leaderHistory = {}
    /\ commitHistory = {}
    /\ scenarioSeen = [election |-> FALSE, leader |-> FALSE,
                         proposal |-> FALSE, append |-> FALSE,
                         commit |-> FALSE, heartbeat |-> FALSE,
                         quorumCheck |-> FALSE, readRequest |-> FALSE,
                         readForward |-> FALSE, readResponse |-> FALSE,
                         readQuorum |-> FALSE, readyRead |-> FALSE,
                         loss |-> FALSE, crash |-> FALSE, restart |-> FALSE]
    /\ readInc = [i \in Server |-> [c \in ReadContexts |-> 0]]
    /\ readReleases = {}

(***************************************************************************
 * Election actions. raft.go:525-532, 570-580, 624-677.
 * becomeCandidate -> reset(r.Term+1) (raft.go:576, 489-511): new readOnly.
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
    \* UPDATE-MAP (repair) code: raft.go:510 reset -> newReadOnly
    \* update: Update!InteractionActions (MCCampaign), Update!UpdPendingQueueAgreement
    /\ pendingReads' = [pendingReads EXCEPT ![i] = ClearedPending]
    /\ readQueue' = [readQueue EXCEPT ![i] = <<>>]
    /\ messages' = messages \cup
         {Msg(MsgVote, i, j, term[i] + 1, LastIndex(i), LastTerm(i),
              0, 0, Nil, Nil, FALSE) : j \in Server \ {i}}
    /\ scenarioSeen' = [scenarioSeen EXCEPT !.election = TRUE]
    /\ UNCHANGED <<logs, commitIndex, appliedIndex, durableVars,
                    matchIndex, nextIndex, recentActive, producedReads,
                    publishedReads, interfaceVars, alive, leaderHistory,
                    commitHistory, readGhostVars>>

(***************************************************************************
 * Step vote handling. raft.go:679-711, 759-775.
 * Higher term -> becomeFollower(m.Term, None) -> reset (raft.go:684-710).
 *************************************************************************)
HandleVoteRequest(i, m) ==
    LET higher == m.term > term[i]
        nt == IF higher THEN m.term ELSE term[i]
        nv == IF higher THEN Nil ELSE vote[i]
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
    /\ role' = [role EXCEPT ![i] = IF higher THEN Follower ELSE @]
    /\ leader' = [leader EXCEPT ![i] = IF higher THEN Nil ELSE @]
    \* UPDATE-MAP (repair) code: raft.go:710 becomeFollower -> raft.go:510
    \* update: Update!InteractionActions (MCHandleVoteRequest)
    /\ pendingReads' = [pendingReads EXCEPT ![i] =
                          IF higher THEN ClearedPending ELSE @]
    /\ readQueue' = [readQueue EXCEPT ![i] = IF higher THEN <<>> ELSE @]
    /\ messages' = (messages \ {m}) \cup {resp}
    /\ UNCHANGED <<logs, commitIndex, appliedIndex, durableVars, leaderVars,
                    producedReads, publishedReads, interfaceVars, alive,
                    historyVars, readGhostVars>>

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
                    recentActive, readVars, interfaceVars, alive, historyVars,
                    readGhostVars>>

(***************************************************************************
 * becomeLeader plus immediate bcastAppend. raft.go:597-621, 1016-1021.
 * reset(r.Term) (raft.go:601, 489-511) rebuilds progress -- peers Match 0,
 * Next lastIndex+1, self Match lastIndex, RecentActive false -- clears votes
 * and installs a new readOnly; appendEntry then advances self progress.
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
    \* UPDATE-MAP (repair) code: raft.go:501-508 progress reset, appendEntry
    \* update: Update!InteractionActions (MCBecomeLeader)
    /\ matchIndex' = [matchIndex EXCEPT ![i] =
                        [j \in Server |-> IF j = i THEN li ELSE 0]]
    /\ nextIndex' = [nextIndex EXCEPT ![i] =
                       [j \in Server |-> IF j = i THEN li + 1 ELSE li]]
    /\ votesGranted' = [votesGranted EXCEPT ![i] = {}]
    /\ recentActive' = [recentActive EXCEPT ![i] = [j \in Server |-> FALSE]]
    \* UPDATE-MAP (repair) code: raft.go:510 reset -> newReadOnly
    \* update: Update!UpdPendingQueueAgreement
    /\ pendingReads' = [pendingReads EXCEPT ![i] = ClearedPending]
    /\ readQueue' = [readQueue EXCEPT ![i] = <<>>]
    /\ messages' = messages \cup
         {Msg(MsgApp, i, j, term[i], li - 1,
              IF li = 1 THEN 0 ELSE nl[li-1].term,
              commitIndex[i], term[i], Nil, Nil, FALSE)
          : j \in Server \ {i}}
    /\ leaderHistory' = leaderHistory \cup {[node |-> i, term |-> term[i]]}
    /\ scenarioSeen' = [scenarioSeen EXCEPT !.leader = TRUE]
    /\ UNCHANGED <<term, vote, commitIndex, appliedIndex, durableVars,
                    producedReads, publishedReads, interfaceVars,
                    alive, commitHistory, readGhostVars>>

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
                    commitHistory, readGhostVars>>

(***************************************************************************
 * Follower AppendEntries. raft.go:1039-1042, 1084-1097;
 * log.go:74-102. Zero-or-one-entry bounded message representation.
 * A higher term (raft.go:684-710) or a same-term candidate
 * (raft.go:1002-1004) passes through becomeFollower -> reset first.
 *************************************************************************)
HandleAppendEntries(i, m) ==
    LET termOK == m.term >= term[i]
        resetRO == \/ m.term > term[i]
                   \/ (m.term = term[i] /\ role[i] = Candidate)
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
    \* UPDATE-MAP (repair) code: raft.go:710, 1003 becomeFollower -> raft.go:510
    \* update: Update!InteractionActions (MCHandleAppendEntries)
    /\ pendingReads' = [pendingReads EXCEPT ![i] =
                          IF resetRO THEN ClearedPending ELSE @]
    /\ readQueue' = [readQueue EXCEPT ![i] = IF resetRO THEN <<>> ELSE @]
    /\ messages' = (messages \ {m}) \cup {resp}
    /\ scenarioSeen' = [scenarioSeen EXCEPT !.append = TRUE]
    /\ UNCHANGED <<appliedIndex, durableVars, leaderVars, producedReads,
                    publishedReads, interfaceVars, alive, leaderHistory,
                    commitHistory, readGhostVars>>

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
                    alive, leaderHistory, readGhostVars>>

(***************************************************************************
 * Heartbeat broadcast/receipt. raft.go:426-473, 1099-1102.
 * MsgBeat broadcasts lastPendingRequestCtx (raft.go:457-464).
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
                    readGhostVars>>

\* A higher term (raft.go:684-710) or a same-term candidate (raft.go:1005-1007)
\* passes through becomeFollower -> reset first.
HandleHeartbeat(i, m) ==
    LET termOK == m.term >= term[i]
        resetRO == \/ m.term > term[i]
                   \/ (m.term = term[i] /\ role[i] = Candidate)
        nt == IF m.term > term[i] THEN m.term ELSE term[i]
        nc == IF termOK THEN Max2(commitIndex[i], Min2(m.commit, LastIndex(i)))
              ELSE commitIndex[i]
        \* Ghost tag: the requesting leader's incarnation counter for m.ctx at
        \* the moment this response is generated (evidence only).
        respInc == IF m.ctx \in ReadContexts THEN readInc[m.from][m.ctx] ELSE 0
        resp == MsgR(MsgHeartbeatResp, i, m.from, nt, 0, 0, 0, 0,
                     Nil, m.ctx, FALSE, respInc)
    IN
    /\ alive[i]
    /\ m.mtype = MsgHeartbeat
    /\ m.to = i
    /\ term' = [term EXCEPT ![i] = nt]
    /\ vote' = [vote EXCEPT ![i] = IF m.term > term[i] THEN Nil ELSE @]
    /\ role' = [role EXCEPT ![i] = IF termOK THEN Follower ELSE @]
    /\ leader' = [leader EXCEPT ![i] = IF termOK THEN m.from ELSE @]
    /\ commitIndex' = [commitIndex EXCEPT ![i] = nc]
    \* UPDATE-MAP (repair) code: raft.go:710, 1006 becomeFollower -> raft.go:510
    \* update: Update!InteractionActions (MCHandleHeartbeat)
    /\ pendingReads' = [pendingReads EXCEPT ![i] =
                          IF resetRO THEN ClearedPending ELSE @]
    /\ readQueue' = [readQueue EXCEPT ![i] = IF resetRO THEN <<>> ELSE @]
    /\ messages' = (messages \ {m}) \cup {resp}
    /\ UNCHANGED <<logs, appliedIndex, durableVars, leaderVars, producedReads,
                    publishedReads, interfaceVars, alive, historyVars,
                    readGhostVars>>

(***************************************************************************
 * ReadIndex enqueue. raft.go:824-853; read_only.go:52-58.
 * The duplicate guard (read_only.go:54-56) now rejects only contexts still
 * queued: the updated advance deletes released contexts.  The heartbeat
 * broadcast (raft.go:837) happens for duplicates too.
 *************************************************************************)
ProcessReadIndex(i, c, requester, consumed) ==
    LET multi == Cardinality(Server) > 1
        eligible == ~multi \/
                    (commitIndex[i] > 0 /\ TermAt(i, commitIndex[i]) = term[i])
        duplicate == pendingReads[i][c].active
        add == eligible /\ multi /\ ~duplicate
        ninc == readInc[i][c] + 1
        bnd == MaxCommittedIndex
        np == IF add
              THEN [pendingReads EXCEPT ![i][c] =
                     [active |-> TRUE, index |-> commitIndex[i],
                      requester |-> requester, acks |-> {},
                      inc |-> ninc, bound |-> bnd, freshAcks |-> {}]]
              ELSE pendingReads
        nq == IF add THEN [readQueue EXCEPT ![i] = Append(@, c)] ELSE readQueue
        oneRead == [owner |-> requester, leader |-> i,
                    index |-> commitIndex[i], ctx |-> c,
                    justificationCtx |-> c, acks |-> {i}]
        oneRelease == [leader |-> i, term |-> term[i], ctx |-> c,
                       owner |-> requester, index |-> commitIndex[i],
                       bound |-> bnd, inc |-> 0, acks |-> {i},
                       freshAcks |-> {i}]
    IN
    /\ alive[i]
    /\ role[i] = Leader
    /\ c \in ReadContexts
    /\ requester \in Server
    /\ eligible
    \* UPDATE-MAP code: read_only.go:52-58 (duplicate guard now sees deletions)
    \* update: Update!AffectedActions (MCClientReadIndex, MCHandleReadIndexRequest)
    /\ pendingReads' = np
    /\ readQueue' = nq
    /\ readInc' = IF add THEN [readInc EXCEPT ![i][c] = ninc] ELSE readInc
    /\ readReleases' = IF multi THEN readReleases
                       ELSE readReleases \cup {oneRelease}
    /\ producedReads' = IF multi THEN producedReads
                         ELSE [producedReads EXCEPT ![i] = Append(@, oneRead)]
    /\ messages' = IF multi
         THEN (messages \ consumed) \cup
              {Msg(MsgHeartbeat, i, j, term[i], 0, 0,
                   Min2(matchIndex[i][j], commitIndex[i]), 0, Nil,
                   c, FALSE) : j \in Server \ {i}}
         ELSE messages \ consumed
    /\ scenarioSeen' = [scenarioSeen EXCEPT
                          !.readRequest = TRUE,
                          !.readForward = TRUE]
    /\ UNCHANGED <<serverVars, durableVars, leaderVars, publishedReads,
                    interfaceVars, alive, leaderHistory, commitHistory>>

ClientReadIndex(i, c, requester) ==
    ProcessReadIndex(i, c, requester, {})

\* stepFollower MsgReadIndex (raft.go:1068-1074); send() attaches no term
\* to MsgReadIndex (raft.go:356-362).
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
                    readGhostVars>>

HandleReadIndexRequest(i, m) ==
    /\ m.mtype = MsgReadIndex
    /\ m.to = i
    /\ m.ctx \in ReadContexts
    /\ ProcessReadIndex(i, m.ctx, m.from, {m})

ReleasedReadSeq(i, pos, jctx, jacks) ==
    [k \in 1..pos |->
       LET c == readQueue[i][k] IN
       [owner |-> pendingReads[i][c].requester,
        leader |-> i,
        index |-> pendingReads[i][c].index,
        ctx |-> c,
        justificationCtx |-> jctx,
        acks |-> jacks]]

(***************************************************************************
 * Heartbeat response: progress activity plus context ack and FIFO-prefix
 * advance. raft.go:903-932; read_only.go:64-109.
 *************************************************************************)
HandleHeartbeatResponse(i, m) ==
    LET known == m.ctx \in ReadContexts /\ pendingReads[i][m.ctx].active
        ent == IF known THEN pendingReads[i][m.ctx] ELSE EmptyPending
        \* recvAck (read_only.go:64-73): unique peer IDs plus implicit self.
        newAcks == IF known THEN ent.acks \cup {m.from} ELSE {}
        \* Ghost: was this response generated after the incarnation now
        \* pending under m.ctx was accepted (m.rinc = its incarnation)?
        newFresh == IF known /\ m.rinc = ent.inc
                    THEN ent.freshAcks \cup {m.from}
                    ELSE ent.freshAcks
        quorum == known /\ Cardinality(newAcks \cup {i}) >= Quorum
        positions == IF known THEN {k \in 1..Len(readQueue[i]) :
                                      readQueue[i][k] = m.ctx} ELSE {}
        pos == IF positions = {} THEN 0 ELSE CHOOSE k \in positions : TRUE
        \* advance (read_only.go:78-109): FIFO prefix ending at m.ctx.
        releasedCtxs == IF quorum THEN {readQueue[i][k] : k \in 1..pos} ELSE {}
        np == [c \in ReadContexts |->
                IF c \in releasedCtxs THEN EmptyPending
                ELSE IF c = m.ctx /\ known
                     THEN [ent EXCEPT !.acks = newAcks, !.freshAcks = newFresh]
                     ELSE pendingReads[i][c]]
        released == IF quorum
                    THEN ReleasedReadSeq(i, pos, m.ctx, newAcks \cup {i})
                    ELSE <<>>
        newReleases ==
            {[leader |-> i, term |-> term[i], ctx |-> readQueue[i][k],
              owner |-> pendingReads[i][readQueue[i][k]].requester,
              index |-> pendingReads[i][readQueue[i][k]].index,
              bound |-> pendingReads[i][readQueue[i][k]].bound,
              inc |-> pendingReads[i][readQueue[i][k]].inc,
              acks |-> newAcks \cup {i},
              freshAcks |-> newFresh \cup {i}] :
             k \in IF quorum THEN 1..pos ELSE {}}
        localReads == SelectSeq(released, LAMBDA rr : rr.owner = i)
        remoteReads == {rr \in {released[k] : k \in 1..Len(released)} :
                            rr.owner /= i}
        responses ==
            {Msg(MsgReadIndexResp, i, rr.owner, term[i], rr.index,
                 0, 0, 0, Nil, rr.ctx, FALSE) : rr \in remoteReads}
    IN
    /\ alive[i]
    /\ role[i] = Leader
    /\ m.mtype = MsgHeartbeatResp
    /\ m.to = i
    /\ m.term = term[i]
    /\ recentActive' = [recentActive EXCEPT ![i][m.from] = TRUE]
    \* UPDATE-MAP
    \* code: read_only.go:100-105 delete(pendingReadIndex, Entries[0].Data)
    \* update: Update!AffectedActions (MCHandleHeartbeatResponse)
    \* Released contexts leave pendingReads; V0 kept them active.
    /\ pendingReads' = [pendingReads EXCEPT ![i] = np]
    /\ readQueue' = [readQueue EXCEPT ![i] =
                       IF quorum THEN SubSeq(@, pos + 1, Len(@)) ELSE @]
    /\ producedReads' = [producedReads EXCEPT ![i] =
         IF quorum THEN @ \o localReads
         ELSE @]
    /\ readReleases' = readReleases \cup newReleases
    /\ messages' = (messages \ {m}) \cup responses
    /\ scenarioSeen' = [scenarioSeen EXCEPT
                          !.readQuorum = @ \/ quorum]
    /\ UNCHANGED <<serverVars, durableVars, matchIndex, nextIndex,
                    votesGranted, publishedReads, interfaceVars, alive,
                    leaderHistory, commitHistory, readInc>>

\* stepFollower MsgReadIndexResp (raft.go:1075-1080).  Ghost justification
\* is looked up in the release history because the updated leader no longer
\* retains the released pending entry.
HandleReadIndexResponse(i, m) ==
    LET matches == {r \in readReleases :
                      /\ r.leader = m.from /\ r.owner = i
                      /\ r.ctx = m.ctx /\ r.index = m.index
                      /\ r.term = m.term}
        evidence == IF matches = {} THEN {}
                    ELSE (CHOOSE r \in matches : TRUE).acks
        rr == [owner |-> i, leader |-> m.from, index |-> m.index,
               ctx |-> m.ctx, justificationCtx |-> m.ctx,
               acks |-> evidence]
    IN
    /\ alive[i]
    /\ m.mtype = MsgReadIndexResp
    /\ m.to = i
    /\ m.ctx \in ReadContexts
    /\ producedReads' = [producedReads EXCEPT ![i] = Append(@, rr)]
    /\ messages' = messages \ {m}
    /\ scenarioSeen' = [scenarioSeen EXCEPT !.readResponse = TRUE]
    /\ UNCHANGED <<serverVars, durableVars, leaderVars, pendingReads,
                    readQueue, publishedReads, interfaceVars, alive,
                    leaderHistory, commitHistory, readGhostVars>>

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
                    readGhostVars>>

ReadyAdvance(i) ==
    /\ alive[i]
    /\ readyOutstanding[i]
    /\ appliedIndex' = [appliedIndex EXCEPT ![i] = commitIndex[i]]
    /\ readyOutstanding' = [readyOutstanding EXCEPT ![i] = FALSE]
    /\ UNCHANGED <<term, vote, role, leader, logs, commitIndex,
                    durableVars, leaderVars, messages, readVars, alive,
                    historyVars, readGhostVars>>

(***************************************************************************
 * CheckQuorum. raft.go:535-559, 791-796, 1214-1235.
 * Step-down is becomeFollower(r.Term, None) -> reset (raft.go:794, 510).
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
    \* UPDATE-MAP (repair) code: raft.go:794 becomeFollower -> raft.go:510
    \* update: Update!EnvUpdate (EnvStepDown) / Update!DischargeCheckQuorum
    /\ pendingReads' = [pendingReads EXCEPT ![i] =
                          IF active THEN @ ELSE ClearedPending]
    /\ readQueue' = [readQueue EXCEPT ![i] = IF active THEN @ ELSE <<>>]
    /\ scenarioSeen' = [scenarioSeen EXCEPT !.quorumCheck = TRUE]
    /\ UNCHANGED <<term, vote, logs, commitIndex, appliedIndex,
                    durableVars, matchIndex, nextIndex, votesGranted,
                    messages, producedReads, publishedReads, interfaceVars,
                    alive, leaderHistory, commitHistory, readGhostVars>>

(***************************************************************************
 * Crash/restart and network loss. node.go Ready durability; rafttest network.
 *************************************************************************)
\* Messages are handed to the transport only after the Ready that carries
\* them is persisted (node.go:58-85); until then they live in volatile
\* r.msgs.  A crash therefore loses every message of i not yet justified by
\* i's durable state.  (V1 repair, Case B: V0 kept them in flight, and a
\* later, different durable entry could satisfy the length-only MsgAppResp
\* gate -- spec/changelog.md, output/update-focused-nk.*.)
Crash(i) ==
    /\ alive[i]
    /\ alive' = [alive EXCEPT ![i] = FALSE]
    /\ messages' = {m \in messages : m.from /= i \/ PublishedBySender(m)}
    /\ scenarioSeen' = [scenarioSeen EXCEPT !.crash = TRUE]
    /\ UNCHANGED <<serverVars, durableVars, leaderVars, readVars,
                    interfaceVars, leaderHistory, commitHistory,
                    readGhostVars>>

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
    /\ pendingReads' = [pendingReads EXCEPT ![i] = ClearedPending]
    /\ readQueue' = [readQueue EXCEPT ![i] = <<>>]
    /\ producedReads' = [producedReads EXCEPT ![i] = <<>>]
    /\ readyOutstanding' = [readyOutstanding EXCEPT ![i] = FALSE]
    /\ scenarioSeen' = [scenarioSeen EXCEPT !.restart = TRUE]
    /\ UNCHANGED <<durableVars, matchIndex, nextIndex, messages,
                    publishedReads, leaderHistory, commitHistory,
                    readGhostVars>>

LoseMessage(m) ==
    /\ m \in messages
    /\ messages' = messages \ {m}
    /\ scenarioSeen' = [scenarioSeen EXCEPT !.loss = TRUE]
    /\ UNCHANGED <<serverVars, durableVars, leaderVars, readVars,
                    interfaceVars, alive, leaderHistory, commitHistory,
                    readGhostVars>>

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

PendingRecord ==
    [active : BOOLEAN, index : 0..MaxLogLen,
     requester : Server \cup {Nil}, acks : SUBSET Server,
     inc : Nat, bound : 0..MaxLogLen, freshAcks : SUBSET Server]

ReleaseRecord ==
    [leader : Server, term : 0..MaxTerm, ctx : ReadContexts,
     owner : Server, index : 0..MaxLogLen, bound : 0..MaxLogLen,
     inc : Nat, acks : SUBSET Server, freshAcks : SUBSET Server]

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
    /\ \A m \in messages : MsgWellFormed(m)
    /\ pendingReads \in [Server -> [ReadContexts -> PendingRecord]]
    /\ readQueue \in [Server -> Seq(ReadContexts)]
    /\ producedReads \in [Server -> Seq([
         owner : Server, leader : Server, index : 0..MaxLogLen,
         ctx : ReadContexts, justificationCtx : ReadContexts,
         acks : SUBSET Server])]
    /\ publishedReads \in Seq([
         owner : Server, leader : Server, index : 0..MaxLogLen,
         ctx : ReadContexts, justificationCtx : ReadContexts,
         acks : SUBSET Server])
    /\ readyOutstanding \in [Server -> BOOLEAN]
    /\ alive \in [Server -> BOOLEAN]
    /\ readInc \in [Server -> [ReadContexts -> Nat]]
    /\ readReleases \subseteq ReleaseRecord

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
