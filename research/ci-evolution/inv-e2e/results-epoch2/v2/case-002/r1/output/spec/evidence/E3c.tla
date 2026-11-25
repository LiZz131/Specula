---- MODULE E3c ----
EXTENDS Update
EInit ==
/\ rollbackAuthorized = [s0 |-> FALSE, s1 |-> FALSE, s2 |-> FALSE]
/\ recovered = [ s0 |-> <<[id |-> 1, epoch |-> 1]>>,
  s1 |-> <<[id |-> 1, epoch |-> 1]>>,
  s2 |-> <<[id |-> 1, epoch |-> 1], [id |-> 2, epoch |-> 1]>> ]
/\ votes = [s0 |-> {"s0", "s1"}, s1 |-> {}, s2 |-> {}]
/\ leadersByEpoch = (0 :> {} @@ 1 :> {"s2"} @@ 2 :> {"s2"} @@ 3 :> {"s0"})
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
/\ syncSource = [s0 |-> "Nil", s1 |-> "s0", s2 |-> "Nil"]
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
/\ everCommitted = { [ent |-> [id |-> 1, epoch |-> 1], ep |-> 2],
  [ent |-> [id |-> 1, epoch |-> 1], ep |-> 3],
  [ent |-> [id |-> 2, epoch |-> 1], ep |-> 2] }
/\ appended = [ s0 |-> <<[id |-> 1, epoch |-> 1], [id |-> 2, epoch |-> 1]>>,
  s1 |-> <<[id |-> 1, epoch |-> 1], [id |-> 2, epoch |-> 1]>>,
  s2 |-> <<[id |-> 1, epoch |-> 1], [id |-> 2, epoch |-> 1]>> ]
/\ acceptedEpoch = [s0 |-> 3, s1 |-> 3, s2 |-> 2]
/\ role = [s0 |-> "leading", s1 |-> "following", s2 |-> "leading"]
/\ seen = {"election", "sync", "broadcast", "DIFF", "leader", "nlack"}
/\ syncJustified = [s0 |-> FALSE, s1 |-> TRUE, s2 |-> FALSE]
/\ phase = [s0 |-> "broadcast", s1 |-> "sync", s2 |-> "broadcast"]
/\ snapshot = [s0 |-> <<>>, s1 |-> <<>>, s2 |-> <<>>]
/\ currentEpoch = [s0 |-> 3, s1 |-> 3, s2 |-> 2]
/\ queued = [ s0 |-> <<[id |-> 1, epoch |-> 1], [id |-> 2, epoch |-> 1]>>,
  s1 |-> <<[id |-> 1, epoch |-> 1], [id |-> 2, epoch |-> 1]>>,
  s2 |-> <<[id |-> 1, epoch |-> 1], [id |-> 2, epoch |-> 1]>> ]
/\ proposed = [ s0 |-> <<[id |-> 1, epoch |-> 1], [id |-> 2, epoch |-> 1]>>,
  s1 |-> <<[id |-> 1, epoch |-> 1], [id |-> 2, epoch |-> 1]>>,
  s2 |-> <<[id |-> 1, epoch |-> 1], [id |-> 2, epoch |-> 1]>> ]
/\ leaderSummaryEpoch = [s0 |-> 2, s1 |-> 0, s2 |-> 1]
/\ committed = [s0 |-> <<[id |-> 1, epoch |-> 1], [id |-> 2, epoch |-> 1]>>, s1 |-> <<[id |-> 1, epoch |-> 1]>>, s2 |-> <<[id |-> 1, epoch |-> 1], [id |-> 2, epoch |-> 1]>>]
/\ counters = [snapshot |-> 0, crash |-> 0, drop |-> 0]
/\ newLeaderAcked = [s0 |-> FALSE, s1 |-> TRUE, s2 |-> FALSE]
/\ up = [s0 |-> TRUE, s1 |-> TRUE, s2 |-> TRUE]
/\ zkState = [s0 |-> "running", s1 |-> "initial", s2 |-> "running"]
/\ messages = { [id |-> 1, epoch |-> 1, kind |-> "ack", from |-> "s0", to |-> "s2"],
  [id |-> 1, epoch |-> 1, kind |-> "ack", from |-> "s1", to |-> "s2"] }
/\ leaderOf = [s0 |-> "s0", s1 |-> "s0", s2 |-> "s2"]
/\ nlAcks = [s0 |-> {"s0", "s1"}, s1 |-> {}, s2 |-> {"s1", "s2"}]
ESpec == EInit /\ [][UNCHANGED uvars]_uvars
Report == PrintT(<<"E3c", "new UpdLeaderCompleteness", UpdLeaderCompleteness, "old", "not checked (no V0 counterpart)">>)
====
