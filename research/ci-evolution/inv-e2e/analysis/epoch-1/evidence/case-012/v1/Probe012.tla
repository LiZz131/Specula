---- MODULE Probe012 ----
\* Decision probes for the case-012 evidence card. Adds no actions; only a state predicate
\* and an action property over variables that all three arms share (role, committed,
\* lastLog, logTerm, effectiveConfig, effectiveMembershipIndex).
EXTENDS Update

\* Ground truth of replication: nodes whose log actually holds leader i's entry at index k
\* (same term at k; logs are contiguous from index 0). Not VecProgress, not matchedIndex.
HoldersOf(i, k) ==
    {j \in Server : lastLog[j] # Nil /\ lastLog[j] >= k /\ logTerm[j][k] = logTerm[i][k]}
MajEach(cfg, S) == \A g \in cfg : 2 * Cardinality(g \cap S) > Cardinality(g)

\* MC-1 trigger state: a leader whose effective membership is joint (two groups) has
\* committed the joint entry (or a later one), but the nodes holding that index are not a
\* majority of every group. Joint consensus requires both (openraft quorum/joint.rs:56-63).
JointOvercommit(i) ==
    /\ role[i] = "leader"
    /\ Cardinality(effectiveConfig[i]) = 2
    /\ committed[i] # Nil
    /\ committed[i] >= effectiveMembershipIndex[i]
    /\ ~MajEach(effectiveConfig[i], HoldersOf(i, committed[i]))
ProbeNoJointOvercommit == ~\E i \in Server : JointOvercommit(i)

\* General form as an action property: whenever a leader's commit index advances, the
\* holders of the new commit index form a quorum of every group of its effective
\* membership before or after the step (leader_append_entries calls update_progress
\* both before and after upgrading the quorum set).
HoldersOfNext(i, k) ==
    {j \in Server : lastLog'[j] # Nil /\ lastLog'[j] >= k /\ logTerm'[j][k] = logTerm'[i][k]}
BadCommitStep(i) ==
    /\ role[i] = "leader" \/ role'[i] = "leader"
    /\ committed'[i] # Nil /\ committed'[i] > committed[i]
    /\ ~MajEach(effectiveConfig[i], HoldersOfNext(i, committed'[i]))
    /\ ~MajEach(effectiveConfig'[i], HoldersOfNext(i, committed'[i]))
ProbeCommitHasQuorum == [][\A i \in Server : ~BadCommitStep(i)]_mcVars
\* Frame canary (positive control for the predicate's frame): a leader in a joint membership
\* has committed the joint entry at all (legitimately or not).
ProbeNoJointCommit ==
    ~\E i \in Server : /\ role[i] = "leader" /\ Cardinality(effectiveConfig[i]) = 2
                       /\ committed[i] # Nil /\ committed[i] >= effectiveMembershipIndex[i]

\* Used only by the SYMMETRY experiment on v0/v1 (v2 defines its own Symmetry in MC.tla).
ProbeSymmetry == Permutations(Server)
====
