------------------------------ MODULE Trace ------------------------------
EXTENDS base, Json, IOUtils, SequencesExt

JsonFile ==
    IF "JSON" \in DOMAIN IOEnv THEN IOEnv.JSON
    ELSE "../traces/membership_change_then_acks.ndjson"

TraceRaw == ndJsonDeserialize(JsonFile)
TraceLog == SelectSeq(TraceRaw, LAMBDA line: line.tag = "trace" /\ line.depth = 0)

TraceServer == {"0", "1", "2", "3", "4", "5", "6", "7", "8", "9"}
TraceServerOrder == <<"0", "1", "2", "3", "4", "5", "6", "7", "8", "9">>
TraceAllowedConfigs == {InitialConfig}

VARIABLE l
traceVars == <<vars, l>>

SeqToSet(seq) == {seq[k]: k \in DOMAIN seq}
JsonConfig(configs) == {SeqToSet(configs[k]): k \in DOMAIN configs}
JsonConfigOrInitial(configs) ==
    IF Len(configs) = 0 THEN InitialConfig ELSE JsonConfig(configs)
JsonQS(configs) == IF Len(configs) = 0 THEN NoQS ELSE JsonConfig(configs)

\* Progress values: u64 test values are raw; Option<LogId> values are encoded
\* by base!LV (None = 0). Field "n" (leader node of the log id) is consumed by
\* LogIdNodeConsistent below.
JV(v) ==
    IF v.kind = "raw" THEN v.raw
    ELSE IF v.kind = "log" THEN LV(v.t, v.i)
    ELSE 0

\* The (term,index) encoding drops LogId.leader_id.node_id. A log id of the
\* node's current vote term must have been proposed by the vote's leader node
\* (the only node that appends in that term); checked on every captured value.
LogIdNodeConsistent(v, term, voteNode) ==
    (v.kind = "log" /\ v.t = term) => v.n = voteNode

JsonVec(vec) == [k \in 1..Len(vec) |-> [id |-> vec[k].id, val |-> JV(vec[k].value)]]

\* Bootstrap directly from the implementation's captured pre-state.
InitFromEngineSnapshot(i, snap) ==
    /\ currentTerm = [n \in Server |-> IF n = i THEN snap.term ELSE 0]
    /\ voteFor = [n \in Server |-> IF n = i THEN snap.vote_node ELSE n]
    /\ voteCommitted = [n \in Server |-> IF n = i THEN snap.vote_committed ELSE FALSE]
    /\ role = [n \in Server |-> IF n = i THEN snap.role ELSE "follower"]
    /\ voteGranted = [n \in Server |-> IF n = i THEN SeqToSet(snap.vote_granted) ELSE {}]
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
    /\ leaderSome = [n \in Server |-> IF n = i THEN snap.leader_some ELSE FALSE]
    /\ progVec = [n \in Server |-> IF n = i THEN JsonVec(snap.progress.vector) ELSE <<>>]
    /\ progCommitted = [n \in Server |-> IF n = i THEN JV(snap.progress.committed) ELSE 0]
    /\ progQS = [n \in Server |-> IF n = i THEN JsonQS(snap.progress.qs) ELSE NoQS]
    /\ blankPending = [n \in Server |-> FALSE]

\* Standalone VecProgress fixture (progress::t). Holder slot ev.nid.
InitFromProgress(ev) ==
    /\ currentTerm = [n \in Server |-> 0]
    /\ voteFor = [n \in Server |-> n]
    /\ voteCommitted = [n \in Server |-> FALSE]
    /\ role = [n \in Server |-> "follower"]
    /\ voteGranted = [n \in Server |-> {}]
    /\ lastLog = [n \in Server |-> Nil]
    /\ logTerm = [n \in Server |-> [idx \in 0..MaxIndex |-> 0]]
    /\ committed = [n \in Server |-> Nil]
    /\ matchedIndex = [n \in Server |-> [j \in Server |-> Nil]]
    /\ matchedTerm = [n \in Server |-> [j \in Server |-> 0]]
    /\ committedConfig = [n \in Server |-> InitialConfig]
    /\ effectiveConfig = [n \in Server |-> InitialConfig]
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
    /\ leaderSome = [n \in Server |-> n = ev.nid]
    /\ progVec = [n \in Server |-> IF n = ev.nid THEN JsonVec(ev.pre.vector) ELSE <<>>]
    /\ progCommitted = [n \in Server |-> IF n = ev.nid THEN JV(ev.pre.committed) ELSE 0]
    /\ progQS = [n \in Server |-> IF n = ev.nid THEN JsonQS(ev.pre.qs) ELSE NoQS]
    /\ blankPending = [n \in Server |-> FALSE]

EngineEvents ==
    {"Elect", "LeaderAppend", "FollowerCommit", "UpdateCommittedMembership",
     "UpdateProgress", "UpdateEffectiveMembership", "HandleVoteResp"}
ProgressEvents == {"ProgressUpdate", "ProgressUpgrade"}

TraceInit ==
    /\ Len(TraceLog) > 0
    /\ l = 1
    /\ LET ev == TraceLog[1].event
       IN IF ev.name \in EngineEvents
          THEN InitFromEngineSnapshot(ev.nid, ev.pre)
          ELSE IF ev.name \in ProgressEvents
               THEN InitFromProgress(ev)
               ELSE Init

