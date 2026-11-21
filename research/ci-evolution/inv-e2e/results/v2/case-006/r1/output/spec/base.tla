------------------------------ MODULE base ------------------------------
(***************************************************************************
 * etcd Raft core, derived only from the supplied source trees.
 * Category A: distributed/message-passing, crash faults.
 *
 * Revision: updated reference for the `update` source revision
 * (artifact c780d355).  The update changes readOnly.advance so that every
 * released ReadIndex request is deleted from pendingReadIndex under its real
 * key string(req.Entries[0].Data) (read_only.go:100-105).  The exact-old V0
 * suite deliberately kept those entries (old key string(req.Context)).
 *
 * Model repairs made in the same revision (implementation-backed, required
 * to verify the update without spurious read-state carry-over):
 *   R1 raft.reset() recreates readOnly on becomeFollower/becomeCandidate/
 *      becomeLeader (raft.go:489-511); V0 never cleared read state on a role
 *      transition.
 *   R2 HandleReadIndexResponse took its justification from the leader's live
 *      pending map, which only worked because exact-old never freed entries;
 *      it now uses the leader-side release history `servedReads`.
 *   R3 HandleReadIndexResponse follows raft.Step term handling
 *      (raft.go:679-735) and stepFollower/stepCandidate/stepLeader dispatch.
 * Ghost/history state added for update properties (no behavioral effect):
 *   readStamp, servedReads, pending.stamp/ackLog/gcommit, message gstamp.
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

\* Pending readIndexStatus (read_only.go:29-33) for one caller context.
\* active/index/requester/acks are behavioral; stamp, ackLog and gcommit are
\* ghost fields used only by Update.tla properties.
\* UPDATE-MAP
\* code: read_only.go:52-59 addRequest; read_only.go:78-109 advance
\* update: Update!UpdPendingMatchesQueue, Update!UpdReadAckFresh,
\*         Update!UpdReadIndexLinearizable
EmptyPending == [active |-> FALSE, index |-> 0, requester |-> Nil,
                 acks |-> {}, stamp |-> 0, ackLog |-> {}, gcommit |-> 0]
EmptyPendingMap == [c \in ReadContexts |-> EmptyPending]

\* gstamp is a ghost field: for MsgHeartbeatResp it records the global read
\* registration stamp current when the follower generated the response.  It
\* is 0 for every other message and never influences behavior.
Msg(mt, from, to, tm, idx, ltm, com, etm, val, ctx, rej) ==
    [mtype |-> mt, from |-> from, to |-> to, term |-> tm,
     index |-> idx, logTerm |-> ltm, commit |-> com,
     entryTerm |-> etm, value |-> val, ctx |-> ctx, reject |-> rej,
     gstamp |-> 0]

VARIABLES
    term, vote, role, leader, logs, commitIndex, appliedIndex,
    durableTerm, durableVote, durableLogs, durableCommit,
    matchIndex, nextIndex, votesGranted, recentActive,
    messages, pendingReads, readQueue, producedReads, publishedReads,
    readyOutstanding, alive, leaderHistory, commitHistory,
    scenarioSeen, readStamp, servedReads

serverVars == <<term, vote, role, leader, logs, commitIndex, appliedIndex>>
durableVars == <<durableTerm, durableVote, durableLogs, durableCommit>>
leaderVars == <<matchIndex, nextIndex, votesGranted, recentActive>>
readVars == <<pendingReads, readQueue, producedReads, publishedReads>>
interfaceVars == <<readyOutstanding>>
historyVars == <<leaderHistory, commitHistory, scenarioSeen>>
\* Ghost read history (update properties only).
\* UPDATE-MAP
\* code: read_only.go:78-109 advance; raft.go:915-932 MsgHeartbeatResp
\* update: Update!UpdReadAckFresh, Update!UpdReadIndexLinearizable
readGhostVars == <<readStamp, servedReads>>
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

LastPendingCtx(i) ==
    IF Len(readQueue[i]) = 0 THEN Nil ELSE readQueue[i][Len(readQueue[i])]

ActiveCount(i) ==
    Cardinality({j \in Server : j = i \/ recentActive[i][j]})

\* Ghost: highest log index committed anywhere so far (commitHistory is the
\* leader-side commit record written by HandleAppendResponse).
MaxCommitted ==
    IF commitHistory = {} THEN 0
    ELSE CHOOSE k \in {ch.index : ch \in commitHistory} :
           \A ch \in commitHistory : k >= ch.index

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
    /\ m.gstamp \in Nat

(***************************************************************************
 * raft.reset() (raft.go:489-511) ends with
 *     r.readOnly = newReadOnly(r.readOnly.option)
 * and is called by becomeFollower (raft.go:561-568), becomeCandidate
 * (raft.go:570-581) and becomeLeader (raft.go:597-622).  r.readStates is
 * NOT reset.  [Repair R1]
 * UPDATE-MAP
 * code: raft.go:489-511 reset; read_only.go:41-46 newReadOnly
 * update: Update!InteractionActions (role transitions), Update!EnvUpdate
 *************************************************************************)
ReadOnlyAfterReset(i, cond) ==
    /\ pendingReads' = [pendingReads EXCEPT ![i] =
                          IF cond THEN EmptyPendingMap ELSE @]
    /\ readQueue' = [readQueue EXCEPT ![i] = IF cond THEN <<>> ELSE @]

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
    /\ pendingReads = [i \in Server |-> EmptyPendingMap]
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
                         loss |-> FALSE, crash |-> FALSE, restart |-> FALSE,
                         readFreed |-> FALSE, readReuse |-> FALSE,
                         staleAck |-> FALSE]
    /\ readStamp = 0
    /\ servedReads = {}

