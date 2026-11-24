---- MODULE CensusProbes ----
EXTENDS MC

\* U5a: "hands every buffered proposal to FollowerZooKeeperServer.logRequest (L:752-757) and immediately
\* writes the NEWLEADER ACK ... logRequest only enqueues ... append and fsync happen later" (output/modeling-brief.md:234-238)
SC_U5a == \E s \in Server : nlAckSent[s] /\ Len(queued[s]) > Len(durable[s])

\* U5b: "The leader counts the ACK toward its NEWLEADER quorum ... and then serves its whole loaded history"
\* while the acknowledging learner has only queued the records (output/modeling-brief.md:238-240;
\* Q5 "Can a leader activate on NEWLEADER ACKs whose DIFF records are queued but not yet fsynced", :208)
SC_U5b == \E l, s \in Server :
            /\ ActiveLeader(l) /\ s /= l /\ s \in nlAcks[l] /\ nlAckSent[s]
            /\ ~IsPrefix(committed[l], Persisted(s))

\* U5c: "A crash in that window loses them, and the restarted learner keeps the new current epoch"
\* (output/analysis-report.md:122-124; Q5 "... and lose them after a learner crash", modeling-brief.md:208)
SC_U5c == \E l, s \in Server :
            /\ s /= l /\ ActiveLeader(l)
            /\ counters.crash > 0 /\ ~up[s]
            /\ currentEpoch[s] = currentEpoch[l]
            /\ ~IsPrefix(committed[l], Persisted(s))

\* U6a: "after startupWithoutServing the learner server is INITIAL. If the learner fails before UPTODATE"
\* (output/modeling-brief.md:259-260) -- the window: INITIAL learner that ACKed NEWLEADER with logged
\* records not in its data tree.
SC_U6a == \E s \in Server : up[s] /\ zkState[s] = "INITIAL" /\ nlAckSent[s]
                            /\ \E e \in Range(queued[s]) : e \notin Range(applied[s])

\* U6b: "no processor shutdown, no fastForwardDataBase ... the in-memory data tree (the FLE vote zxid ...)
\* does not contain them" (output/modeling-brief.md:262-266) -- a failed learner back in election whose
\* logged records are missing from its data tree.
SC_U6b == \E s \in Server : up[s] /\ role[s] = "looking" /\ phase[s] = "election"
                            /\ \E e \in Range(queued[s]) : e \notin Range(applied[s])

\* U6c: Q6 "vote/lead with a data tree that omits the logged DIFF records" (output/modeling-brief.md:209)
SC_U6c == \E s \in Server : up[s] /\ role[s] = "leading"
                            /\ \E e \in Range(durable[s]) : e \notin Range(applied[s])

\* P_CPoQ: "Every history an active leader treats as committed is persisted ... on a quorum"
\* (output/modeling-brief.md:187)
SC_P_CPoQ == \E l \in Server : ActiveLeader(l) /\ Len(committed[l]) > 0

\* P_LC: "Every certified (committed) transaction is in every active leader's committed history"
\* (output/modeling-brief.md:188); situation: an active leader of a later epoch than a certified record.
SC_P_LC == \E l, s \in Server : ActiveLeader(l) /\
             \E k \in 1..Len(committed[s]) : commitCertified[committed[s][k].id]
                                              /\ committed[s][k].epoch < currentEpoch[l]

\* P_SAC: "restored/fast-forwarded uncommitted records are allowed only while not serving"
\* (output/modeling-brief.md:182)
SC_P_SAC == \E s \in Server : up[s] /\ zkState[s] /= "RUNNING"
              /\ \E k \in 1..Len(applied[s]) : ~commitCertified[applied[s][k].id]

\* P_SCJ: "strengthening (a broadcasting follower must also have sent its NEWLEADER ACK)" (invariant-evidence.json)
SC_P_SCJ == \E s \in Server : role[s] = "following" /\ phase[s] = "broadcast"

\* P_OAL: "the predicate quantifies over established leaders (role leading and epoch settled)" (invariant-evidence.json)
SC_P_OAL == \E l \in Server : up[l] /\ Established(l) /\ currentEpoch[l] > 0

\* P_PP: "a crashed process has no data tree, so snapshot-prefix-of-applied is required only for live servers"
\* (invariant-evidence.json)
SC_P_PP == \E s \in Server : ~up[s] /\ Len(snapshot[s]) > 0

\* C_ActOld: "The activation of an older-epoch record (the broad canary CanaryActivationCommitsOldEpoch was
\* not reached from MCInit within budget)" (spec/output/validation-summary.md:130-131)
SC_C_ActOld == ~CanaryActivationCommitsOldEpoch

\* positive control: a leader is active
SC_CTRL == \E l \in Server : ActiveLeader(l)
====
