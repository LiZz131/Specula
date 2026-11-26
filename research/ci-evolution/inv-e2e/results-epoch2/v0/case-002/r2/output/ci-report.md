# Incremental CI report

Model updated for the NEWLEADER/UPTODATE change; three model-checking findings and two code-review findings were reproduced on the updated implementation.

CI verdict: **FAIL**. Reproduced bugs: 5; other unresolved findings: 0; other dispositions: 0.

[Findings and evidence](confirmed-bugs.md) · [Severity](bug-severity.md)

## Validation limits

- All TLC runs are budget-limited (30 min each); no state space was exhausted. MC.cfg BFS reached depth 28 (16.9M distinct states), Update-full BFS depth 28 (17.5M), focused BFS depth 29, discharge depth 22; simulation follow-ups are recorded in spec/model-checking-campaign.md.
- The full-MCNext counterexample for MC-1 starts from seeded epoch-2 states whose reachability is shown by canary NotUpdateDurabilityGap and by replaying the real diff-sync-uncommitted trace; the data-loss consequence (CommittedAgreement) was not reached by model checking within budget and is shown only by the implementation reproduction.
- Open-spec (EnvUpdate) results are claimed only for a fixed established epoch; epoch creation is covered only by the full MCNext checks.
- The leaked SyncThread of CR-4 is modeled only for its history effect; quiescence guards on ElectLeader and LeaderSyncFollower assume it drains before an election completes.
- MC-1 and MC-2 reproductions use Level 1 timing assistance (delayed follower SyncThread plus crash emulation; delayed NEWLEADER-ACK write); MC-3 (deterministic fixture; real cluster triggers in 4 of 5 runs), CR-4 and CR-5 are Level 0.
- Builds and tests used JDK 11 (prior run used JDK 21). Observers, dynamic reconfiguration and the pre-Zab1.0 protocol remain outside the model scope.
- Novelty was not assessed: issue-tracker and history research is prohibited in this blind run.