(***************************************************************************
 * Election actions. raft.go:525-532, 570-581, 624-677.
 * becomeCandidate -> reset(r.Term+1) recreates readOnly (raft.go:571, 510).
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
    /\ ReadOnlyAfterReset(i, TRUE)                       \* raft.go:510 [R1]
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
 * A higher-term MsgVote calls becomeFollower(m.Term, None) -> reset
 * (raft.go:684-711).  The CheckQuorum in-lease rejection (raft.go:686-695)
 * remains abstracted as in V0 (vote requests are always processed).
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
    /\ ReadOnlyAfterReset(i, higher)                     \* raft.go:710 [R1]
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
 * becomeLeader -> reset(r.Term) recreates readOnly (raft.go:602, 510).
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
    /\ ReadOnlyAfterReset(i, TRUE)                       \* raft.go:510 [R1]
    /\ messages' = messages \cup
         {Msg(MsgApp, i, j, term[i], li - 1,
              IF li = 1 THEN 0 ELSE nl[li-1].term,
              commitIndex[i], term[i], Nil, Nil, FALSE)
          : j \in Server \ {i}}
    /\ leaderHistory' = leaderHistory \cup {[node |-> i, term |-> term[i]]}
    /\ scenarioSeen' = [scenarioSeen EXCEPT !.leader = TRUE]
    /\ UNCHANGED <<term, vote, commitIndex, appliedIndex, durableVars,
                    votesGranted, recentActive, producedReads, publishedReads,
                    interfaceVars, alive, commitHistory, readGhostVars>>

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
 * becomeFollower (and its reset) runs for a higher term (raft.go:710) or for
 * a candidate receiving an equal-term MsgApp (raft.go:1000-1002). [R1]
 *************************************************************************)
HandleAppendEntries(i, m) ==
    LET termOK == m.term >= term[i]
        becomesFollower == \/ m.term > term[i]
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
    /\ ReadOnlyAfterReset(i, becomesFollower)            \* raft.go:510 [R1]
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
 * bcastHeartbeat attaches lastPendingRequestCtx (raft.go:457-464,
 * read_only.go:111-118).
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

\* handleHeartbeat echoes m.Context (raft.go:1112-1115).  The response's
\* ghost gstamp records the read-registration stamp current at generation.
HandleHeartbeat(i, m) ==
    LET termOK == m.term >= term[i]
        becomesFollower == \/ m.term > term[i]
                           \/ (m.term = term[i] /\ role[i] = Candidate)
        nt == IF m.term > term[i] THEN m.term ELSE term[i]
        nc == IF termOK THEN Max2(commitIndex[i], Min2(m.commit, LastIndex(i)))
              ELSE commitIndex[i]
        resp == [Msg(MsgHeartbeatResp, i, m.from, nt, 0, 0, 0, 0,
                     Nil, m.ctx, FALSE) EXCEPT !.gstamp = readStamp]
    IN
    /\ alive[i]
    /\ m.mtype = MsgHeartbeat
    /\ m.to = i
    /\ term' = [term EXCEPT ![i] = nt]
    /\ vote' = [vote EXCEPT ![i] = IF m.term > term[i] THEN Nil ELSE @]
    /\ role' = [role EXCEPT ![i] = IF termOK THEN Follower ELSE @]
    /\ leader' = [leader EXCEPT ![i] = IF termOK THEN m.from ELSE @]
    /\ commitIndex' = [commitIndex EXCEPT ![i] = nc]
    /\ ReadOnlyAfterReset(i, becomesFollower)            \* raft.go:510 [R1]
    /\ messages' = (messages \ {m}) \cup {resp}
    /\ UNCHANGED <<logs, appliedIndex, durableVars, leaderVars, producedReads,
                    publishedReads, interfaceVars, alive, historyVars,
                    readGhostVars>>

