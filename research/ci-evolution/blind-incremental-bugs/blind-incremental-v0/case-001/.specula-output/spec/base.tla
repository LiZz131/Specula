------------------------------ MODULE base ------------------------------
\* Exact-old OpenRaft Engine / RaftCore abstraction for Specula V0.
\* Every transition below is tied to the immutable source locations noted
\* beside it.  Rust allocation, payload bytes and runtime choice are excluded.

EXTENDS Naturals, FiniteSets, Sequences, TLC

CONSTANT Nodes, Nil, MaxTerm, MaxLog

VARIABLES term, voteNode, voteCommitted, role, logLen, commitLen,
          candidate, grantSet, voters, selfVoter,
          ioAccepted, ioSubmitted, ioFlushed,
          ioAcceptedTerm, ioSubmittedTerm, ioFlushedTerm,
          matchLen, messages, alive

nodeVars == <<term, voteNode, voteCommitted, role, logLen, commitLen,
              candidate, grantSet, voters, selfVoter,
              ioAccepted, ioSubmitted, ioFlushed,
              ioAcceptedTerm, ioSubmittedTerm, ioFlushedTerm, alive>>
vars == <<nodeVars, matchLen, messages>>

Roles == {"Learner", "Follower", "Candidate", "Leader", "Shutdown"}

Msg(kind, src, dst, msgTerm, msgLog, granted) ==
    [kind |-> kind, src |-> src, dst |-> dst,
     term |-> msgTerm, logLen |-> msgLog, granted |-> granted]

MessageType ==
    [kind : {"VoteRequest", "VoteResponse", "AppendEntries"},
     src : Nodes, dst : Nodes, term : Nat, logLen : Nat,
     granted : BOOLEAN]

IOLeq(aTerm, aLen, bTerm, bLen) ==
    \/ aTerm < bTerm
    \/ /\ aTerm = bTerm
       /\ aLen <= bLen

IsQuorum(S) == Cardinality(S) * 2 > Cardinality(Nodes)
Symmetry == Permutations(Nodes)

TypeOK ==
    /\ term \in [Nodes -> Nat]
    /\ voteNode \in [Nodes -> Nodes \cup {Nil}]
    /\ voteCommitted \in [Nodes -> BOOLEAN]
    /\ role \in [Nodes -> Roles]
    /\ logLen \in [Nodes -> Nat]
    /\ commitLen \in [Nodes -> Nat]
    /\ candidate \in [Nodes -> BOOLEAN]
    /\ grantSet \in [Nodes -> SUBSET Nodes]
    /\ voters \in [Nodes -> Nat]
    /\ selfVoter \in [Nodes -> BOOLEAN]
    /\ ioAccepted \in [Nodes -> Nat]
    /\ ioSubmitted \in [Nodes -> Nat]
    /\ ioFlushed \in [Nodes -> Nat]
    /\ ioAcceptedTerm \in [Nodes -> Nat]
    /\ ioSubmittedTerm \in [Nodes -> Nat]
    /\ ioFlushedTerm \in [Nodes -> Nat]
    /\ matchLen \in [Nodes -> [Nodes -> Nat]]
    /\ messages \subseteq MessageType
    /\ alive \in [Nodes -> BOOLEAN]

IOOrdered ==
    \A n \in Nodes:
        /\ IOLeq(ioFlushedTerm[n], ioFlushed[n],
                 ioSubmittedTerm[n], ioSubmitted[n])
        /\ IOLeq(ioSubmittedTerm[n], ioSubmitted[n],
                 ioAcceptedTerm[n], ioAccepted[n])

CommittedWithinLog == \A n \in Nodes: commitLen[n] <= logLen[n]
LeaderHasCommittedVote ==
    \A n \in Nodes: role[n] = "Leader" => voteCommitted[n]
CandidateHasOwnVote ==
    \A n \in Nodes: role[n] = "Candidate" =>
        candidate[n] /\ voteNode[n] = n /\ ~voteCommitted[n]
MatchWithinLog ==
    \A i, j \in Nodes: matchLen[i][j] <= logLen[i]
ElectionSafety ==
    \A i, j \in Nodes:
        /\ role[i] = "Leader"
        /\ role[j] = "Leader"
        /\ term[i] = term[j]
        => i = j

