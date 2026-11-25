----------------------------- MODULE MCFiltered -----------------------------
(* Follow-up standard rounds: filter the already-analyzed U4 counterexample   *)
(* class (MC-2: an INITIAL-state exit leaves the in-memory DB used for voting *)
(* and Leader.lead behind the durable log) so that the round keeps exploring  *)
(* the rest of the state space.  Exploration-only constraint; the reference   *)
(* behavior and the checked properties are unchanged.                        *)
EXTENDS MC, UpdateProps
\* round-1 filter (only the leaked-flush branch); superseded by FilterKnownU4
FilterKnownU4Flushed == "initial-exit-flushed" \notin seen
FilterKnownU4 == VotingHistoryCoversDurable
StandardConstraint == CanonicalDepthBound /\ FilterKnownU4
=============================================================================