(***************************************************************************
 * ReadIndex enqueue. raft.go:824-853; read_only.go:48-59.
 * addRequest ignores a context already present in pendingReadIndex.  Since
 * the update frees released contexts, a context released earlier in the same
 * leader term can now be registered again (readReuse).
 * UPDATE-MAP
 * code: read_only.go:52-59 addRequest (dedup guard now sees freed entries);
 *       raft.go:836-837 addRequest + bcastHeartbeatWithCtx
 * update: Update!AffectedActions (MCClientReadIndex, MCHandleReadIndexRequest)
 *************************************************************************)
ProcessReadIndex(i, c, requester, consumed) ==
    LET multi == Cardinality(Server) > 1
        eligible == ~multi \/
                    (commitIndex[i] > 0 /\ TermAt(i, commitIndex[i]) = term[i])
        duplicate == pendingReads[i][c].active           \* read_only.go:54-56
        register == eligible /\ multi /\ ~duplicate
        ns == readStamp + 1
        reuse == /\ register
                 /\ \E sr \in servedReads :
                      sr.leader = i /\ sr.term = term[i] /\ sr.ctx = c
        np == IF register
              THEN [pendingReads EXCEPT ![i][c] =        \* read_only.go:57
                     [active |-> TRUE, index |-> commitIndex[i],
                      requester |-> requester, acks |-> {},
                      stamp |-> ns, ackLog |-> {}, gcommit |-> MaxCommitted]]
              ELSE pendingReads
        nq == IF register                                 \* read_only.go:58
              THEN [readQueue EXCEPT ![i] = Append(@, c)] ELSE readQueue
        oneRead == [owner |-> requester, leader |-> i,
                    index |-> commitIndex[i], ctx |-> c,
                    justificationCtx |-> c, acks |-> {i}]
        oneServed == [leader |-> i, term |-> term[i], owner |-> requester,
                      ctx |-> c, justificationCtx |-> c,
                      index |-> commitIndex[i], acks |-> {i},
                      freshAcks |-> {i}, gcommit |-> MaxCommitted,
                      stamp |-> readStamp]
    IN
    /\ alive[i]
    /\ role[i] = Leader
    /\ c \in ReadContexts
    /\ requester \in Server
    /\ eligible                                          \* raft.go:826-829
    /\ pendingReads' = np
    /\ readQueue' = nq
    /\ readStamp' = IF register THEN ns ELSE readStamp
    /\ producedReads' = IF multi THEN producedReads      \* raft.go:850
                         ELSE [producedReads EXCEPT ![i] = Append(@, oneRead)]
    /\ servedReads' = IF multi THEN servedReads ELSE servedReads \cup {oneServed}
    /\ messages' = IF multi                              \* raft.go:837
         THEN (messages \ consumed) \cup
              {Msg(MsgHeartbeat, i, j, term[i], 0, 0,
                   Min2(matchIndex[i][j], commitIndex[i]), 0, Nil,
                   c, FALSE) : j \in Server \ {i}}
         ELSE messages \ consumed
    /\ scenarioSeen' = [scenarioSeen EXCEPT
                          !.readRequest = TRUE,
                          !.readForward = TRUE,
                          !.readReuse = @ \/ reuse]
    /\ UNCHANGED <<serverVars, durableVars, leaderVars, publishedReads,
                    interfaceVars, alive, leaderHistory, commitHistory>>

ClientReadIndex(i, c, requester) ==
    ProcessReadIndex(i, c, requester, {})

\* stepFollower MsgReadIndex forwards to r.lead without a term
\* (raft.go:356-360, 1068-1074).
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

\* Ghost release record.  freshAcks keeps only acknowledgements generated at
\* or after this request's own registration (plus the leader's implicit ack).
ServedRecord(i, c, jctx, jacks, jlog) ==
    LET p == pendingReads[i][c] IN
    [leader |-> i, term |-> term[i], owner |-> p.requester, ctx |-> c,
     justificationCtx |-> jctx, index |-> p.index, acks |-> jacks,
     freshAcks |-> {a.node : a \in {x \in jlog : x.stamp >= p.stamp}} \cup {i},
     gcommit |-> p.gcommit, stamp |-> p.stamp]

(***************************************************************************
 * Heartbeat response: progress activity plus context ack and FIFO-prefix
 * advance. raft.go:903-932; read_only.go:61-109.
 * UPDATE-MAP
 * code: read_only.go:100-105 advance deletes every released request under
 *       string(rs.req.Entries[0].Data), the key addRequest used
 *       (read_only.go:53).  Exact-old deleted string(rs.req.Context).
 * update: Update!AffectedActions (MCHandleHeartbeatResponse),
 *         Update!UpdPendingMatchesQueue, Update!UpdReadAckFresh
 *************************************************************************)
