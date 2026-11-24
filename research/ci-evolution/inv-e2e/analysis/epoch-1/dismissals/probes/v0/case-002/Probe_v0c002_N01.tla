---- MODULE Probe_v0c002_N01 ----
\* Dismissal (bug-report.md:127): "U-LOSS with crashes instead of INITIAL exit ...
\* Not reached within budget ... crash consequence covered by MC-2".
\* Canary: a newly established leader lacks a committed entry (LeaderCompleteness
\* step fails) on a path that used a crash, while MC-2's characteristic condition
\* (EpochHistoryRecoverable: persisted epoch without durable history) is absent.
EXTENDS Update
Canary == ~LeaderCompletenessStep /\ counters.crash > 0 /\ EpochHistoryRecoverable
NotCanaryAct == [][~Canary]_mcAllVars
====