Init ==
    /\ term = [n \in Nodes |-> 0]
    /\ voteNode = [n \in Nodes |-> Nil]
    /\ voteCommitted = [n \in Nodes |-> FALSE]
    /\ role = [n \in Nodes |-> "Learner"]
    /\ logLen = [n \in Nodes |-> 0]
    /\ commitLen = [n \in Nodes |-> 0]
    /\ candidate = [n \in Nodes |-> FALSE]
    /\ grantSet = [n \in Nodes |-> {}]
    /\ voters = [n \in Nodes |-> 0]
    /\ selfVoter = [n \in Nodes |-> FALSE]
    /\ ioAccepted = [n \in Nodes |-> 0]
    /\ ioSubmitted = [n \in Nodes |-> 0]
    /\ ioFlushed = [n \in Nodes |-> 0]
    /\ ioAcceptedTerm = [n \in Nodes |-> 0]
    /\ ioSubmittedTerm = [n \in Nodes |-> 0]
    /\ ioFlushedTerm = [n \in Nodes |-> 0]
    /\ matchLen = [i \in Nodes |-> [j \in Nodes |-> 0]]
    /\ messages = {}
    /\ alive = [n \in Nodes |-> TRUE]

\* engine_impl.rs:190-210: initialize is one deterministic Engine step;
\* it installs log 0, a term-0 committed leader identity, then immediately
\* calls elect(), leaving a term-1 candidate and three ordered commands.
EngineInitialize(n, voterCount) ==
    /\ alive[n]
    /\ term[n] = 0
    /\ logLen[n] = 0
    /\ voters[n] = 0
    /\ voterCount \in 1..Cardinality(Nodes)
    /\ term' = [term EXCEPT ![n] = 1]
    /\ voteNode' = [voteNode EXCEPT ![n] = n]
    /\ voteCommitted' = [voteCommitted EXCEPT ![n] = FALSE]
    /\ role' = [role EXCEPT ![n] = "Candidate"]
    /\ logLen' = [logLen EXCEPT ![n] = 1]
    /\ candidate' = [candidate EXCEPT ![n] = TRUE]
    /\ grantSet' = [grantSet EXCEPT ![n] = {}]
    /\ voters' = [voters EXCEPT ![n] = voterCount]
    /\ selfVoter' = [selfVoter EXCEPT ![n] = TRUE]
    /\ ioAcceptedTerm' = [ioAcceptedTerm EXCEPT ![n] = 1]
    /\ ioAccepted' = [ioAccepted EXCEPT ![n] = 0]
    /\ UNCHANGED <<commitLen, ioSubmitted, ioFlushed,
                    ioSubmittedTerm, ioFlushedTerm, matchLen, messages, alive>>

\* engine_impl.rs:213-233 and vote_handler/mod.rs:104-139: a timeout
\* creates a new non-committed self vote, accepts its vote IO and becomes a
\* candidate. SaveVote precedes SendVote in the Engine command queue.
EngineElect(n) ==
    /\ alive[n]
    /\ selfVoter[n]
    /\ term[n] < MaxTerm
    /\ term' = [term EXCEPT ![n] = @ + 1]
    /\ voteNode' = [voteNode EXCEPT ![n] = n]
    /\ voteCommitted' = [voteCommitted EXCEPT ![n] = FALSE]
    /\ role' = [role EXCEPT ![n] = "Candidate"]
    /\ candidate' = [candidate EXCEPT ![n] = TRUE]
    /\ grantSet' = [grantSet EXCEPT ![n] = {}]
    /\ ioAcceptedTerm' = [ioAcceptedTerm EXCEPT ![n] = term[n] + 1]
    /\ ioAccepted' = [ioAccepted EXCEPT ![n] = 0]
    /\ UNCHANGED <<logLen, commitLen, voters, selfVoter,
                    ioSubmitted, ioFlushed, ioSubmittedTerm, ioFlushedTerm,
                    matchLen, messages, alive>>

