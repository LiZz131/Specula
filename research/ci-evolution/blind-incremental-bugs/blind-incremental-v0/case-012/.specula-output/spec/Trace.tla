------------------------------ MODULE Trace ------------------------------
EXTENDS base, Json, IOUtils, SequencesExt

JsonFile ==
    IF "JSON" \in DOMAIN IOEnv THEN IOEnv.JSON
    ELSE "../traces/leader_append.ndjson"

TraceRaw == ndJsonDeserialize(JsonFile)
TraceLog == SelectSeq(TraceRaw, LAMBDA line: line.tag = "trace")

TraceServer == {"0", "1", "2", "3", "4", "5", "6", "7", "8"}
TraceAllowedConfigs == {InitialConfig}

VARIABLE l
traceVars == <<vars, l>>

SeqToSet(seq) == {seq[k]: k \in DOMAIN seq}
JsonConfig(configs) == {SeqToSet(configs[k]): k \in DOMAIN configs}
JsonConfigOrInitial(configs) ==
    IF Len(configs) = 0 THEN InitialConfig ELSE JsonConfig(configs)

ValueFor(values, id, default) ==
    IF \E k \in DOMAIN values: values[k].id = id
    THEN LET chosen == CHOOSE k \in DOMAIN values: values[k].id = id
         IN values[chosen].value
    ELSE default

MaxValue(values) ==
    CHOOSE v \in {values[k].value: k \in DOMAIN values}:
        \A k \in DOMAIN values: values[k].value <= v

EngineEvents ==
    {"Elect", "LeaderAppend", "FollowerCommit", "UpdateCommittedMembership"}

\* Bootstrap directly from the implementation's captured pre-state. This is
\* stronger than assuming the unit test's hand-built fixture equals base Init.
InitFromEngineSnapshot(i, snap) ==
    /\ currentTerm = [n \in Server |-> IF n = i THEN snap.term ELSE 0]
    /\ voteFor = [n \in Server |-> IF n = i THEN snap.vote_node ELSE n]
    /\ voteCommitted = [n \in Server |-> IF n = i THEN snap.vote_committed ELSE FALSE]
    /\ role = [n \in Server |-> IF n = i THEN snap.role ELSE "follower"]
    /\ voteGranted = [n \in Server |-> {}]
    /\ lastLog = [n \in Server |-> IF n = i THEN snap.last_log ELSE Nil]
    /\ logTerm = [n \in Server |->
          [idx \in 0..MaxIndex |->
             IF n = i /\ idx <= snap.last_log
             THEN snap.logs[idx + 1]
             ELSE 0]]
    /\ committed = [n \in Server |-> IF n = i THEN snap.committed ELSE Nil]
    /\ matchedIndex = [n \in Server |-> [j \in Server |-> Nil]]
    /\ matchedTerm = [n \in Server |-> [j \in Server |-> 0]]
    /\ committedConfig = [n \in Server |->
          IF n = i THEN JsonConfigOrInitial(snap.committed_configs) ELSE InitialConfig]
    /\ effectiveConfig = [n \in Server |->
          IF n = i THEN JsonConfigOrInitial(snap.effective_configs) ELSE InitialConfig]
    /\ committedMembershipIndex = [n \in Server |->
          IF n = i THEN snap.committed_mem_index ELSE Nil]
    /\ committedMembershipTerm = [n \in Server |->
          IF n = i THEN snap.committed_mem_term ELSE 0]
    /\ effectiveMembershipIndex = [n \in Server |->
          IF n = i THEN snap.effective_mem_index ELSE Nil]
    /\ effectiveMembershipTerm = [n \in Server |->
          IF n = i THEN snap.effective_mem_term ELSE 0]
    /\ messages = {}
    /\ crashed = {}
    /\ witnessIndex = [n \in Server |-> Nil]
    /\ witnessNodes = [n \in Server |-> {}]
    /\ witnessConfig = [n \in Server |-> InitialConfig]
    /\ witnessTerm = [n \in Server |-> 0]

