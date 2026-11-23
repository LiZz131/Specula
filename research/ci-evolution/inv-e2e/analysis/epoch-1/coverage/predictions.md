# Predictions, written before any run (2026-11-23)

Question: would update-coverage/check.py, run unchanged on the final epoch-1 specs, have flagged the cfg
gaps the TLC evidence found? Each gap below is a scenario the arm's own cfgs cannot reach
(see ../evidence/<case>/README.md).

| Gap | Probe that would have to show it | Prediction | Reason |
|---|---|---|---|
| 004 v2: `MembershipLimit <= 1`, node removal unreachable | a membership-change action | not flagged | v2's `AffectedActions` is only `MCTransferLeader`; no probe covers membership change |
| 011 v0: `MaxElectionCount <= 2` in every membership cfg, bug B unreachable | pre-vote response handling | not flagged | the action is enabled in these cfgs; the gap is a third election round, a depth/budget condition, not an action |
| 006 v1/v2: standard `MC.cfg` has `MaxReadLimit = 1`, context reuse unreachable | ReadIndex handling | not flagged | the hunt cfgs take the action, and the check is per action over all cfgs, not per cfg |
| 004 v1: `TransferTargets = {2,3}` in the main cfg | `MCTransferLeader` | not flagged | the action is taken; the gap is one argument value (self-transfer) |

If all four hold, the tool as-is does not cover proposal A; A needs scenario-level preconditions,
not action-level probes. Also recorded: gaps the tool does report on the 21 specs (possible noise or real findings).