\* engine_impl.rs:340-403, 708-735: a matching granted response adds a
\* unique granter; a quorum commits the vote and appends the leader noop.
TraceHandleVoteResponse(n, target, granted) ==
    /\ alive[n]
    /\ candidate[n]
    /\ granted
    /\ target \in Nodes \ grantSet[n]
    /\ LET gs == grantSet[n] \cup {target}
           won == Cardinality(gs) * 2 > voters[n]
       IN /\ term' = term
          /\ voteNode' = voteNode
          /\ voteCommitted' = [voteCommitted EXCEPT ![n] = IF won THEN TRUE ELSE @]
          /\ role' = [role EXCEPT ![n] = IF won THEN "Leader" ELSE @]
          /\ logLen' = [logLen EXCEPT ![n] = IF won THEN @ + 1 ELSE @]
          /\ candidate' = [candidate EXCEPT ![n] = IF won THEN FALSE ELSE @]
          /\ grantSet' = [grantSet EXCEPT ![n] = IF won THEN {} ELSE gs]
          /\ ioAcceptedTerm' = [ioAcceptedTerm EXCEPT ![n] = IF won THEN term[n] ELSE @]
          /\ ioAccepted' = [ioAccepted EXCEPT ![n] = IF won THEN logLen[n] + 1 ELSE @]
    /\ UNCHANGED <<commitLen, voters, selfVoter,
                    ioSubmitted, ioFlushed, ioSubmittedTerm, ioFlushedTerm,
                    matchLen, messages, alive>>

\* engine_impl.rs:443-457 and following_handler/mod.rs:63-173: after the
\* vote guard and consecutive-prefix check, conflicting suffixes are
\* truncated, the incoming suffix is accepted, and membership may change role.
TraceEngineAppendEntries(n, incomingTerm, incomingNode, entryCount,
                         prevLen, postVoterCount, postSelfVoter) ==
    /\ alive[n]
    /\ incomingNode \in Nodes
    /\ incomingTerm >= term[n]
    /\ prevLen <= logLen[n]
    /\ entryCount > 0
    /\ term' = [term EXCEPT ![n] = incomingTerm]
    /\ voteNode' = [voteNode EXCEPT ![n] = incomingNode]
    /\ voteCommitted' = [voteCommitted EXCEPT ![n] = TRUE]
    /\ role' = [role EXCEPT ![n] = IF postSelfVoter THEN "Follower" ELSE "Learner"]
    /\ logLen' = [logLen EXCEPT ![n] = prevLen + entryCount]
    /\ candidate' = [candidate EXCEPT ![n] = FALSE]
    /\ grantSet' = [grantSet EXCEPT ![n] = {}]
    /\ voters' = [voters EXCEPT ![n] = postVoterCount]
    /\ selfVoter' = [selfVoter EXCEPT ![n] = postSelfVoter]
    /\ ioAcceptedTerm' = [ioAcceptedTerm EXCEPT ![n] = incomingTerm]
    /\ ioAccepted' = [ioAccepted EXCEPT ![n] = prevLen + entryCount]
    /\ UNCHANGED <<commitLen, ioSubmitted, ioFlushed,
                    ioSubmittedTerm, ioFlushedTerm, matchLen, messages, alive>>

\* io_progress.rs:86-145: accept and submit are monotonic stages.
IOAccept(n, x) ==
    /\ x >= ioAccepted[n]
    /\ ioAccepted' = [ioAccepted EXCEPT ![n] = x]
    /\ UNCHANGED <<term, voteNode, voteCommitted, role, logLen, commitLen,
                    candidate, grantSet, voters, selfVoter,
                    ioSubmitted, ioFlushed, ioAcceptedTerm,
                    ioSubmittedTerm, ioFlushedTerm, matchLen, messages, alive>>

IOSubmit(n, x) ==
    /\ x >= ioSubmitted[n]
    /\ x <= ioAccepted[n]
    /\ ioSubmitted' = [ioSubmitted EXCEPT ![n] = x]
    /\ UNCHANGED <<term, voteNode, voteCommitted, role, logLen, commitLen,
                    candidate, grantSet, voters, selfVoter,
                    ioAccepted, ioFlushed, ioAcceptedTerm,
                    ioSubmittedTerm, ioFlushedTerm, matchLen, messages, alive>>

\* io_progress.rs:127-190: completion tolerates delayed/out-of-order reports
\* by changing the flushed cursor only when the reported identity is newer.
IOFlush(n, x) ==
    /\ x >= ioFlushed[n]
    /\ x <= ioSubmitted[n]
    /\ ioFlushed' = [ioFlushed EXCEPT ![n] = x]
    /\ UNCHANGED <<term, voteNode, voteCommitted, role, logLen, commitLen,
                    candidate, grantSet, voters, selfVoter,
                    ioAccepted, ioSubmitted, ioAcceptedTerm,
                    ioSubmittedTerm, ioFlushedTerm, matchLen, messages, alive>>

