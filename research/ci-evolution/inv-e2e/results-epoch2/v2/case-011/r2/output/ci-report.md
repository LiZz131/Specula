# Incremental CI report

Pre-Vote update required a model change (new pre-candidate state, Pre-Vote messages, a new elect() caller, changed tick/do_elect/become_following). The reference, MC, Trace and Update suites were updated; the prior harness was rebased; 17 fresh traces pass TLC trace validation with 12/12 negative controls rejected; two prior-model defects (empty-log comparison, leader lease on establishment) were repaired. Model checking found three update-introduced defects, all reproduced on the updated implementation through the public API: a timer Pre-Vote round survives leader establishment and makes the new leader re-elect (MC-1), and two RaftCore panics in Candidate::grant_by when a completed or repeated round involves nodes outside the frozen quorum set (MC-2, MC-3). A documentation mismatch about Unreachable pre-vote responses (pre_vote.md) was noted as code review only.

CI verdict: **FAIL**. Reproduced bugs: 3; other unresolved findings: 0; other dispositions: 0.

[Findings and evidence](confirmed-bugs.md) · [Severity](bug-severity.md)

## Validation limits

- All TLC campaigns are bounded (3 nodes, 2 in one hunt; terms <= 2-3; log index <= 3-4; bounded elections, pre-vote rounds, membership changes, crashes, drops, messages) and most BFS runs stopped at their time budget with states left on the queue (LIMITED_COVERAGE), followed by bounded simulation; no exhaustive pass or proof is claimed.
- Membership learners and follower-side membership changes are not modelled; the non-voter election outcome is a nondeterministic union, and the follower variant of MC-3 is covered only by source analysis.
- The engine-level harness captures the frozen candidate/pre-candidate quorum through the effective membership (private field); no traced scenario changes membership after a round starts.
- Timer, lease and RPC-timeout behaviour are abstracted as enablement nondeterminism; their effect is exercised only by the runtime reproductions.
- MC-1's runtime reproduction needs timing assistance (slow vote persistence emulated in the test store plus RPC hook delays); a pure black-box Level-0 attempt did not hit the window.
- Old-revision controls are not runnable because the Pre-Vote API does not exist in the old revision; attribution to the update rests on source comparison.
- External issue trackers were not consulted (blinded run); novelty is NEW with respect to the supplied tree only.