InitFromProgress(ev) ==
    /\ currentTerm = [n \in Server |-> IF n = ev.nid THEN 1 ELSE 0]
    /\ voteFor = [n \in Server |-> n]
    /\ voteCommitted = [n \in Server |-> FALSE]
    /\ role = [n \in Server |-> "follower"]
    /\ voteGranted = [n \in Server |-> {}]
    /\ lastLog = [n \in Server |-> IF n = ev.nid THEN MaxIndex ELSE Nil]
    /\ logTerm = [n \in Server |->
          [idx \in 0..MaxIndex |-> IF n = ev.nid THEN 1 ELSE 0]]
    /\ committed = [n \in Server |-> IF n = ev.nid THEN ev.pre_committed ELSE Nil]
    /\ matchedIndex = [n \in Server |->
          [j \in Server |-> IF n = ev.nid THEN ValueFor(ev.pre_values, j, Nil) ELSE Nil]]
    /\ matchedTerm = [n \in Server |->
          [j \in Server |-> IF n = ev.nid /\ ValueFor(ev.pre_values, j, Nil) # Nil
                              THEN 1 ELSE 0]]
    /\ committedConfig = [n \in Server |->
          IF n = ev.nid THEN JsonConfig(ev.configs) ELSE InitialConfig]
    /\ effectiveConfig = [n \in Server |->
          IF n = ev.nid THEN JsonConfig(ev.configs) ELSE InitialConfig]
    /\ committedMembershipIndex = [n \in Server |-> Nil]
    /\ committedMembershipTerm = [n \in Server |-> 0]
    /\ effectiveMembershipIndex = [n \in Server |-> Nil]
    /\ effectiveMembershipTerm = [n \in Server |-> 0]
    /\ messages = {}
    /\ crashed = {}
    /\ witnessIndex = [n \in Server |-> Nil]
    /\ witnessNodes = [n \in Server |-> {}]
    /\ witnessConfig = [n \in Server |-> InitialConfig]
    /\ witnessTerm = [n \in Server |-> 0]

TraceInit ==
    /\ Len(TraceLog) > 0
    /\ l = 1
    /\ LET ev == TraceLog[1].event
       IN IF ev.name \in EngineEvents
          THEN InitFromEngineSnapshot(ev.nid, ev.pre)
          ELSE IF ev.name = "ProgressUpdate"
               THEN InitFromProgress(ev)
               ELSE Init

EngineSnapshotMatches(i, snap) ==
    /\ currentTerm[i] = snap.term
    /\ voteFor[i] = snap.vote_node
    /\ voteCommitted[i] = snap.vote_committed
    /\ role[i] = snap.role
    /\ lastLog[i] = snap.last_log
    /\ committed[i] = snap.committed
    /\ committedMembershipIndex[i] = snap.committed_mem_index
    /\ committedMembershipTerm[i] = snap.committed_mem_term
    /\ effectiveMembershipIndex[i] = snap.effective_mem_index
    /\ effectiveMembershipTerm[i] = snap.effective_mem_term
    /\ committedConfig[i] = JsonConfigOrInitial(snap.committed_configs)
    /\ effectiveConfig[i] = JsonConfigOrInitial(snap.effective_configs)
    /\ \A idx \in 0..snap.last_log: logTerm[i][idx] = snap.logs[idx + 1]

ProgressMatches(ev) ==
    /\ committed[ev.nid] = ev.post_committed
    /\ \A k \in DOMAIN ev.post_values:
          matchedIndex[ev.nid][ev.post_values[k].id] = ev.post_values[k].value

EngineSnapshotMatchesNext(i, snap) ==
    /\ currentTerm'[i] = snap.term
    /\ voteFor'[i] = snap.vote_node
    /\ voteCommitted'[i] = snap.vote_committed
    /\ role'[i] = snap.role
    /\ lastLog'[i] = snap.last_log
    /\ committed'[i] = snap.committed
    /\ committedMembershipIndex'[i] = snap.committed_mem_index
    /\ committedMembershipTerm'[i] = snap.committed_mem_term
    /\ effectiveMembershipIndex'[i] = snap.effective_mem_index
    /\ effectiveMembershipTerm'[i] = snap.effective_mem_term
    /\ committedConfig'[i] = JsonConfigOrInitial(snap.committed_configs)
    /\ effectiveConfig'[i] = JsonConfigOrInitial(snap.effective_configs)
    /\ \A idx \in 0..snap.last_log: logTerm'[i][idx] = snap.logs[idx + 1]