HandleHeartbeatResponse(i, m) ==
    LET known == m.ctx \in ReadContexts /\ pendingReads[i][m.ctx].active
                                                         \* read_only.go:65-68
        newAcks == IF known                              \* read_only.go:70
                   THEN pendingReads[i][m.ctx].acks \cup {m.from}
                   ELSE {}
        newAckLog == IF known
                     THEN pendingReads[i][m.ctx].ackLog \cup
                            {[node |-> m.from, stamp |-> m.gstamp]}
                     ELSE {}
        quorum == known /\ Cardinality(newAcks \cup {i}) >= Quorum
                                                         \* raft.go:919-922
        positions == IF known THEN {k \in 1..Len(readQueue[i]) :
                                      readQueue[i][k] = m.ctx} ELSE {}
        pos == IF positions = {} THEN 0 ELSE CHOOSE k \in positions : TRUE
        relPos == IF quorum THEN pos ELSE 0              \* read_only.go:87-100
        releasedCtxs == {readQueue[i][k] : k \in 1..relPos}
        acked == [c \in ReadContexts |->
                   IF c = m.ctx /\ known
                     THEN [pendingReads[i][c] EXCEPT !.acks = newAcks,
                                                     !.ackLog = newAckLog]
                     ELSE pendingReads[i][c]]
        \* read_only.go:102-104: delete every released request [update]
        np == [c \in ReadContexts |->
                IF c \in releasedCtxs THEN EmptyPending ELSE acked[c]]
        released == IF quorum
                    THEN ReleasedReadSeq(i, pos, m.ctx, newAcks \cup {i})
                    ELSE <<>>
        served == {ServedRecord(i, readQueue[i][k], m.ctx, newAcks \cup {i},
                                newAckLog) : k \in 1..relPos}
        localReads == SelectSeq(released, LAMBDA rr : rr.owner = i)
        remoteReads == {rr \in {released[k] : k \in 1..Len(released)} :
                            rr.owner /= i}
        responses ==                                     \* raft.go:925-931
            {Msg(MsgReadIndexResp, i, rr.owner, term[i], rr.index,
                 0, 0, 0, Nil, rr.ctx, FALSE) : rr \in remoteReads}
        stale == known /\ m.gstamp < pendingReads[i][m.ctx].stamp
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
    /\ servedReads' = servedReads \cup served
    /\ messages' = (messages \ {m}) \cup responses
    /\ scenarioSeen' = [scenarioSeen EXCEPT
                          !.readQuorum = @ \/ quorum,
                          !.readFreed = @ \/ (releasedCtxs /= {}),
                          !.staleAck = @ \/ stale]
    /\ UNCHANGED <<serverVars, durableVars, matchIndex, nextIndex,
                    votesGranted, publishedReads, interfaceVars, alive,
                    leaderHistory, commitHistory, readStamp>>

(***************************************************************************
 * MsgReadIndexResp receipt.  raft.Step (raft.go:679-735): a higher term makes
 * the receiver becomeFollower(m.Term, m.From) (with reset); a lower term is
 * ignored.  Only stepFollower appends a ReadState (raft.go:1075-1080);
 * stepCandidate and stepLeader have no MsgReadIndexResp case.  [R3]
 * The read record's justification comes from the leader-side release history
 * (servedReads); V0 read the leader's live pending map, which the update now
 * frees on release.  [R2]
 * UPDATE-MAP
 * code: raft.go:1075-1080; raft.go:925-931 (producer)
 * update: Update!AffectedActions (MCHandleReadIndexResponse)
 *************************************************************************)
