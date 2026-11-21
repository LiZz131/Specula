# Exact-old instrumentation handoff

The harness instruments only `/work/work-source`. The immutable evidence tree
is `/work/source`. `apply.sh` verifies and applies
`patches/instrumentation.patch`, then installs the two added Java files from
`harness/src/`. A reverse dry-run with GNU `patch` is the provenance check used
by the validation suite.

## Marker locations after apply

- Startup, shutdown, and accepted/current epoch memory/persistence markers:
  `QuorumPeer.java:774,1205,1761-1775`.
- Election result markers: `FastLeaderElection.java:1002,1029,1062`.
- Leader epoch support, epoch/NewLeader acknowledgements, readiness, proposal,
  acknowledgement, and commit markers:
  `Leader.java:841,970,1089,1177,1226,1294,1339`.
- Learner sync application/proposal/commit/snapshot/readiness markers:
  `Learner.java:336,403,439,460,537,552`.
- Leader sync-mode and wire-boundary markers:
  `LearnerHandler.java:413,447,461,522,965`.
- Follower proposal/commit and persistence pipeline markers:
  `Follower.java:138`, `FollowerZooKeeperServer.java:112`,
  `SyncRequestProcessor.java:124,184`, `SendAckRequestProcessor.java:47`, and
  `FinalRequestProcessor.java:128`.

## Adjusting capture

`harness/src/SpeculaTrace.java` owns the NDJSON envelope. To add a field, add a
parameter and serialized key there, update every relevant `emit` call in the
recorded patch, update `normalize-trace.jq` if the value needs a TLC-safe
projection, then add the matching check to the corresponding wrapper in
`spec/Trace.tla`. Do not retain an emitted state field that Trace does not
consume.

To add an event, insert the marker at the exact old-source transition boundary,
add its source mapping to `spec/instrumentation-spec.md`, and add a one-to-one
wrapper in `spec/Trace.tla` that invokes the base action and checks its
post-state. To move a marker, update the patch and the cited before/after
boundary together; marker timing is semantic evidence.

## Rebuild and replay

From `.specula-output`, run `timeout 360s harness/run.sh NAME` to apply, build,
test, preserve the original bytes, and normalize the trace. Then run
`timeout 900s harness/run-checks.sh`. The latter parses all specs, validates
every retained top-level trace before either canonical BFS, requires natural
completion with a zero queue, records commands and exit codes, and removes its
TLC metadata directories.