ProgressMatchesNext(ev) ==
    /\ committed'[ev.nid] = ev.post_committed
    /\ \A k \in DOMAIN ev.post_values:
          matchedIndex'[ev.nid][ev.post_values[k].id] = ev.post_values[k].value

TraceElect(ev) ==
    /\ ev.name = "Elect"
    /\ StartElection(ev.nid)
    /\ EngineSnapshotMatchesNext(ev.nid, ev.post)
    /\ l' = l + 1

TraceLeaderAppend(ev) ==
    /\ ev.name = "LeaderAppend"
    /\ LeaderAppendEntries(ev.nid, ev.args.count, ev.args.membership_position,
                           JsonConfig(ev.post.effective_configs))
    /\ EngineSnapshotMatchesNext(ev.nid, ev.post)
    /\ l' = l + 1

TraceFollowerCommit(ev) ==
    /\ ev.name = "FollowerCommit"
    /\ FollowerCommitEntries(ev.nid,
                             ev.args.leader_commit_term, ev.args.leader_commit,
                             ev.args.prev_log_term, ev.args.prev_log,
                             ev.args.last_entry_term, ev.args.last_entry)
    /\ EngineSnapshotMatchesNext(ev.nid, ev.post)
    /\ l' = l + 1

TraceUpdateCommittedMembership(ev) ==
    /\ ev.name = "UpdateCommittedMembership"
    /\ UpdateCommittedMembership(ev.nid, ev.args.new_term, ev.args.new_index,
                                 JsonConfig(ev.args.new_configs))
    /\ EngineSnapshotMatchesNext(ev.nid, ev.post)
    /\ l' = l + 1

TraceProgressUpdate(ev) ==
    /\ ev.name = "ProgressUpdate"
    /\ ProgressUpdateValue(ev.nid, ev.args.target, ev.args.value)
    /\ ProgressMatchesNext(ev)
    /\ l' = l + 1

ValueQuorum(configs, values, threshold) ==
    \A group \in configs:
        2 * Cardinality({id \in group: ValueFor(values, id, Nil) >= threshold})
        > Cardinality(group)

ExpectedGreatest(configs, values) ==
    LET candidates == {values[k].value: k \in DOMAIN values}
        valid == {v \in candidates: ValueQuorum(configs, values, v)}
    IN IF valid = {}
       THEN Nil
       ELSE CHOOSE v \in valid: \A other \in valid: other <= v

TraceGreatestMajority(ev) ==
    /\ ev.name = "GreatestMajority"
    /\ ev.result = ExpectedGreatest(JsonConfig(ev.configs), ev.values)
    /\ UNCHANGED vars
    /\ l' = l + 1

TraceQuorumCheck(ev) ==
    /\ ev.name = "QuorumCheck"
    /\ ev.result = Quorum(JsonConfig(ev.configs), SeqToSet(ev.granted))
    /\ UNCHANGED vars
    /\ l' = l + 1

TraceReplicationLagCheck(ev) ==
    /\ ev.name = "ReplicationLagCheck"
    /\ ev.result = (ev.last_index - ev.matched_index <= ev.threshold)
    /\ UNCHANGED vars
    /\ l' = l + 1

TraceStep ==
    LET ev == TraceLog[l].event
    IN CASE ev.name = "Elect" -> TraceElect(ev)
         [] ev.name = "LeaderAppend" -> TraceLeaderAppend(ev)
         [] ev.name = "FollowerCommit" -> TraceFollowerCommit(ev)
         [] ev.name = "UpdateCommittedMembership" -> TraceUpdateCommittedMembership(ev)
         [] ev.name = "ProgressUpdate" -> TraceProgressUpdate(ev)
         [] ev.name = "GreatestMajority" -> TraceGreatestMajority(ev)
         [] ev.name = "QuorumCheck" -> TraceQuorumCheck(ev)
         [] ev.name = "ReplicationLagCheck" -> TraceReplicationLagCheck(ev)
         [] OTHER -> FALSE

TraceNext ==
    \/ /\ l <= Len(TraceLog)
       /\ TraceStep
    \/ /\ l > Len(TraceLog)
       /\ UNCHANGED traceVars

TraceMatched == <>(l > Len(TraceLog))

TraceSpec == TraceInit /\ [][TraceNext]_traceVars /\ WF_traceVars(TraceNext)

=============================================================================
