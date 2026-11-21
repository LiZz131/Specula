# ZooKeeper Zab V0 modeling scope

This is a source-first baseline-modeling task. Analyze only the supplied
historical source tree. There is no source update in this phase, and no later
revision or historical defect information is part of the input.

## System category

Category A: a distributed, message-passing replicated state machine with
leader election, epoch changes, log replication, durable storage, recovery,
and independently scheduled request-processing components.

## Required behavioral scope

Build a finite-state TLA+ model of the old implementation's ZooKeeper Atomic
Broadcast behavior. Derive the actual transitions and atomicity boundaries
from the source rather than assuming that an informal protocol step is atomic.
Cover:

- server roles and the election, discovery, synchronization, and broadcast
  phases;
- accepted/current epochs, zxids, leader/follower relationships, and quorum
  decisions needed by recovery;
- the leader-to-learner synchronization modes and the protocol messages used
  to establish a synchronized follower;
- volatile, queued, durable, committed, and applied transaction state at the
  smallest abstraction that preserves ordering and recovery behavior;
- snapshots, transaction-log persistence, crash, restart, and re-election;
- independently scheduled server/request-processing components when the old
  source makes their ordering observable.

Do not prescribe a particular ordering between these operations in advance.
Represent the ordering and concurrency that the old source actually permits.
If an implementation distinction cannot affect the properties below, abstract
it and document the abstraction.

## Baseline properties

Include and model-check general protocol properties, without tailoring them to
any historical incident:

- type correctness and well-formed message/state records;
- at most one active leader per epoch under the modeled quorum assumptions;
- committed histories agree on their common prefix;
- a transaction is not applied before the model's commit and durability
  preconditions hold;
- commit, apply, and durable-history positions do not move backward except
  through a source-faithful recovery action whose retained state is explicit;
- epoch transitions and recovered histories remain mutually consistent;
- a server that completes synchronization enters broadcast with a state that
  is justified by the synchronization exchange.

Liveness checks may be bounded and conditional on explicit fairness and fault
assumptions. Never report a resource-limited liveness run as a proof.

## Validation and harness scope

Create a baseline harness from the old implementation. Exercise ordinary
startup, election, client mutation, follower synchronization, shutdown,
restart, and recovery paths. Emit nonempty NDJSON traces whose fields are
actually consumed by `Trace.tla`. Preserve exact build/test/trace commands and
event inventories.

Use only scenarios justified by the old source and its existing tests. Do not
seed the model or harness with a later counterexample or a scenario selected to
recreate a known fix.

## Excluded details

Exclude serialization bytes, TCP framing, metrics, logging text, JMX, command
line handling, authentication, allocation, and numeric representation widths
unless the old source shows that one changes a modeled protocol transition.

## Evidence and output contract

Every modeled action must cite old-source functions or tests. Record important
unchanged producers, consumers, persistence boundaries, and thread boundaries.
Write a complete prior run under `/work/current/.specula-output/`, including:

- `modeling-brief.md` and `analysis-report.md`;
- `spec/base.tla`, `spec/base.cfg`, `spec/MC.tla`, `spec/MC.cfg`,
  `spec/Trace.tla`, `spec/Trace.cfg`, and `spec/instrumentation-spec.md`;
- a runnable baseline harness and at least one fresh nonempty trace;
- SANY, configuration parsing, trace-validation, and bounded TLC logs;
- a provenance manifest listing all inputs, commands, limits, and outcomes.

Do not use external specifications, papers, issue trackers, repository history,
later source trees, or remembered benchmark labels. If the available old source
is insufficient for a faithful model or runnable harness, report the limitation
instead of importing missing semantics from outside the input.