HandleReadIndexResponse(i, m) ==
    LET higher == m.term > term[i]
        accept == m.term >= term[i] /\ (higher \/ role[i] = Follower)
        matches == {sr \in servedReads :
                      /\ sr.leader = m.from /\ sr.owner = i
                      /\ sr.term = m.term /\ sr.ctx = m.ctx
                      /\ sr.index = m.index}
        evidence == IF matches = {} THEN {}
                    ELSE (CHOOSE sr \in matches : TRUE).acks
        rr == [owner |-> i, leader |-> m.from, index |-> m.index,
               ctx |-> m.ctx, justificationCtx |-> m.ctx,
               acks |-> evidence]
    IN
    /\ alive[i]
    /\ m.mtype = MsgReadIndexResp
    /\ m.to = i
    /\ m.ctx \in ReadContexts
    /\ term' = [term EXCEPT ![i] = IF higher THEN m.term ELSE @]
    /\ vote' = [vote EXCEPT ![i] = IF higher THEN Nil ELSE @]
    /\ role' = [role EXCEPT ![i] = IF higher THEN Follower ELSE @]
    /\ leader' = [leader EXCEPT ![i] = IF higher THEN m.from ELSE @]
    /\ ReadOnlyAfterReset(i, higher)
    /\ producedReads' = [producedReads EXCEPT ![i] =
                           IF accept THEN Append(@, rr) ELSE @]
    /\ messages' = messages \ {m}
    /\ scenarioSeen' = [scenarioSeen EXCEPT !.readResponse = @ \/ accept]
    /\ UNCHANGED <<logs, commitIndex, appliedIndex, durableVars, leaderVars,
                    publishedReads, interfaceVars, alive,
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
 * Step-down is becomeFollower(r.Term, None) and therefore resets readOnly.
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
    /\ ReadOnlyAfterReset(i, ~active)                    \* raft.go:794 [R1]
    /\ scenarioSeen' = [scenarioSeen EXCEPT !.quorumCheck = TRUE]
    /\ UNCHANGED <<term, vote, logs, commitIndex, appliedIndex,
                    durableVars, matchIndex, nextIndex, votesGranted,
                    messages, producedReads, publishedReads, interfaceVars,
                    alive, leaderHistory, commitHistory, readGhostVars>>

(***************************************************************************
 * Crash/restart and network loss. node.go Ready durability; rafttest network.
 *************************************************************************)
Crash(i) ==
    /\ alive[i]
    /\ alive' = [alive EXCEPT ![i] = FALSE]
    /\ scenarioSeen' = [scenarioSeen EXCEPT !.crash = TRUE]
    /\ UNCHANGED <<serverVars, durableVars, leaderVars, messages, readVars,
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
    /\ pendingReads' = [pendingReads EXCEPT ![i] = EmptyPendingMap]
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

\* REQ-EVIDENCE TypeOK
\* intent:   every variable except the history variables leaderHistory, commitHistory and scenarioSeen stays within its declared type and value range.
\* status:   model-internal
\* verified: update (c780d355)
\* review:   intent narrowed from "every model variable" because the formula does not constrain leaderHistory, commitHistory or scenarioSeen.
\* note:     representation-only revision for the update: ghost fields gstamp (messages), stamp/ackLog/gcommit (pending reads) and the ghost variables readStamp/servedReads are typed; no behavioral constraint changed.
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
                                     reject : BOOLEAN,
                                     gstamp : Nat] : MsgWellFormed(m)}
    /\ pendingReads \in [Server -> [ReadContexts ->
         [active : BOOLEAN, index : 0..MaxLogLen,
          requester : Server \cup {Nil}, acks : SUBSET Server,
          stamp : Nat, ackLog : SUBSET [node : Server, stamp : Nat],
          gcommit : 0..MaxLogLen]]]
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
    /\ readStamp \in Nat
    /\ servedReads \subseteq [leader : Server, term : 0..MaxTerm,
                              owner : Server, ctx : ReadContexts,
                              justificationCtx : ReadContexts,
                              index : 0..MaxLogLen, acks : SUBSET Server,
                              freshAcks : SUBSET Server,
                              gcommit : 0..MaxLogLen, stamp : Nat]

\* REQ-EVIDENCE ElectionSafety
\* intent:   in any one term, at most one server becomes leader.
\* status:   requirement
\* evidence: test source/raft_paper_test.go:234 TestFollowerVote "each follower will vote for at most one" -> a server grants at most one vote in a given term
\* evidence: test source/raft_paper_test.go:211 TestLeaderElectionInOneRoundRPC "stay in candidate if it does not obtain the majority" -> a candidate without votes from a majority does not become leader, so two leaders in one term would need some server to vote twice
\* evidence: doc source/README.md:116 "no messages be sent until the latest HardState has been persisted to disk" -> a cast vote is durable before any vote reply leaves the node, so a restart cannot re-vote in the same term
\* evidence: impl source/raft.go:762 "(r.Vote == None || m.Term > r.Term || r.Vote == m.From)"
\* evidence: impl source/raft.go:1014 "switch r.quorum() {"
\* watch:    raft.go:Step; raft.go:poll; raft.go:stepCandidate; raft.go:campaign; raft.go:becomeLeader; raft.go:quorum; raft.go:reset; node.go:newReady
\* verified: base
\* note:     the Raft paper is cited at README.md:5-6 and raft_paper_test.go:15-17 but its text is not in /work, so no protocol line is recorded; searched source and history for "one leader", "at most one leader", "Election Safety" and found no direct statement; the intent follows from the two tested rules; the line-198 cases of TestLeaderElectionInOneRoundRPC ("win the election when receiving votes from a majority") show only that a majority suffices, so the line-211 cases, which assert that a candidate without a majority does not become leader, are cited instead; history 0b2b904 (message "raft: add tests based on section 5.2 in raft paper") only names the paper section the tests follow and states no rule, so it is not counted as evidence
\* review:   re-pointed the TestLeaderElectionInOneRoundRPC line from 198 (a majority suffices) to 211 (a majority is needed) because only the latter supports the claimed part, and moved the provenance-only history 0b2b904 line to the note because it supports no part of the intent.
ElectionSafety ==
    \A t \in 1..MaxTerm :
        Cardinality({i \in Server : [node |-> i, term |-> t] \in leaderHistory}) <= 1