\* raft_core.rs:1812-1872: runtime submission advances submitted before the
\* append callback can run. The identity is copied, not reconstructed.
SubmitAccepted(n) ==
    /\ alive[n]
    /\ ~(/\ ioSubmittedTerm[n] = ioAcceptedTerm[n]
          /\ ioSubmitted[n] = ioAccepted[n])
    /\ ioSubmittedTerm' = [ioSubmittedTerm EXCEPT ![n] = ioAcceptedTerm[n]]
    /\ ioSubmitted' = [ioSubmitted EXCEPT ![n] = ioAccepted[n]]
    /\ UNCHANGED <<term, voteNode, voteCommitted, role, logLen, commitLen,
                    candidate, grantSet, voters, selfVoter,
                    ioAccepted, ioFlushed, ioAcceptedTerm, ioFlushedTerm,
                    matchLen, messages, alive>>

\* raft_core.rs:1497-1514 and storage/callback.rs:79-111: only a delivered
\* successful LocalIO notification advances the flushed stage.
FlushSubmitted(n) ==
    /\ alive[n]
    /\ ~(/\ ioFlushedTerm[n] = ioSubmittedTerm[n]
          /\ ioFlushed[n] = ioSubmitted[n])
    /\ ioFlushedTerm' = [ioFlushedTerm EXCEPT ![n] = ioSubmittedTerm[n]]
    /\ ioFlushed' = [ioFlushed EXCEPT ![n] = ioSubmitted[n]]
    /\ UNCHANGED <<term, voteNode, voteCommitted, role, logLen, commitLen,
                    candidate, grantSet, voters, selfVoter,
                    ioAccepted, ioSubmitted, ioAcceptedTerm, ioSubmittedTerm,
                    matchLen, messages, alive>>

\* raft_core.rs:1864-1887: after a pending vote is durably saved, RaftCore
\* queues a successful local VoteResponse. The notification event then counts
\* this node in the candidate's quorum progress through handle_vote_resp().
DeliverLocalVoteResponse(n) ==
    /\ alive[n]
    /\ candidate[n]
    /\ ioFlushedTerm[n] = term[n]
    /\ ioFlushed[n] = 0
    /\ n \notin grantSet[n]
    /\ grantSet' = [grantSet EXCEPT ![n] = @ \cup {n}]
    /\ UNCHANGED <<term, voteNode, voteCommitted, role, logLen, commitLen,
                    candidate, voters, selfVoter, ioAccepted, ioSubmitted,
                    ioFlushed, ioAcceptedTerm, ioSubmittedTerm, ioFlushedTerm,
                    matchLen, messages, alive>>

\* engine_impl.rs:213-233 plus raft_core.rs:1151-1220: network requests are
\* emitted only after the saved-vote command completes; the set represents
\* arbitrary delay/reorder without inventing delivery guarantees.
SendVoteRequest(c, v) ==
    /\ c /= v
    /\ alive[c]
    /\ candidate[c]
    /\ ioSubmittedTerm[c] = term[c]
    /\ LET m == Msg("VoteRequest", c, v, term[c], logLen[c], FALSE)
       IN /\ m \notin messages
          /\ messages' = messages \cup {m}
    /\ UNCHANGED <<nodeVars, matchLen>>