\* Leader progress (Engine snapshots and standalone progress fixtures).
ProgressPartsMatch(i, pj, vec, pc, qs) ==
    /\ Len(vec[i]) = Len(pj.vector)
    /\ \A k \in 1..Len(pj.vector):
          /\ vec[i][k].id = pj.vector[k].id
          /\ vec[i][k].val = JV(pj.vector[k].value)
    /\ pc[i] = JV(pj.committed)
    /\ qs[i] = JsonQS(pj.qs)

\* Pre-state check for every Engine step: the captured pre-state must equal the
\* replayed state, so chained multi-call fixtures cannot hide unobserved steps.
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
    /\ leaderSome[i] = snap.leader_some
    /\ ProgressPartsMatch(i, snap.progress, progVec, progCommitted, progQS)

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
    /\ leaderSome'[i] = snap.leader_some
    /\ voteGranted'[i] = SeqToSet(snap.vote_granted)
    /\ ProgressPartsMatch(i, snap.progress, progVec', progCommitted', progQS')
    /\ \A k \in 1..Len(snap.progress.vector):
          LogIdNodeConsistent(snap.progress.vector[k].value, snap.term, snap.vote_node)
    /\ LogIdNodeConsistent(snap.progress.committed, snap.term, snap.vote_node)

EngineStep(ev) ==
    /\ EngineSnapshotMatches(ev.nid, ev.pre)
    /\ EngineSnapshotMatchesNext(ev.nid, ev.post)
    /\ l' = l + 1

TraceElect(ev) ==
    /\ ev.name = "Elect"
    /\ StartElection(ev.nid)
    /\ EngineStep(ev)

TraceLeaderAppend(ev) ==
    /\ ev.name = "LeaderAppend"
    /\ LeaderAppendEntries(ev.nid, ev.args.count, ev.args.membership_position,
                           JsonConfigOrInitial(ev.args.membership_configs))
    /\ UNCHANGED blankPending
    /\ EngineStep(ev)

LogIdIndex(v) == IF v.kind = "log" THEN v.i ELSE Nil
LogIdTerm(v) == IF v.kind = "log" THEN v.t ELSE 0

TraceFollowerCommit(ev) ==
    /\ ev.name = "FollowerCommit"
    /\ FollowerCommitEntries(ev.nid,
                             LogIdTerm(ev.args.leader_commit), LogIdIndex(ev.args.leader_commit),
                             LogIdTerm(ev.args.prev_log), LogIdIndex(ev.args.prev_log),
                             LogIdTerm(ev.args.last_entry), LogIdIndex(ev.args.last_entry))
    /\ EngineStep(ev)

TraceUpdateCommittedMembership(ev) ==
    /\ ev.name = "UpdateCommittedMembership"
    /\ UpdateCommittedMembership(ev.nid, ev.args.new_term, ev.args.new_index,
                                 JsonConfig(ev.args.new_configs))
    /\ EngineStep(ev)

TraceUpdateProgress(ev) ==
    /\ ev.name = "UpdateProgress"
    /\ LogIdNodeConsistent(ev.args.value, ev.pre.term, ev.pre.vote_node)
    /\ UpdateProgressAction(ev.nid, ev.args.target, JV(ev.args.value))
    /\ EngineStep(ev)

TraceUpdateEffectiveMembership(ev) ==
    /\ ev.name = "UpdateEffectiveMembership"
    /\ UpdateEffectiveMembershipAction(ev.nid, ev.args.log_index, ev.args.log_term,
                                       JsonConfig(ev.args.configs))
    /\ EngineStep(ev)

TraceProgressUpdate(ev) ==
    /\ ev.name = "ProgressUpdate"
    /\ ProgressPartsMatch(ev.nid, ev.pre, progVec, progCommitted, progQS)
    /\ ProgressUpdateValue(ev.nid, ev.args.target, JV(ev.args.value))
    /\ ProgressPartsMatch(ev.nid, ev.post, progVec', progCommitted', progQS')
    /\ l' = l + 1

TraceProgressUpgrade(ev) ==
    /\ ev.name = "ProgressUpgrade"
    /\ ProgressPartsMatch(ev.nid, ev.pre, progVec, progCommitted, progQS)
    /\ ProgressUpgradeAction(ev.nid, JsonConfig(ev.args.qs))
    /\ ProgressPartsMatch(ev.nid, ev.post, progVec', progCommitted', progQS')
    /\ l' = l + 1

TraceHandleVoteResp(ev) ==
    /\ ev.name = "HandleVoteResp"
    /\ HandleVoteResp(ev.nid, ev.args.target, ev.args.vote.term, ev.args.vote.node,
                      ev.args.vote.committed, ev.args.granted)
    /\ EngineStep(ev)

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
         [] ev.name = "UpdateProgress" -> TraceUpdateProgress(ev)
         [] ev.name = "UpdateEffectiveMembership" -> TraceUpdateEffectiveMembership(ev)
         [] ev.name = "HandleVoteResp" -> TraceHandleVoteResp(ev)
         [] ev.name = "ProgressUpdate" -> TraceProgressUpdate(ev)
         [] ev.name = "ProgressUpgrade" -> TraceProgressUpgrade(ev)
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