\* REQ-EVIDENCE CommitWithinLog
\* intent:   on every server the applied index never exceeds the commit index, the commit index never exceeds the last log index, and the persisted commit index never exceeds the persisted log length.
\* status:   requirement
\* evidence: comment source/log.go:37 "Invariant: applied <= committed" -> the applied index never exceeds the commit index
\* evidence: comment source/raft.go:432 "The leader MUST NOT forward the follower's commit to" -> a follower's commit index must not point past entries it holds
\* evidence: test source/log_test.go:451 TestCommitTo "commit out of range -> panic" -> committing beyond the last log index is treated as an error
\* evidence: test source/log_test.go:189 TestLogMaybeAppend "do not increase commit higher than lastnewi" -> the commit index is capped by the entries actually in the log
\* evidence: history 5e1859c (message) "raft: panic if loaded commit is out of range" -> a persisted commit index must lie within the persisted log when it is reloaded
\* evidence: impl source/log.go:201 "if l.committed < i || i < l.applied {"
\* evidence: impl source/log.go:190 "if l.lastIndex() < tocommit {"
\* evidence: impl source/raft.go:1195 "state.Commit > r.raftLog.lastIndex()"
\* watch:    log.go:raftLog.committed; log.go:appliedTo; log.go:commitTo; log.go:maybeAppend; raft.go:sendHeartbeat; raft.go:handleHeartbeat; raft.go:loadState; node.go:run; rawnode.go:commitReady
\* verified: base
\* note:     history e769766 (message) says a follower may see "commit > unstable"; that is about the boundary of locally stable entries, not about the persisted HardState against the persisted log, so it is counted neither for nor against the persisted clause
\* review:   ok
CommitWithinLog ==
    \A i \in Server :
        /\ appliedIndex[i] <= commitIndex[i]
        /\ commitIndex[i] <= Len(logs[i])
        /\ durableCommit[i] <= Len(durableLogs[i])

\* REQ-EVIDENCE LogMatching
\* intent:   whenever two servers' logs hold entries with the same term at the same index, the two logs are identical up to and including that index.
\* status:   requirement
\* evidence: test source/raft_paper_test.go:597 TestFollowerCheckMsgApp "entry in its log with the same index and term" -> a follower accepts new entries only after a preceding entry whose index and term match the leader's
\* evidence: test source/raft_paper_test.go:641 TestFollowerAppendEntries "the follower will delete the existing conflict entry and all that follow it" -> a conflicting entry and its whole suffix are replaced by the leader's entries
\* evidence: test source/raft_paper_test.go:694 TestLeaderSyncFollowerLog "the leader could bring a follower's log" -> the leader brings each follower's log into consistency with its own
\* evidence: test source/raft_paper_test.go:390 TestLeaderStartReplication "the leader appends the proposal to its log as a new entry" -> a leader only adds entries after its last entry, so with one leader per term no term places two different entries at the same index
\* evidence: impl source/log.go:77 "if l.matchTerm(index, logTerm) {"
\* evidence: impl source/log.go:118 "if !l.matchTerm(ne.Index, ne.Term) {"
\* watch:    log.go:maybeAppend; log.go:findConflict; log.go:matchTerm; log_unstable.go:truncateAndAppend; raft.go:handleAppendEntries; raft.go:sendAppend; raft.go:appendEntry
\* verified: base
\* note:     searched source and history for "Log Matching" and "log matching" and found nothing; the Raft paper text is not in /work; the tests record the per-append rules (prefix check, conflict truncation, leader append) from which the property follows by induction together with the one-leader-per-term evidence recorded for ElectionSafety; history d747117 (message "raft: add tests based on section 5.3 in raft paper") only names the paper section the tests follow and states no rule, so it is not counted as evidence
\* review:   moved the provenance-only history d747117 line to the note because it supports no part of the intent, and added the TestLeaderStartReplication line because the cited tests covered the prefix check but not the premise that a term places at most one entry at each index.
LogMatching ==
    \A i, j \in Server : \A k \in 1..Min2(Len(logs[i]), Len(logs[j])) :
        logs[i][k].term = logs[j][k].term =>
            SubSeq(logs[i], 1, k) = SubSeq(logs[j], 1, k)

