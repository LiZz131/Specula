--------------------------- MODULE UpdateFiltered ---------------------------
(* Follow-up update runs: filter the already-analyzed U4 counterexample      *)
(* class (INITIAL-state exit with the leaked flush; MC-2) so that full/focused *)
(* runs keep exploring toward the target property.  Exploration-only.         *)
EXTENDS Update
FilterKnownU4Flushed == "initial-exit-flushed" \notin seen
\* precise filter for the MC-2 class (log ahead of the in-memory DB at a vote)
FilterKnownU4 == VotingHistoryCoversDurable
=============================================================================
