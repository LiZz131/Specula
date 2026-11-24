---- MODULE CensusProbes ----
EXTENDS MC
\* Census precondition probes for v2/case-002 (state predicates only; no actions).

\* U1 "the updated NEWLEADER branch hands the buffered DIFF/TRUNC proposals to ... logRequest
\* (an enqueue ...) and immediately writes ACK(NEWLEADER)" (output/modeling-brief.md:208-215)
\* -> a learner has sent its NEWLEADER ACK while its synced history is not yet durable.
SC_U1 == \E s \in Server : up[s] /\ nlAckSent[s] /\ ~IsPrefix(recovered[s], durable[s])

\* U2 "crash inside the ACK/fsync window ... U1 plus Crash (queued records are lost) and re-election"
\* (output/modeling-brief.md:221-224) -> a learner whose NEWLEADER ACK was counted by the current leader
\* is down and lacks (durably) a transaction that this leader committed in that epoch.
SC_U2 == \E l, s \in Server :
           /\ s /= l /\ s \in nlAcks[l] /\ ~up[s]
           /\ \E t \in Txn : commitCertified[t] /\ certEpoch[t] = acceptedEpoch[l]
                             /\ t \notin TxnIds(durable[s])

\* U4 "between NEWLEADER and UPTODATE the server is INITIAL ... any failure ... runs Learner.shutdown ...
\* processors are not stopped" (output/modeling-brief.md:237-243) -> a live server back in LOOKING
\* still has queued (not yet durable) log records, i.e. it left sync with a running sync processor.
SC_U4a == \E s \in Server : up[s] /\ role[s] = "looking" /\ Len(durable[s]) < Len(queued[s])

\* U4 "The leaked SyncRequestProcessor persists the streamed txns while the in-memory database
\* (reported in FLE and ACKEPOCH, served by a new leader) lacks them." (output/modeling-brief.md:243-245)
SC_U4b == \E s \in Server : up[s] /\ phase[s] \in {"election", "discovery"}
                            /\ (TxnIds(durable[s]) \ TxnIds(memHist[s])) /= {}

\* LeaderCompleteness intent "A leader that activates in a later epoch serves every transaction
\* committed in an earlier epoch." (output/spec/UpdateProps.tla:37) -> precondition (antecedent non-vacuous).
SC_P_LC == \E l \in Server : up[l] /\ role[l] = "leading" /\ phase[l] = "broadcast"
                             /\ \E t \in Txn : commitCertified[t] /\ certEpoch[t] < acceptedEpoch[l]

\* SyncedLogMatchesLeader intent "After a follower completes synchronization, its persistent log holds no
\* transaction that its current leader does not have" (output/spec/UpdateProps.tla:53)
SC_P_SLMLa == \E s \in Server : up[s] /\ role[s] = "following" /\ phase[s] = "broadcast"
                                /\ leaderOf[s] \in Server /\ up[leaderOf[s]] /\ durable[s] /= <<>>

\* same intent: "duplicates of the leader's transactions are tolerated" (output/spec/UpdateProps.tla:53)
SC_P_SLMLb == \E s \in Server : \E i, j \in 1..Len(durable[s]) : i /= j /\ durable[s][i].id = durable[s][j].id

\* SyncCompletionJustified strengthening "UPTODATE processing (follower BROADCAST) is now a separate step
\* after the NEWLEADER ACK" (invariant-evidence.json:10)
SC_P_SCJ == \E s \in Server : role[s] = "following" /\ phase[s] = "broadcast"

\* PendingOnlyDuringSync intent "The learner sync buffer is non-empty only while that learner is
\* synchronizing." (output/spec/UpdateProps.tla:68)
SC_P_POD == \E s \in Server : pendingSync[s] /= <<>>

\* Positive control: some leader activated (broadcast).
SC_CTRL == \E l \in Server : role[l] = "leading" /\ phase[l] = "broadcast"
====
