`repro-ack-before-fsync-1.ndjson`: emitted by `harness/repro/AckBeforeFsyncReproTest` (MC-1).
The run injects a stalled, then failing, txn-log append on followers (slow disk + crash before
the write).  The reference model represents that fault only as `Crash`, so this trace is kept
as raw evidence and is not part of the conformance suite.
