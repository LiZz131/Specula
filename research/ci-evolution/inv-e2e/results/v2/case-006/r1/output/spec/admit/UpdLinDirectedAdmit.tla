---- MODULE UpdLinDirectedAdmit ----
EXTENDS Update
CONSTANTS s1, s2, s3, ctx1, ctx2, v1
VARIABLE pc
D == INSTANCE UpdLinDirectedCex
S == D!CounterExample.state
Path == [k \in 1..Cardinality(S) |-> (CHOOSE p \in S : p[1] = k)[2]]
AInit ==
    /\ pc = 1
    /\ term = Path[1].term
    /\ vote = Path[1].vote
    /\ role = Path[1].role
    /\ leader = Path[1].leader
    /\ logs = Path[1].logs
    /\ commitIndex = Path[1].commitIndex
    /\ appliedIndex = Path[1].appliedIndex
    /\ durableTerm = Path[1].durableTerm
    /\ durableVote = Path[1].durableVote
    /\ durableLogs = Path[1].durableLogs
    /\ durableCommit = Path[1].durableCommit
    /\ matchIndex = Path[1].matchIndex
    /\ nextIndex = Path[1].nextIndex
    /\ votesGranted = Path[1].votesGranted
    /\ recentActive = Path[1].recentActive
    /\ messages = Path[1].messages
    /\ pendingReads = Path[1].pendingReads
    /\ readQueue = Path[1].readQueue
    /\ producedReads = Path[1].producedReads
    /\ publishedReads = Path[1].publishedReads
    /\ readyOutstanding = Path[1].readyOutstanding
    /\ alive = Path[1].alive
    /\ leaderHistory = Path[1].leaderHistory
    /\ commitHistory = Path[1].commitHistory
    /\ scenarioSeen = Path[1].scenarioSeen
    /\ readStamp = Path[1].readStamp
    /\ servedReads = Path[1].servedReads
    /\ faultCounters = Path[1].faultCounters
ANext ==
    /\ pc < Len(Path)
    /\ MCNext
    /\ term' = Path[pc + 1].term
    /\ vote' = Path[pc + 1].vote
    /\ role' = Path[pc + 1].role
    /\ leader' = Path[pc + 1].leader
    /\ logs' = Path[pc + 1].logs
    /\ commitIndex' = Path[pc + 1].commitIndex
    /\ appliedIndex' = Path[pc + 1].appliedIndex
    /\ durableTerm' = Path[pc + 1].durableTerm
    /\ durableVote' = Path[pc + 1].durableVote
    /\ durableLogs' = Path[pc + 1].durableLogs
    /\ durableCommit' = Path[pc + 1].durableCommit
    /\ matchIndex' = Path[pc + 1].matchIndex
    /\ nextIndex' = Path[pc + 1].nextIndex
    /\ votesGranted' = Path[pc + 1].votesGranted
    /\ recentActive' = Path[pc + 1].recentActive
    /\ messages' = Path[pc + 1].messages
    /\ pendingReads' = Path[pc + 1].pendingReads
    /\ readQueue' = Path[pc + 1].readQueue
    /\ producedReads' = Path[pc + 1].producedReads
    /\ publishedReads' = Path[pc + 1].publishedReads
    /\ readyOutstanding' = Path[pc + 1].readyOutstanding
    /\ alive' = Path[pc + 1].alive
    /\ leaderHistory' = Path[pc + 1].leaderHistory
    /\ commitHistory' = Path[pc + 1].commitHistory
    /\ scenarioSeen' = Path[pc + 1].scenarioSeen
    /\ readStamp' = Path[pc + 1].readStamp
    /\ servedReads' = Path[pc + 1].servedReads
    /\ faultCounters' = Path[pc + 1].faultCounters
    /\ pc' = pc + 1
ASpec == AInit /\ [][ANext]_<<mcVars, pc>>
AdmitNotDone == pc < Len(Path)
====