\* REQ-EVIDENCE CommittedPrefixAgreement
\* intent:   any two servers hold identical log entries up to the smaller of their two commit indexes.
\* status:   requirement
\* evidence: doc source/README.md:4 "The state machine is kept in sync through the use of a replicated log." -> replicas apply the same log, so their committed prefixes must agree
\* evidence: test source/raft_paper_test.go:472 TestLeaderAcknowledgeCommit "leader that created the entry has replicated it on a majority of the servers" -> an entry counts as committed only once a majority holds it
\* evidence: comment source/log.go:32 "committed is the highest log position that is known to be in" -> a committed position is one known to be in stable storage on a quorum (continues on line 33)
\* evidence: impl source/log.go:83 "entry %d conflict with committed entry [committed(%d)]"
\* evidence: impl source/raft.go:485 "mci := mis[r.quorum()-1]"
\* watch:    log.go:maybeAppend; log.go:maybeCommit; log.go:commitTo; raft.go:maybeCommit; raft.go:handleAppendEntries; raft.go:handleHeartbeat; raft.go:sendHeartbeat
\* verified: base
\* note:     doc.go:19-20 repeats the README sentence; searched history for "State Machine Safety" and found nothing; the Raft paper text is not in /work; the TestLogMaybeAppend case at log_test.go:230 ("conflict with existing committed entry") sets wpanic, but the test's recover handler reports only unexpected panics and the case's other expected values also hold if the committed entry were overwritten, so the test does not assert that committed entries are kept and is not counted
\* review:   removed the TestLogMaybeAppend line-230 evidence because the test never checks that the expected panic occurs, so it does not assert that a committed entry is kept; the README, TestLeaderAcknowledgeCommit and log.go:32 lines still support the intent.
CommittedPrefixAgreement ==
    \A i, j \in Server :
        SubSeq(logs[i], 1, Min2(commitIndex[i], commitIndex[j])) =
        SubSeq(logs[j], 1, Min2(commitIndex[i], commitIndex[j]))

\* REQ-EVIDENCE LeaderCompleteness
\* intent:   an entry committed in some term appears, at the same index with the same term and value, in the log of every server that became leader in a later term.
\* status:   requirement
\* evidence: test source/raft_paper_test.go:820 TestVoter "the voter denies its vote if its own log is more up-to-date" -> a candidate whose log is behind a voter's cannot win that vote
\* evidence: test source/raft_paper_test.go:874 TestLeaderOnlyCommitsLogFromCurrentTerm "do not commit log entries in previous terms" -> commitment by counting replicas applies only to current-term entries
\* evidence: test source/raft_test.go:643 TestCannotCommitWithoutNewTermEntry "no log entries from previous term should be committed" -> the same restriction holds across a leader change
\* evidence: test source/raft_paper_test.go:472 TestLeaderAcknowledgeCommit "replicated it on a majority of the servers" -> a committed entry is held by a majority, which every electing majority overlaps
\* evidence: impl source/log.go:268 "return term > l.lastTerm() || (term == l.lastTerm() && lasti >= l.lastIndex())"
\* evidence: impl source/log.go:280 "maxIndex > l.committed && l.zeroTermOnErrCompacted(l.term(maxIndex)) == term"
\* watch:    log.go:isUpToDate; log.go:maybeCommit; raft.go:Step; raft.go:maybeCommit; raft.go:campaign; raft.go:becomeLeader; raft.go:handleAppendEntries
\* verified: base
\* note:     searched source and history for "Leader Completeness" and found nothing; the Raft paper text is not in /work; the isUpToDate comment at log.go:261-266 (added by 76f7f7a) only narrates the comparison, so it is treated as impl narration and not listed; doc.go:249-252 words the vote rule in terms of a "last committed index", which differs from the rule TestVoter checks, so it is not counted; history 5c55fdf (message "raft: add paper tests for section 5.4.1") only names the paper section the tests follow and states no rule, so it is not counted as evidence
\* review:   moved the provenance-only history 5c55fdf line to the note because the commit message supports no part of the intent; the four test lines still support it, so the status is unchanged.
LeaderCompleteness ==
    \A lh \in leaderHistory : \A ch \in commitHistory :
        ch.commitTerm < lh.term =>
          /\ ch.index <= Len(logs[lh.node])
          /\ logs[lh.node][ch.index] = ch.entry

\* REQ-EVIDENCE MessagesWellFormed
\* intent:   every message in the network has every field drawn from the model's bounded domains.
\* status:   model-internal
\* verified: update (c780d355)
\* note:     representation-only revision: the ghost gstamp field is checked to be a natural number.
\* review:   ok
MessagesWellFormed == \A m \in messages : MsgWellFormed(m)

