# Instrumentation specification

## 1. Trace event schema

### Envelope

Every emitted line is one compact JSON object followed by `\n`:

```json
{
  "tag": "trace",
  "ts": "<unix-nanoseconds>",
  "event": {
    "name": "<event-name>",
    "nid": 1,
    "before": { "term": 0 },
    "state": { "term": 1 },
    "args": { "incomingTerm": 0 }
  }
}
```

`ts` is a real `SystemTime` value encoded as a decimal string so its width does not affect TLA+ arithmetic. Trace order is file order. A process-wide mutex protects one-line append and flush. Emission is disabled unless `SPECULA_TRACE` names a file and `SPECULA_EVENT_FILTER` contains the event name.

### State fields

Every `before` and `state` object contains the complete field set below.

| JSON field | Implementation source | TLA+ variable |
|---|---|---|
| `term` | `state.vote_ref().leader_id().term()` | `term[nid]` |
| `voteNode` | `state.vote_ref().leader_id().node_id()` | `voteNode[nid]` |
| `voteCommitted` | `state.vote_ref().is_committed()` | `voteCommitted[nid]` |
| `role` | `state.server_state` | `role[nid]` |
| `logLen` | last log index plus one, or zero | `logLen[nid]` |
| `commitLen` | committed log index plus one, or zero | `commitLen[nid]` |
| `candidate` | `candidate_ref().is_some()` | `candidate[nid]` |
| `grants` | `candidate_ref().granters().count()` | `Cardinality(grantSet[nid])` |
| `voters` | effective membership voter count | `voters[nid]` |
| `selfVoter` | effective membership contains local ID | `selfVoter[nid]` |
| `ioAccepted` | accepted IO last-log index plus one | `ioAccepted[nid]` |
| `ioSubmitted` | submitted IO last-log index plus one | `ioSubmitted[nid]` |
| `ioFlushed` | flushed IO last-log index plus one | `ioFlushed[nid]` |
| `ioAcceptedTerm` | accepted IO vote term | `ioAcceptedTerm[nid]` |
| `ioSubmittedTerm` | submitted IO vote term | `ioSubmittedTerm[nid]` |
| `ioFlushedTerm` | flushed IO vote term | `ioFlushedTerm[nid]` |

The trace validator checks every listed post-state field, not only the fields normally changed by an action. `grants` is a cardinality because the generic event schema does not serialize application-defined node IDs; for the one response event, Trace initialization chooses a set of the required size that excludes the new target.

### Argument fields

| JSON field | Meaning | Used by |
|---|---|---|
| `incomingTerm` | term of accepted AppendEntries vote | `EngineAppendEntries` |
| `incomingNode` | node component of accepted vote | `EngineAppendEntries` |
| `entryCount` | input suffix length before Engine filtering | `EngineAppendEntries` |
| `prevLen` | previous log index plus one, or zero | `EngineAppendEntries` |
| `target` | vote-response sender identity | `HandleVoteResponse` |
| `granted` | response grant bit | `HandleVoteResponse` |

Unused arguments are present with zero/false defaults. This keeps one stable schema across events.

## 2. Action-to-code mapping

### `EngineInitializeLogged`

- Spec action: `EngineInitializeLogged`, delegating to `base!EngineInitialize`.
- Baseline code: `openraft/src/engine/engine_impl.rs:190-210`.
- Trigger: capture before `check_initialize`; emit after the internal `elect` returns and before returning `Ok(())`.
- Trace event: `EngineInitialize`.
- Fields: complete before/post Engine snapshot; no nondefault arguments.
- Notes: initialization calls `elect` internally. The harness selects only `EngineInitialize`, so it emits one outer atomic event for this scenario.

### `EngineElectLogged`

- Spec action: `EngineElectLogged`, delegating to `base!EngineElect`.
- Baseline code: `openraft/src/engine/engine_impl.rs:213-233`.
- Trigger: capture on entry; emit after server-state recalculation.
- Trace event: `EngineElect`.
- Fields: complete before/post Engine snapshot; no nondefault arguments.
- Notes: the post-state has an empty candidate grant set. The local grant is a later runtime notification and is modeled separately in ordinary MC.

### `HandleVoteResponseLogged`

