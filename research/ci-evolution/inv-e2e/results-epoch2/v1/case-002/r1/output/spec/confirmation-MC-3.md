# Confirmation MC-3 — learner txn ACK can precede its NEWLEADER ACK

- Status: **REPRODUCED** with a timing injection (learner-thread pause before the epoch ACK
  write, emulating a descheduled learner thread); not observed without injection.
- Source revision: commit 2efbdfc ("update"); old control: commit 1414ebf ("baseline").
- Model: `spec/output/cex/MC-3_NewLeaderAckIsFirstAck_hunt2s.out` (22 states),
  `MC-3_NewLeaderAckIsFirstAck_fullMCNext.out`.

## Code path
`Learner.java:751-760` starts the request processors (SyncRequestProcessor →
SendAckRequestProcessor) before the learner thread writes the NEWLEADER ACK.
`LearnerHandler.java:606-623` reads the first packet after NEWLEADER as the NEWLEADER ACK;
`Leader.waitForNewLeaderAck` rejects a txn zxid (`Leader.java:1556-1562`); the real
NEWLEADER ACK later reaches `processAck`, which ignores epoch zxids (`Leader.java:988-994`).

## Natural runs
NEWLEADER ACK first in all traced exchanges (13 conformance traces) and in
`SpeculaNewLeaderAckOrderTest` with 7 (traced ×3), 1500 (traced ×1, untraced ×2) and
3000 (untraced ×2) DIFF txns (`spec/output/incremental/harness/notrace-ackorder-*.log`).

## Reproduction
Command: `SKIP_PREPARE=1 SCENARIOS="repro-u3-ack-delay-r1" harness/run.sh`
(test `harness/repro/SpeculaU3ReproTest.java`: update test scenario without the UPTODATE
failure; restarted learners pause 1.5 s before writing an epoch ACK).
Result (`traces/fault-injected-repro/repro-u3-ack-delay-r1.ndjson`): in epochs 2, 3 and 4 the
leader's `NewLeaderAckReceived` shows `rejected-zxid-mismatch` for both learners (first ACK =
txn (1,2)); the leader returns to DISCOVERY each time; `establishedLeader=-1` after 100 s;
10 "is from a different epoch" errors in the test output.
Old revision with the same pause: leader established, 0 rejections
(`spec/output/incremental/harness/old-control-repro-u3-r1.log`). Update-introduced.