\* engine_impl.rs:286-337: last-log is checked before vote; a grant accepts
\* the incoming non-committed vote. This delivery also creates a delayed reply.
DeliverVoteRequest(m) ==
    /\ m \in messages
    /\ m.kind = "VoteRequest"
    /\ LET canGrant ==
              /\ alive[m.dst]
              /\ m.term >= term[m.dst]
              /\ m.logLen >= logLen[m.dst]
              /\ (m.term > term[m.dst] \/ voteNode[m.dst] \in {Nil, m.src})
           resp == Msg("VoteResponse", m.dst, m.src, m.term, logLen[m.dst], canGrant)
       IN /\ term' = [term EXCEPT ![m.dst] = IF canGrant THEN m.term ELSE @]
          /\ voteNode' = [voteNode EXCEPT ![m.dst] = IF canGrant THEN m.src ELSE @]
          /\ voteCommitted' = [voteCommitted EXCEPT ![m.dst] = IF canGrant THEN FALSE ELSE @]
          /\ role' = [role EXCEPT ![m.dst] = IF canGrant THEN
                           (IF selfVoter[m.dst] THEN "Follower" ELSE "Learner") ELSE @]
          /\ candidate' = [candidate EXCEPT ![m.dst] = IF canGrant THEN FALSE ELSE @]
          /\ grantSet' = [grantSet EXCEPT ![m.dst] = IF canGrant THEN {} ELSE @]
          /\ ioAcceptedTerm' = [ioAcceptedTerm EXCEPT ![m.dst] = IF canGrant THEN m.term ELSE @]
          /\ ioAccepted' = [ioAccepted EXCEPT ![m.dst] = IF canGrant THEN 0 ELSE @]
          /\ messages' = (messages \ {m}) \cup {resp}
    /\ UNCHANGED <<logLen, commitLen, voters, selfVoter,
                    ioSubmitted, ioFlushed, ioSubmittedTerm, ioFlushedTerm,
                    matchLen, alive>>

\* engine_impl.rs:340-363: stale/mismatching responses are ignored; matching
\* grants add the responding node once.
DeliverVoteResponse(m) ==
    /\ m \in messages
    /\ m.kind = "VoteResponse"
    /\ messages' = messages \ {m}
    /\ grantSet' = [grantSet EXCEPT ![m.dst] =
           IF alive[m.dst] /\ candidate[m.dst] /\ m.granted
              /\ m.term = term[m.dst] /\ voteNode[m.dst] = m.dst
           THEN @ \cup {m.src} ELSE @]
    /\ UNCHANGED <<term, voteNode, voteCommitted, role, logLen, commitLen,
                    candidate, voters, selfVoter, ioAccepted, ioSubmitted,
                    ioFlushed, ioAcceptedTerm, ioSubmittedTerm, ioFlushedTerm,
                    matchLen, alive>>

BecomeLeader(n) ==
    /\ alive[n]
    /\ candidate[n]
    /\ IsQuorum(grantSet[n])
    /\ logLen[n] < MaxLog
    /\ voteCommitted' = [voteCommitted EXCEPT ![n] = TRUE]
    /\ role' = [role EXCEPT ![n] = "Leader"]
    /\ logLen' = [logLen EXCEPT ![n] = @ + 1]
    /\ candidate' = [candidate EXCEPT ![n] = FALSE]
    /\ grantSet' = [grantSet EXCEPT ![n] = {}]
    /\ ioAcceptedTerm' = [ioAcceptedTerm EXCEPT ![n] = term[n]]
    /\ ioAccepted' = [ioAccepted EXCEPT ![n] = logLen[n] + 1]
    /\ matchLen' = [matchLen EXCEPT ![n][n] = logLen[n] + 1]
    /\ UNCHANGED <<term, voteNode, commitLen, voters, selfVoter,
                    ioSubmitted, ioFlushed, ioSubmittedTerm, ioFlushedTerm,
                    messages, alive>>

\* leader_handler/mod.rs:53-100: a leader assigns current-leader log IDs,
\* accepts the resulting LogIOId, then initiates replication.
LeaderAppend(n) ==
    /\ alive[n]
    /\ role[n] = "Leader"
    /\ logLen[n] < MaxLog
    /\ logLen' = [logLen EXCEPT ![n] = @ + 1]
    /\ ioAcceptedTerm' = [ioAcceptedTerm EXCEPT ![n] = term[n]]
    /\ ioAccepted' = [ioAccepted EXCEPT ![n] = logLen[n] + 1]
    /\ matchLen' = [matchLen EXCEPT ![n][n] = logLen[n] + 1]
    /\ UNCHANGED <<term, voteNode, voteCommitted, role, commitLen,
                    candidate, grantSet, voters, selfVoter,
                    ioSubmitted, ioFlushed, ioSubmittedTerm, ioFlushedTerm,
                    messages, alive>>

SendAppendEntries(l, f) ==
    /\ l /= f
    /\ alive[l]
    /\ role[l] = "Leader"
    /\ LET m == Msg("AppendEntries", l, f, term[l], logLen[l], TRUE)
       IN /\ m \notin messages
          /\ messages' = messages \cup {m}
    /\ UNCHANGED <<nodeVars, matchLen>>

