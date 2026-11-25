/\ rollbackAuthorized = (s1 :> FALSE @@ s2 :> FALSE @@ s3 :> FALSE)
/\ recovered = (s1 :> <<[id |-> t1, epoch |-> 1]>> @@ s2 :> <<>> @@ s3 :> <<>>)
/\ votes = (s1 :> {s1, s2} @@ s2 :> {s2} @@ s3 :> {})
/\ leadersByEpoch = (0 :> {} @@ 1 :> {s1} @@ 2 :> {s1} @@ 3 :> {})
/\ syncMode = (s1 :> "NONE" @@ s2 :> "NONE" @@ s3 :> "NONE")
/\ commitCertified = (t1 :> TRUE)
/\ syncSource = (s1 :> Nil @@ s2 :> s1 @@ s3 :> Nil)
/\ applied = (s1 :> <<[id |-> t1, epoch |-> 1]>> @@ s2 :> <<>> @@ s3 :> <<>>)
/\ durable = (s1 :> <<[id |-> t1, epoch |-> 1]>> @@ s2 :> <<>> @@ s3 :> <<>>)
/\ acked = (t1 :> {})
/\ usedTxn = {t1}
/\ everCommitted = {[ent |-> [id |-> t1, epoch |-> 1], ep |-> 2]}
/\ appended = (s1 :> <<[id |-> t1, epoch |-> 1]>> @@ s2 :> <<>> @@ s3 :> <<>>)
/\ acceptedEpoch = (s1 :> 2 @@ s2 :> 2 @@ s3 :> 0)
/\ role = (s1 :> "leading" @@ s2 :> "following" @@ s3 :> "looking")
/\ seen = { "election",
  "sync",
  "broadcast",
  "DIFF",
  "leader",
  "diffpayload",
  "synclog",
  "nlack",
  "nlackBeforeDurable",
  "mutation" }
/\ syncJustified = (s1 :> FALSE @@ s2 :> TRUE @@ s3 :> FALSE)
/\ phase = (s1 :> "broadcast" @@ s2 :> "sync" @@ s3 :> "election")
/\ snapshot = (s1 :> <<>> @@ s2 :> <<>> @@ s3 :> <<>>)
/\ currentEpoch = (s1 :> 2 @@ s2 :> 2 @@ s3 :> 0)
/\ queued = ( s1 :> <<[id |-> t1, epoch |-> 1]>> @@
  s2 :> <<[id |-> t1, epoch |-> 1]>> @@
  s3 :> <<>> )
/\ proposed = ( s1 :> <<[id |-> t1, epoch |-> 1]>> @@
  s2 :> <<[id |-> t1, epoch |-> 1]>> @@
  s3 :> <<>> )
/\ leaderSummaryEpoch = (s1 :> 1 @@ s2 :> 0 @@ s3 :> 0)
/\ committed = (s1 :> <<[id |-> t1, epoch |-> 1]>> @@ s2 :> <<>> @@ s3 :> <<>>)
/\ counters = [snapshot |-> 0, crash |-> 0, drop |-> 0]
/\ newLeaderAcked = (s1 :> FALSE @@ s2 :> TRUE @@ s3 :> FALSE)
/\ up = (s1 :> TRUE @@ s2 :> TRUE @@ s3 :> TRUE)
/\ zkState = (s1 :> "running" @@ s2 :> "initial" @@ s3 :> "off")
/\ messages = { [id |-> t1, epoch |-> 1, kind |-> "proposal", from |-> s1, to |-> s2],
  [id |-> t1, epoch |-> 1, kind |-> "proposal", from |-> s1, to |-> s3] }
/\ leaderOf = (s1 :> s1 @@ s2 :> s1 @@ s3 :> Nil)
/\ nlAcks = (s1 :> {s1, s2} @@ s2 :> {} @@ s3 :> {})
