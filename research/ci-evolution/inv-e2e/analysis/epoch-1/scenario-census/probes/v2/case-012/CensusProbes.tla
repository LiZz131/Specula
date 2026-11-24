---- MODULE CensusProbes ----
EXTENDS MC
\* Census probes for v2/case-012 (state predicates only; no actions). Base/MC variables only, so the
\* module works under both the MC-based and the Update-based cfgs.

\* PC (positive control): some node took the leader role (agent's ReachLeader, base.tla:1066).
SC_PC == \E i \in Server : role[i] = "leader"

\* US1a. "U-S1: Leader append with a membership entry commits through progress" / "Uncertainty: commit at
\* append time from follower progress under the upgraded quorum set" (output/modeling-brief.md:166,169).
\* Encoded (weaker: the append-time step is not visible in a state): a leader whose progress quorum set
\* was upgraded away from the initial membership has recorded a commit under that upgraded set with a
\* follower among the supporters.
SC_US1a == \E i \in Server :
             /\ role[i] = "leader" /\ leaderState[i]
             /\ progressConfig[i] # InitialConfig
             /\ witnessIndex[i] # Nil
             /\ witnessConfig[i] = progressConfig[i]
             /\ witnessNodes[i] \ {i} # {}

\* US1b. "Uncertainty: ... promotion of the previous effective membership" (output/modeling-brief.md:169)
\* Encoded: a leader has a promoted (committed) membership log entry.
SC_US1b == \E i \in Server : role[i] = "leader" /\ committedMembershipIndex[i] # Nil

\* US1c. "Uncertainty: ... leader removing itself." (output/modeling-brief.md:169)
\* Encoded: a node holding leader data whose progress quorum set no longer contains it.
SC_US1c == \E i \in Server : leaderState[i] /\ i \notin Voters(progressConfig[i])

\* US2a. "U-S2: Election recreates leader progress ... Uncertainty: commit evidence after the progress is
\* recreated" (output/modeling-brief.md:173,176). Same predicate as the agent canary
\* ReachReelectedLeaderWithOldWitness (base.tla:1073).
SC_US2a == \E i \in Server : leaderState[i] /\ witnessIndex[i] # Nil /\ witnessTerm[i] < currentTerm[i]

\* US2b. "(changed action -> crash/recovery -> changed action)" (output/modeling-brief.md:173).
\* Encoded (weaker: the crash counter is global): after a crash, every node is up again and some node
\* leads in a term above 1.
SC_US2b == crashes > 0 /\ crashed = {} /\ \E i \in Server : role[i] = "leader" /\ currentTerm[i] > 1

\* US3. "Uncertainty: states where the effective membership is covered by the commit index but not
\* promoted." (output/modeling-brief.md:183). Same predicate as ReachUnpromotedCoveredMembership (base.tla:1075).
SC_US3 == \E i \in Server : /\ effectiveMembershipIndex[i] <= committed[i]
                            /\ committedMembershipIndex[i] < effectiveMembershipIndex[i]

\* US4. "U-S4: Progress quorum-set upgrade on membership change" (output/modeling-brief.md:187).
\* Same predicate as ReachLeaderWithProgressUpgrade (base.tla:1071).
SC_US4 == \E i \in Server : leaderState[i] /\ progressConfig[i] # InitialConfig

\* P1. ProgressMonotonic intent: "Within one leader-data lifetime (same term, leader data present before and
\* after), the progress value of an id tracked before and after a step never decreases" (spec/Update.tla:156);
\* watch includes VecProgress::upgrade_quorum_set. Encoded: after an upgrade, an id tracked in both the
\* initial and the upgraded set carries a non-empty progress value.
SC_P1 == \E i, j \in Server :
           /\ leaderState[i] /\ progressConfig[i] # InitialConfig
           /\ j \in Voters(progressConfig[i]) \cap Voters(InitialConfig)
           /\ matchedIndex[i][j] # Nil

\* C1. "handle_update_matched, which now skips the Engine progress update when matched <= committed
\* (core/replication.rs:133-135) ... values may lag. Checked by Update!ProgressMonotonic and commit
\* properties." (output/analysis-report.md:115). Encoded: a positive ack at or below the leader's commit
\* is pending at a current-term leader.
SC_C1 == \E m \in messages :
           /\ m.type = "ack" /\ m.ok
           /\ m.to \notin crashed /\ role[m.to] = "leader" /\ currentTerm[m.to] = m.term
           /\ m.last >= matchedIndex[m.to][m.from]
           /\ m.last <= committed[m.to]

\* C2a. "RejectAppendConflict / DiscardNegativeAck had no positive coverage at the explored depths"
\* (spec/bug-report.md:61); Update.tla:26 "RejectAppendConflict ... (drops leader data, truncates)".
\* Encoded: the guard of RejectAppendConflict (base.tla:562-568) holds for a pending append.
SC_C2a == \E m \in messages :
            /\ m.type = "append" /\ m.to \notin crashed
            /\ m.term >= currentTerm[m.to] /\ m.prev # Nil
            /\ ~HasLogId(m.to, m.prev, m.ents[m.prev])

\* C2b. same quote, DiscardNegativeAck: a negative ack is pending (base.tla:721-724).
SC_C2b == \E m \in messages : m.type = "ack" /\ ~m.ok
====