\* engine_impl.rs:405-457 and following_handler/mod.rs:63-173.
DeliverAppendEntries(m) ==
    /\ m \in messages
    /\ m.kind = "AppendEntries"
    /\ alive[m.dst]
    /\ m.term >= term[m.dst]
    /\ term' = [term EXCEPT ![m.dst] = m.term]
    /\ voteNode' = [voteNode EXCEPT ![m.dst] = m.src]
    /\ voteCommitted' = [voteCommitted EXCEPT ![m.dst] = TRUE]
    /\ role' = [role EXCEPT ![m.dst] = IF selfVoter[m.dst] THEN "Follower" ELSE "Learner"]
    /\ logLen' = [logLen EXCEPT ![m.dst] = m.logLen]
    /\ candidate' = [candidate EXCEPT ![m.dst] = FALSE]
    /\ grantSet' = [grantSet EXCEPT ![m.dst] = {}]
    /\ ioAcceptedTerm' = [ioAcceptedTerm EXCEPT ![m.dst] = m.term]
    /\ ioAccepted' = [ioAccepted EXCEPT ![m.dst] = m.logLen]
    /\ matchLen' = [matchLen EXCEPT ![m.src][m.dst] = m.logLen]
    /\ messages' = messages \ {m}
    /\ UNCHANGED <<commitLen, voters, selfVoter, ioSubmitted, ioFlushed,
                    ioSubmittedTerm, ioFlushedTerm, alive>>

\* replication_handler/mod.rs:139-181: only a quorum-accepted current-term
\* position advances local committed/application acceptance.
AdvanceCommit(n, k) ==
    /\ alive[n]
    /\ role[n] = "Leader"
    /\ k \in (commitLen[n] + 1)..logLen[n]
    /\ IsQuorum({j \in Nodes: matchLen[n][j] >= k})
    /\ commitLen' = [commitLen EXCEPT ![n] = k]
    /\ UNCHANGED <<term, voteNode, voteCommitted, role, logLen,
                    candidate, grantSet, voters, selfVoter,
                    ioAccepted, ioSubmitted, ioFlushed,
                    ioAcceptedTerm, ioSubmittedTerm, ioFlushedTerm,
                    matchLen, messages, alive>>

\* raft_core.rs:242-495 and raft/mod.rs:1337-1349 expose stop/restart only
\* between Engine/runtime steps. No storage-internal ordering is invented.
Crash(n) ==
    /\ alive[n]
    /\ alive' = [alive EXCEPT ![n] = FALSE]
    /\ role' = [role EXCEPT ![n] = "Shutdown"]
    /\ candidate' = [candidate EXCEPT ![n] = FALSE]
    /\ grantSet' = [grantSet EXCEPT ![n] = {}]
    /\ UNCHANGED <<term, voteNode, voteCommitted, logLen, commitLen,
                    voters, selfVoter, ioAccepted, ioSubmitted, ioFlushed,
                    ioAcceptedTerm, ioSubmittedTerm, ioFlushedTerm,
                    matchLen, messages>>

Restart(n) ==
    /\ ~alive[n]
    /\ alive' = [alive EXCEPT ![n] = TRUE]
    /\ role' = [role EXCEPT ![n] = IF selfVoter[n] THEN "Follower" ELSE "Learner"]
    /\ UNCHANGED <<term, voteNode, voteCommitted, logLen, commitLen,
                    candidate, grantSet, voters, selfVoter,
                    ioAccepted, ioSubmitted, ioFlushed,
                    ioAcceptedTerm, ioSubmittedTerm, ioFlushedTerm,
                    matchLen, messages>>

LoseMessage(m) ==
    /\ m \in messages
    /\ messages' = messages \ {m}
    /\ UNCHANGED <<nodeVars, matchLen>>

\* Standalone base configuration: a small, finite reference behavior.
Next ==
    \/ \E n \in Nodes: EngineInitialize(n, Cardinality(Nodes))
    \/ \E n \in Nodes: EngineElect(n)
    \/ \E n \in Nodes: SubmitAccepted(n)
    \/ \E n \in Nodes: FlushSubmitted(n)
    \/ \E n \in Nodes: DeliverLocalVoteResponse(n)

Spec == Init /\ [][Next]_vars

=============================================================================