\* REQ-EVIDENCE ReadDeliveryJustified
\* intent:   with the default safe read-only option, every read state delivered to an application, whether served by the leader itself or forwarded to a follower, is backed by acknowledgements from at least a quorum of servers.
\* status:   requirement
\* evidence: contract source/raft.go:167 "communicating with the quorum. It is the default and suggested option." -> safe read-only requests are confirmed by communicating with a quorum, and this is the default option
\* evidence: doc source/README.md:28 "leader checks with quorum and bypasses Raft log before processing read-only queries" -> a leader-served read is confirmed with a quorum before it is processed
\* evidence: doc source/README.md:29 "followers asks leader to get a safe read index before processing read-only queries" -> a follower-served read uses a read index the leader has made safe
\* evidence: contract source/node.go:156 "any linearizable read requests issued before the read request can be" -> a delivered read state must be safe to use for linearizable reads
\* evidence: impl source/raft.go:920 "if ackCount < r.quorum() {"
\* evidence: impl source/read_only.go:72 "return len(rs.acks) + 1"
\* evidence: impl source/raft.go:930 "r.send(pb.Message{To: req.From, Type: pb.MsgReadIndexResp, Index: rs.index, Entries: req.Entries})"
\* evidence: impl source/raft.go:1080 "r.readStates = append(r.readStates, ReadState{Index: m.Index, RequestCtx: m.Entries[0].Data})"
\* watch:    raft.go:ReadOnlyOption; raft.go:stepLeader; raft.go:stepFollower; raft.go:bcastHeartbeatWithCtx; raft.go:handleHeartbeat; raft.go:reset; read_only.go:addRequest; read_only.go:recvAck; read_only.go:advance
\* verified: update (c780d355)
\* update:   watch touched (read_only.go:advance). Kept unchanged (decision keep, spec/invariant-evidence.json K1). The count-only formulation does not bind acknowledgements to the request instance they confirm; the instance-bound strengthening is Update!UpdReadAckFresh. For forwarded reads the acks now come from the leader-side release history (repair R2) instead of the leader's live pending map.
\* note:     the lease-based option (raft.go:50-55, README.md:30-33) is documented as relying on clocks rather than a quorum, so the evidence covers the safe option only; TestReadOnlyOptionSafe (raft_test.go:1724) asserts read index and context but not the acknowledgement count, so it is not counted; the Raft thesis text is not in /work; history f1dae53 (message "Implement raft readonly request described in raft thesis 6.4") names the source of the algorithm but states no quorum rule, so it is not counted as evidence
\* review:   moved the provenance-only history f1dae53 line to the note because the commit message states no quorum rule; the contract and doc lines still support the intent, so the status is unchanged.
ReadDeliveryJustified ==
    \A k \in 1..Len(publishedReads) :
        Cardinality(publishedReads[k].acks) >= Quorum

\* REQ-EVIDENCE ReadyNoInvention
\* intent:   every read state delivered to an application has a read index no larger than the serving leader's log length, and its context fields are request contexts.
\* status:   mixed
\* evidence: comment source/read_only.go:49 "`index` is the commit index of the raft state machine when it received" -> the read index is the leader's commit index when the request arrived
\* evidence: comment source/log.go:32 "committed is the highest log position that is known to be in" -> a commit index names a position in the log
\* evidence: comment source/log.go:188 "never decrease commit" -> the commit index that bounds the read index never moves backward
\* evidence: test source/raft_test.go:1768 TestReadOnlyOptionSafe "readIndex = %d, want %d" -> the delivered read index equals the leader's commit index in the tested runs
\* evidence: impl source/raft.go:836 "r.readOnly.addRequest(r.raftLog.committed, m)"
\* evidence: impl source/raft.go:928 "r.readStates = append(r.readStates, ReadState{Index: rs.index, RequestCtx: req.Entries[0].Data})"
\* watch:    raft.go:stepLeader; raft.go:stepFollower; read_only.go:addRequest; read_only.go:advance; log.go:commitTo; node.go:newReady
\* verified: update (c780d355)
\* update:   watch touched (read_only.go:advance). Kept unchanged (decision keep, spec/invariant-evidence.json K2): the update changes which pending entries survive a release, not the produced read index or context fields.
\* clause index-bound: requirement — read_only.go:49 (read index is the commit index at arrival), log.go:32 and log.go:188 comments, TestReadOnlyOptionSafe assertion at raft_test.go:1768
\* clause ctx-domain: model-internal — membership of ctx and justificationCtx in the request-context set is a domain check
\* note:     searched read_only.go, raft.go, node.go and history f1dae53 for a statement bounding the read index and found only the addRequest parameter comment; node.go:157 ("The read state will have the same rctx attached.") is about equality with the requested context rather than domain membership, so it is not counted for the ctx-domain clause
\* review:   ok
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
