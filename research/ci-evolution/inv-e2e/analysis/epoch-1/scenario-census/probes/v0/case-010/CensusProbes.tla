---- MODULE CensusProbes ----
EXTENDS MC

\* Positive control: some transaction is globally committed.
SC_PC == globalCommitted # <<>>

\* U1: "a learner that had replaced its data tree with the leader's SNAP image (Learner.java:565-586)
\* but had not yet reached the NEWLEADER snapshot (:739-741) kept that non-durable image"
\* / "U1 - SNAP-window learner exit (directly changed). old producer ChooseSyncMode(SNAP)/
\* LearnerApplySnapshot ... -> changed LearnerShutdown"  (output/modeling-brief.md:193,207)
\* Encoded as: a SNAP learner holds a non-durable applied image and the exit is enabled.
SC_U1 ==
    \E f \in Server :
        /\ syncMode[f] = "SNAP" /\ syncStage[f] = "DATA"
        /\ ~(Elems(memDb[f]) \subseteq Elems(durable[f]))
        /\ ENABLED MCLearnerShutdown(f)

\* U1b: "old producer ChooseSyncMode(SNAP)/LearnerApplySnapshot (and in-memory COMMITs)"
\* (output/modeling-brief.md:207). Encoded as: in a SNAP window an in-memory COMMIT is enabled.
SC_U1b ==
    \E f \in Server :
        /\ syncMode[f] = "SNAP" /\ syncStage[f] = "DATA" /\ syncBuf[f] # <<>>
        /\ ENABLED MCSyncCommit(f)

\* U1r: "Expected (source): after the exit the peer reports only disk history; a rejoin then
\* receives the missing transactions" (output/modeling-brief.md:207). Encoded as: a peer whose
\* stale syncMode is SNAP (only an exit before NEWLEADER leaves it) re-registered with a leader,
\* a DIFF can be chosen, and a committed transaction is missing from its disk.
SC_U1r ==
    \E f \in Server :
        /\ syncMode[f] = "SNAP" /\ role[f] = "FOLLOWING" /\ syncStage[f] = "IDLE"
        /\ \E t \in Elems(globalCommitted) : t \notin Elems(durable[f])
        /\ ENABLED MCChooseSync(f, "DIFF")

\* P-SERD: SnapExitReportsDisk intent: "After a SNAP-window exit the next reported history is
\* reloaded from disk, i.e. a peer whose stale syncMode is SNAP and that is LOOKING never reports
\* the discarded leader image." (output/spec/Update.tla:144-147)
SC_PSERD ==
    \E s \in Server :
        running[s] /\ role[s] = "LOOKING" /\ syncMode[s] = "SNAP" /\ memInit[s]

\* U2a: crash-based U2: "PA proposes a second record that only PA logs, then PA crashes; PB leads
\* epoch 2 ... PA restarts, joins PB and may be sent TRUNC" (output/spec/Update.tla:192-194);
\* "The crash-based U2 path (old leader's uncommitted record) ... not reached within bounds"
\* (output/spec/output/verification-summary.md:28). Encoded as: TRUNC chosen for a peer whose disk
\* holds a never-committed record (before the truncation step).
SC_U2a ==
    \E f \in Server :
        /\ syncMode[f] = "TRUNC" /\ syncStage[f] = "MODE"
        /\ \E t \in Elems(durable[f]) : t \notin Elems(globalCommitted)

\* U2b: "TRUNC followed by forwarded PROPOSAL/COMMIT before NEWLEADER ... a TRUNC-mode exit keeps the
\* in-memory transaction" (output/modeling-brief.md:209); crash-free variant "reached without any
\* crash (learner ahead of the leader's applied frontier)" (modeling-brief.md:239).
\* Encoded as: TRUNC learner with a memory-only record, exit enabled, no crash so far.
SC_U2b ==
    \E f \in Server :
        /\ syncMode[f] = "TRUNC" /\ syncStage[f] = "DATA"
        /\ ~(Elems(memDb[f]) \subseteq Elems(durable[f]))
        /\ ENABLED MCLearnerShutdown(f)
        /\ counters.crashes = 0

\* U2 (any): TRUNC learner with a memory-only record and the exit enabled (with or without crash).
SC_U2 ==
    \E f \in Server :
        /\ syncMode[f] = "TRUNC" /\ syncStage[f] = "DATA"
        /\ ~(Elems(memDb[f]) \subseteq Elems(durable[f]))
        /\ ENABLED MCLearnerShutdown(f)

\* U3: "DIFF learner exit between NEWLEADER and UPTODATE ... DIFF NEWLEADER logs buffered proposals
\* without applying them; an exit before UPTODATE leaves the database under-reporting its own log"
\* (output/modeling-brief.md:211). Encoded as: after NEWLEADER ACK, log ahead of data tree, exit enabled.
SC_U3 ==
    \E f \in Server :
        /\ syncStage[f] = "ACKED"
        /\ ~(Elems(durable[f]) \subseteq Elems(memDb[f]))
        /\ ENABLED MCLearnerShutdown(f)
====
