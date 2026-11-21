# E2 — NoRaftCorePanic separating state (mc)

State: final state (State 16) of the TLC counterexample in
`spec/output/mc-Update_hunt_U2_panic.log` (also `spec/output/mc-Update_canary_CanaryLearnerPanic.log`):
learner 3 handled `MCTransferLeader(3)`, persisted its candidate vote, sent its requests and then
handled its own grant `MCVoteResponse(3,3)`, which takes `base!CandidateGrantPanic`
(`panicked[3] = TRUE`, `up[3] = FALSE`). TLC evaluated `Update!NoRaftCorePanic` = FALSE on it
(that is the reported invariant violation). Old suite: property not defined (not checked).

Control E2c: every replayed state of the 18 fresh traces (e.g. `spec/evidence/E1/tlc.log`,
`spec/evidence/E1c/tlc.log`, `spec/evidence/EK1/tlc.log` print `NoRaftCorePanic` = TRUE).

Implementation: clean worktree of d7176ef, `spec/output/clean-update-specula_repro_transfer_to_learner_no_panic.log`
("panicked at openraft/src/proposer/candidate.rs:92:59: target not in quorum set").