- Spec action: `HandleVoteResponseLogged`, delegating to `base!TraceHandleVoteResponse`.
- Baseline code: `openraft/src/engine/engine_impl.rs:340-403` and `:708-735`.
- Trigger: capture on handler entry; emit on the matching granted-response path after optional leader establishment and before return.
- Trace event: `HandleVoteResponse`.
- Fields: complete before/post Engine snapshot plus `target` and `granted`.
- Notes: stale/rejected response branches do not emit this event. The neutral harness exercises a matching quorum-forming response, including the synchronous blank-entry append.

### `EngineAppendEntriesLogged`

- Spec action: `EngineAppendEntriesLogged`, delegating to `base!TraceEngineAppendEntries`.
- Baseline code: `openraft/src/engine/engine_impl.rs:443-457`; state mutation continues in `handler/following_handler/mod.rs:63-173`.
- Trigger: capture before vote validation; emit after prefix validation and append mutation return successfully.
- Trace event: `EngineAppendEntries`.
- Fields: complete before/post Engine snapshot plus incoming term/node, original entry count, and previous-prefix length.
- Notes: rejected vote/prefix paths do not emit. Post-state voter count and local voter bit carry membership effects into the action.

### `IOAcceptLogged`

- Spec action: `IOAcceptLogged`, delegating to `base!IOAccept`.
- Baseline code: `openraft/src/raft_state/io_state/io_progress.rs:86-104`.
- Trigger: snapshot all three cursors on entry; emit immediately after assigning `accepted`.
- Trace event: `IOAccept`.
- Fields: accepted/submitted/flushed before and after; neutral defaults for protocol fields and arguments.
- Notes: the generic IO harness uses the existing `u64` monotonic-progress test so decimal conversion is exact.

### `IOSubmitLogged`

- Spec action: `IOSubmitLogged`, delegating to `base!IOSubmit`.
- Baseline code: `openraft/src/raft_state/io_state/io_progress.rs:106-125`.
- Trigger: snapshot all three cursors on entry; emit immediately after assigning `submitted`.
- Trace event: `IOSubmit`.
- Fields: accepted/submitted/flushed before and after; neutral defaults elsewhere.
- Notes: the action validates that submit does not move ahead of accepted in the concrete trace.

### `IOFlushLogged`

- Spec action: `IOFlushLogged`, delegating to `base!IOFlush`.
- Baseline code: `openraft/src/raft_state/io_state/io_progress.rs:127-190`.
- Trigger: snapshot all three cursors on entry; emit immediately after assigning `flushed`.
- Trace event: `IOFlush`.
- Fields: accepted/submitted/flushed before and after; neutral defaults elsewhere.
- Notes: the chosen monotonic trace advances the cursor. The exact-old method also tolerates completion already covered by a newer cursor.

## 3. Special considerations

### Granularity and filtering

There is a one-to-one relation between the seven event strings and the seven logged actions in `Trace.tla`. Ordinary MC contains additional environmental actions—RPC send/delivery/loss, local persisted-vote response, leader append, commit, crash, and restart—that are intentionally not accepted as silent trace steps. A trace containing an unknown event cannot advance its cursor and fails `TraceMatched`.

The event filter is required because low-level IO progress is used in many tests and because `initialize` invokes `elect`. Each harness case selects only its intended stable boundary, producing deterministic nonempty files without a special protocol schedule.

### Numeric conversion

OpenRaft permits application-defined node and term display types. The probe converts displayed node/term values to `u64`, falling back to zero when not decimal. Therefore this harness is deliberately bound to the exact-old numeric `UTConfig` tests named in `harness/run.sh`; it is not advertised as a universal instrumentation API for arbitrary user configs.

Generic IO events stringify the progress value and parse it as `u64`. Their protocol fields are neutral placeholders because `IOProgress<T>` alone has no Engine/node context. The selected `test_monotonic_updates` uses `u64` and validates only the generic IO action sequence.

### Intrusiveness and failure behavior

The probe uses only the Rust standard library and adds no Cargo dependency or feature. It writes only when both environment variables enable an event. Write/open errors are ignored so instrumentation cannot change a protocol result. The output mutex may serialize selected probe writes but does not add a lock when tracing is disabled beyond the environment check.

### Reproduction artifacts

- Apply script: `/work/prior/.specula-output/harness/apply.sh`
- Exact baseline patch: `/work/prior/.specula-output/harness/patches/instrumentation.patch`
- Probe source copy: `/work/prior/.specula-output/harness/src/specula_trace.rs`
- Trace collector: `/work/prior/.specula-output/harness/run.sh`
- Trace-first validator: `/work/prior/.specula-output/harness/validate.sh`
