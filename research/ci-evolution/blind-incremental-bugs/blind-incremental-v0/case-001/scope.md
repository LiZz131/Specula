# V0 model scope: case-001

## Authority

The only behavioral authority is `/work/old-tree`. Generate a pre-update suite
without repository history, network research, another revision, or subject and
grading metadata. This document selects a neutral subsystem boundary; it does
not prescribe a future change, finding, or property outcome.

## Category and boundary

This is a Category A crash-fault-tolerant replicated-state-machine library. The
V0 boundary includes the deterministic Engine, the RaftCore event loop, log
storage submission and completion, election, log replication, commit progress,
and cluster initialization. Application command semantics and storage-engine
internals beyond the public old-version interfaces are outside the boundary.

## State and identities to derive

Derive the minimal exact-old representation of node role and vote, log and
membership state, per-peer replication progress, Engine commands, storage IO
identity and progress, completion notifications, and in-flight protocol
messages. Preserve distinctions that the old interfaces expose; collapse Rust
types, allocation, and serialization details.

## Atomicity and faults

Treat Engine transitions, command submission, storage completion, notification
delivery, and RaftCore handling as separate steps only where the exact-old code
permits them to interleave. Storage implementations may execute work
independently; document, rather than assume, any ordering guarantee. Include
crash/restart and message delay only at boundaries justified by the old code.

## Neutral trace baseline

Start with ordinary single-node initialization, multi-node election, and log
append/replication scenarios already present in the old tree. Instrument stable
post-state boundaries and generic IO lifecycle events. Do not construct a
special schedule to demonstrate a suspected failure.

## Exclusions

Exclude wall-clock performance, a particular runtime implementation, disk-file
format, application state-machine contents, and all behavior absent from the old
tree. Do not add a future API or name a possible update obligation.

## V0 completion rule

Freeze only after the model parses, bounded reference checking terminates, and
at least one fresh exact-old trace is completely validated. The suite must not
contain bug reports, reproductions, targeted hunt configurations, expected
findings, or historical annotations.

