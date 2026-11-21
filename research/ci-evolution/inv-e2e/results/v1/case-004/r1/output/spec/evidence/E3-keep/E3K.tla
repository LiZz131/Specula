---- MODULE E3K ----
(* Keep-evidence: evaluate the prior (OldBase) and current definitions of the affected reference
   properties on every state of real transfer-scenario traces (post-transfer leaders, candidates,
   vote grants, panic).  Both must hold where the requirement says the state is legal. *)
EXTENDS Trace
Old == INSTANCE OldBase
Keep ==
    /\ Old!CandidateGrantSound = CandidateGrantSound
    /\ Old!LeaderVoteCommitted = LeaderVoteCommitted
    /\ Old!DurableStateBounded = DurableStateBounded
    /\ Old!CurrentTermCommit = CurrentTermCommit
KeepHolds ==
    /\ CandidateGrantSound /\ LeaderVoteCommitted /\ DurableStateBounded /\ CurrentTermCommit
====
