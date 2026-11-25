---- MODULE E3prefix ----
\* MC continuation from a validated trace state (diff-sync-uncommitted-log,
\* cursor l = 103: both learners left epoch 2 after NEWLEADER, their leaked
\* SyncThreads forced (1,2), their in-memory databases still end at (1,1)).
\* Behaviour is the complete reference: UpdFullNext = MCNext /\ GhostNext.
EXTENDS Update
PInit ==
/\ rollbackAuthorized = [s0 |-> FALSE, s1 |-> FALSE, s2 |-> FALSE]
/\ recovered = [ s0 |-> <<[id |-> 1, epoch |-> 1]>>,
  s1 |-> <<[id |-> 1, epoch |-> 1]>>,
  s2 |-> <<[id |-> 1, epoch |-> 1], [id |-> 2, epoch |-> 1]>> ]
/\ votes = [s0 |-> {}, s1 |-> {}, s2 |-> {}]
/\ leadersByEpoch = (0 :> {} @@ 1 :> {"s2"} @@ 2 :> {"s2"} @@ 3 :> {})
/\ syncMode = [s0 |-> "NONE", s1 |-> "NONE", s2 |-> "NONE"]
/\ commitCertified = ( 0 :> FALSE @@
  1 :> TRUE @@
  2 :> TRUE @@
  3 :> FALSE @@
  4 :> FALSE @@
  5 :> FALSE @@
  6 :> FALSE @@
  7 :> FALSE @@
  1000 :> FALSE )
/\ syncSource = [s0 |-> "Nil", s1 |-> "Nil", s2 |-> "Nil"]
/\ applied = [ s0 |-> <<[id |-> 1, epoch |-> 1]>>,
  s1 |-> <<[id |-> 1, epoch |-> 1]>>,
  s2 |-> <<[id |-> 1, epoch |-> 1], [id |-> 2, epoch |-> 1]>> ]
/\ durable = [ s0 |-> <<[id |-> 1, epoch |-> 1], [id |-> 2, epoch |-> 1]>>,
  s1 |-> <<[id |-> 1, epoch |-> 1], [id |-> 2, epoch |-> 1]>>,
  s2 |-> <<[id |-> 1, epoch |-> 1], [id |-> 2, epoch |-> 1]>> ]
/\ acked = ( 0 :> {} @@
  1 :> {} @@
  2 :> {} @@
  3 :> {} @@
  4 :> {} @@
  5 :> {} @@
  6 :> {} @@
  7 :> {} @@
  1000 :> {} )
/\ usedTxn = {1, 2}
/\ appended = [ s0 |-> <<[id |-> 1, epoch |-> 1], [id |-> 2, epoch |-> 1]>>,
  s1 |-> <<[id |-> 1, epoch |-> 1], [id |-> 2, epoch |-> 1]>>,
  s2 |-> <<[id |-> 1, epoch |-> 1], [id |-> 2, epoch |-> 1]>> ]
/\ acceptedEpoch = [s0 |-> 2, s1 |-> 2, s2 |-> 2]
/\ role = [s0 |-> "looking", s1 |-> "looking", s2 |-> "leading"]
/\ syncJustified = [s0 |-> FALSE, s1 |-> FALSE, s2 |-> FALSE]
/\ phase = [s0 |-> "election", s1 |-> "election", s2 |-> "broadcast"]
/\ snapshot = [s0 |-> <<>>, s1 |-> <<>>, s2 |-> <<>>]
/\ currentEpoch = [s0 |-> 2, s1 |-> 2, s2 |-> 2]
/\ queued = [ s0 |-> <<[id |-> 1, epoch |-> 1], [id |-> 2, epoch |-> 1]>>,
  s1 |-> <<[id |-> 1, epoch |-> 1], [id |-> 2, epoch |-> 1]>>,
  s2 |-> <<[id |-> 1, epoch |-> 1], [id |-> 2, epoch |-> 1]>> ]
/\ proposed = [ s0 |-> <<[id |-> 1, epoch |-> 1], [id |-> 2, epoch |-> 1]>>,
  s1 |-> <<[id |-> 1, epoch |-> 1], [id |-> 2, epoch |-> 1]>>,
  s2 |-> <<[id |-> 1, epoch |-> 1], [id |-> 2, epoch |-> 1]>> ]
/\ leaderSummaryEpoch = [s0 |-> 0, s1 |-> 0, s2 |-> 1]
/\ committed = [ s0 |-> <<[id |-> 1, epoch |-> 1]>>,
  s1 |-> <<[id |-> 1, epoch |-> 1]>>,
  s2 |-> <<[id |-> 1, epoch |-> 1], [id |-> 2, epoch |-> 1]>> ]
/\ newLeaderAcked = [s0 |-> FALSE, s1 |-> FALSE, s2 |-> FALSE]
/\ up = [s0 |-> TRUE, s1 |-> TRUE, s2 |-> TRUE]
/\ zkState = [s0 |-> "off", s1 |-> "off", s2 |-> "running"]
/\ messages = { [id |-> 1, epoch |-> 1, kind |-> "ack", from |-> "s0", to |-> "s2"],
  [id |-> 1, epoch |-> 1, kind |-> "ack", from |-> "s1", to |-> "s2"] }
/\ leaderOf = [s0 |-> "Nil", s1 |-> "Nil", s2 |-> "s2"]
/\ nlAcks = [s0 |-> {}, s1 |-> {}, s2 |-> {"s1", "s2"}]
/\ counters = [crash |-> 0, drop |-> 0, snapshot |-> 0]
/\ seen = {}
/\ everCommitted = {}
PSpec == PInit /\ [][UpdFullNext]_uvars

\* Concrete focused continuation: election/synchronization actions of the two
\* learners s0, s1 only; the stale epoch-2 leader s2 takes no further step
\* (e.g. it is partitioned).  Every step is an MCNext step (subset of the
\* reference behaviour); nothing is added.
L == {"s0", "s1"}
FocusNext ==
    /\ \/ \E s \in L : MCBeginElection(s)
       \/ \E v, c \in L : MCCastVote(v, c)
       \/ \E s \in L : MCWinElection(s)
       \/ \E s, l \in L : MCFollowLeader(s, l)
       \/ \E s \in L : MCAcceptEpoch(s)
       \/ \E l \in L : MCFinishDiscovery(l)
       \/ \E s, l \in L : MCEnterSyncPhase(s, l)
       \/ \E s, l \in L, mode \in SyncModes \ {"NONE"} : MCSelectSync(s, l, mode)
       \/ \E s \in L : MCCompleteSync(s)
       \/ \E s \in L : MCPersistCurrentEpoch(s)
       \/ \E s \in L : MCClearSyncMode(s)
       \/ \E s \in L : MCLogSyncProposal(s)
       \/ \E s \in L : MCAckNewLeader(s)
       \/ \E l, s \in L : MCCountNewLeaderAck(l, s)
       \/ \E l \in L : MCLeaderBroadcast(l)
    /\ GhostNext
FocusSpec == PInit /\ [][FocusNext]_uvars
====
