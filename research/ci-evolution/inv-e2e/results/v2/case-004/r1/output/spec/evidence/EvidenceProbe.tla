---- MODULE EvidenceProbe ----
(***************************************************************************)
(* Divergence-evidence evaluator: replays a real trace with Trace.tla and  *)
(* evaluates the ACTUAL old (V0 OldBase, copied verbatim from               *)
(* /work/previous/.specula-output/spec/base.tla, module line renamed) and  *)
(* new (base / Update) property definitions on every replayed state. The   *)
(* probes print <<label, cursor, old, new>> for every state; they are      *)
(* TRUE-valued, so they never prune the replay.                            *)
(***************************************************************************)
EXTENDS Trace

Old == INSTANCE OldBase
U == INSTANCE Update WITH
        ElectionLimit <- 0, TransferLimit <- 0, AppendLimit <- 0,
        MembershipLimit <- 0, CrashLimit <- 0, StaleLimit <- 0,
        ElectNodes <- {},
        electionCount <- 0, transferCount <- 0, appendCount <- 0,
        membershipCount <- 0, crashCount <- 0, staleCount <- 0,
        grantLog <- {}, voteReqs <- {}, transferLog <- {}

Probe ==
    /\ PrintT(<<"ElectionByVoterOnly", l, "old:not-defined", U!ElectionByVoterOnly>>)
    /\ PrintT(<<"NoRaftCorePanic", l, "old:not-defined", U!NoRaftCorePanic>>)
    /\ PrintT(<<"CandidateGrantSound", l, Old!CandidateGrantSound, CandidateGrantSound>>)
    /\ PrintT(<<"LeaderVoteCommitted", l, Old!LeaderVoteCommitted, LeaderVoteCommitted>>)
    /\ PrintT(<<"CommittedLogAgreement", l, Old!CommittedLogAgreement, CommittedLogAgreement>>)
    /\ PrintT(<<"CurrentTermCommit", l, Old!CurrentTermCommit, CurrentTermCommit>>)
    /\ PrintT(<<"records", l, [candidates |-> {n \in Server : candidate[n]},
                               leaders |-> {n \in Server : role[n] = "Leader"},
                               cand_cfg |-> candidateConfigs,
                               commit |-> commitIndex]>>)
====
