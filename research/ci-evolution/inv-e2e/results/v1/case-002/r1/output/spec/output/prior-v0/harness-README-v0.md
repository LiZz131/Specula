# Specula V0 trace harness

`run.sh` runs four exact-old JUnit scenarios against the instrumented writable
tree. Each run is bounded by an outer 240-second timeout and writes a fresh,
nonempty NDJSON trace plus a Maven/test log. The selected source tests exercise:

- follower discovery, SNAP sync, a proposal, commit, application, and persistence;
- DIFF synchronization and in-flight transaction persistence;
- real peer election/startup, a client mutation, and shutdown;
- leader abandonment followed by restart and recovery.

The probes are synchronous and opt-in through `specula.trace.file`. They do not
start threads and write actual wall-clock/nanosecond time and Java thread
identity. Run from any directory with:

```sh
timeout 1000s /work/prior/.specula-output/harness/run.sh
```

The environment only provides JDK 21. The exact-old build accepts it; this is
broader than the manifest's preferred JDK 8 / allowed JDK 11 and is recorded as
an environment coverage limitation.
