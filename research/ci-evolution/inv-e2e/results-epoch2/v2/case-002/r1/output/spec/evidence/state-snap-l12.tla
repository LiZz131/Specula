/\ rollbackAuthorized = [s0 |-> FALSE, s1 |-> FALSE, s2 |-> FALSE]
/\ recovered = [ s0 |-> <<[id |-> 1, epoch |-> 1]>>,
  s1 |-> <<[id |-> 1, epoch |-> 1]>>,
  s2 |-> <<[id |-> 1, epoch |-> 1]>> ]
/\ votes = [s0 |-> {}, s1 |-> {"s0", "s1", "s2"}, s2 |-> {}]
/\ leadersByEpoch = (0 :> {} @@ 1 :> {"s1"} @@ 2 :> {} @@ 3 :> {})
/\ syncMode = [s0 |-> "NONE", s1 |-> "NONE", s2 |-> "NONE"]
/\ commitCertified = ( 0 :> FALSE @@
  1 :> TRUE @@
  2 :> FALSE @@
  3 :> FALSE @@
  4 :> FALSE @@
  5 :> FALSE @@
  6 :> FALSE @@
  7 :> FALSE @@
  1000 :> FALSE )
/\ syncSource = [s0 |-> "s1", s1 |-> "Nil", s2 |-> "Nil"]
/\ applied = [ s0 |-> <<[id |-> 1, epoch |-> 1]>>,
  s1 |-> <<[id |-> 1, epoch |-> 1]>>,
  s2 |-> <<[id |-> 1, epoch |-> 1]>> ]
/\ durable = [ s0 |-> <<[id |-> 1, epoch |-> 1]>>,
  s1 |-> <<[id |-> 1, epoch |-> 1]>>,
  s2 |-> <<[id |-> 1, epoch |-> 1]>> ]
/\ acked = ( 0 :> {} @@
  1 :> {"s0", "s1", "s2"} @@
  2 :> {} @@
  3 :> {} @@
  4 :> {} @@
  5 :> {} @@
  6 :> {} @@
  7 :> {} @@
  1000 :> {} )
/\ usedTxn = {1}
/\ appended = [ s0 |-> <<[id |-> 1, epoch |-> 1]>>,
  s1 |-> <<[id |-> 1, epoch |-> 1]>>,
  s2 |-> <<[id |-> 1, epoch |-> 1]>> ]
/\ acceptedEpoch = [s0 |-> 1, s1 |-> 1, s2 |-> 1]
/\ role = [s0 |-> "following", s1 |-> "leading", s2 |-> "following"]
/\ syncJustified = [s0 |-> TRUE, s1 |-> TRUE, s2 |-> TRUE]
/\ phase = [s0 |-> "sync", s1 |-> "broadcast", s2 |-> "broadcast"]
/\ snapshot = [ s0 |-> <<[id |-> 1, epoch |-> 1]>>,
  s1 |-> <<[id |-> 1, epoch |-> 1]>>,
  s2 |-> <<[id |-> 1, epoch |-> 1]>> ]
/\ currentEpoch = [s0 |-> 1, s1 |-> 1, s2 |-> 1]
/\ queued = [ s0 |-> <<[id |-> 1, epoch |-> 1]>>,
  s1 |-> <<[id |-> 1, epoch |-> 1]>>,
  s2 |-> <<[id |-> 1, epoch |-> 1]>> ]
/\ proposed = [ s0 |-> <<[id |-> 1, epoch |-> 1]>>,
  s1 |-> <<[id |-> 1, epoch |-> 1]>>,
  s2 |-> <<[id |-> 1, epoch |-> 1]>> ]
/\ leaderSummaryEpoch = [s0 |-> 0, s1 |-> 0, s2 |-> 0]
/\ committed = [ s0 |-> <<[id |-> 1, epoch |-> 1]>>,
  s1 |-> <<[id |-> 1, epoch |-> 1]>>,
  s2 |-> <<[id |-> 1, epoch |-> 1]>> ]
/\ newLeaderAcked = [s0 |-> TRUE, s1 |-> FALSE, s2 |-> FALSE]
/\ up = [s0 |-> TRUE, s1 |-> TRUE, s2 |-> TRUE]
/\ zkState = [s0 |-> "initial", s1 |-> "running", s2 |-> "running"]
/\ messages = {}
/\ leaderOf = [s0 |-> "s1", s1 |-> "s1", s2 |-> "s1"]
/\ nlAcks = [s0 |-> {}, s1 |-> {}, s2 |-> {}]
