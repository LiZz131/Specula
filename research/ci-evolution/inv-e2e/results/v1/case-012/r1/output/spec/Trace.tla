------------------------------ MODULE Trace ------------------------------
EXTENDS base, Json, IOUtils, SequencesExt

JsonFile ==
    IF "JSON" \in DOMAIN IOEnv THEN IOEnv.JSON
    ELSE "../traces/leader_append.ndjson"

TraceRaw == ndJsonDeserialize(JsonFile)
TraceLog == SelectSeq(TraceRaw, LAMBDA line: line.tag = "trace")

\* Unit fixtures use u64 node ids 0..9 rendered as strings; single-digit
\* strings sort exactly like the numeric ids, matching BTreeSet order.
TraceServer == {"0", "1", "2", "3", "4", "5", "6", "7", "8", "9"}
TraceServerOrder == <<"0", "1", "2", "3", "4", "5", "6", "7", "8", "9">>
TraceAllowedConfigs == {InitialConfig}

VARIABLE l
traceVars == <<vars, l>>

SeqToSet(seq) == {seq[k]: k \in DOMAIN seq}
JsonConfig(configs) == {SeqToSet(configs[k]): k \in DOMAIN configs}
JsonConfigOrInitial(configs) ==
    IF Len(configs) = 0 THEN InitialConfig ELSE JsonConfig(configs)

\* {"term": t, "index": i} -> <<t, i>>; None is {"term":0,"index":-1}.
JLog(r) == <<r.term, r.index>>

\* A VecProgress captured by the probes: quorum-set groups, the vector in its
\* real order (id, term, index), and VecProgress.committed.
JsonProgress(cfgs, vector, comm) ==
    [cfg |-> JsonConfig(cfgs),
     order |-> [k \in DOMAIN vector |-> vector[k].id],
     val |-> [j \in Server |->
                IF \E k \in DOMAIN vector: vector[k].id = j
                THEN LET k0 == CHOOSE k \in DOMAIN vector: vector[k].id = j
                     IN JLog(vector[k0])
                ELSE NoLog],
     committed |-> JLog(comm)]

SnapProgress(snap) ==
    IF snap.leader_active
    THEN JsonProgress(snap.progress_configs, snap.progress_vector,
                      snap.progress_committed)
    ELSE NoProgress

EngineEvents ==
    {"Elect", "HandleVoteResp", "LeaderAppend", "FollowerCommit", "UpdateCommittedMembership",
     "UpdateProgress", "UpdateEffectiveMembership"}

EngineLines == {k \in DOMAIN TraceLog : TraceLog[k].event.name \in EngineEvents}
FirstEngineLine ==
    IF EngineLines = {} THEN 0
    ELSE CHOOSE k \in EngineLines: \A k2 \in EngineLines: k <= k2

\* Bootstrap directly from the implementation's captured pre-state of the first
\* Engine event.  Pure helper events (VecProgress, quorum, lag) leave protocol
\* state unchanged, so traces made only of them start from Init.
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
    /\ leaderActive = [n \in Server |-> IF n = i THEN snap.leader_active ELSE FALSE]
    /\ progress = [n \in Server |-> IF n = i THEN SnapProgress(snap) ELSE NoProgress]
    \* Membership payloads of the captured log: the effective and committed
    \* membership entries (other entries' payloads are not captured).
    /\ logConfig = [n \in Server |->
          [k \in 0..MaxIndex |->
             IF n = i /\ k = snap.effective_mem_index
             THEN JsonConfigOrInitial(snap.effective_configs)
             ELSE IF n = i /\ k = snap.committed_mem_index
                  THEN JsonConfigOrInitial(snap.committed_configs)
                  ELSE {}]]

TraceInit ==
    /\ Len(TraceLog) > 0
    /\ l = 1
    /\ IF FirstEngineLine > 0
       THEN LET ev == TraceLog[FirstEngineLine].event
            IN InitFromEngineSnapshot(ev.nid, ev.pre)
       ELSE Init

\* Post-state comparison of every captured Engine field, including the Engine
\* leader state and the complete VecProgress (order, values, committed).
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
    /\ leaderActive'[i] = snap.leader_active
    /\ progress'[i] = SnapProgress(snap)
    /\ snap.leader_active => voteGranted'[i] = SeqToSet(snap.vote_granted)

\* Pre-state agreement at every Engine event (catches drift between events).
EngineSnapshotMatches(i, snap) ==
    /\ currentTerm[i] = snap.term
    /\ voteFor[i] = snap.vote_node
    /\ voteCommitted[i] = snap.vote_committed
    /\ role[i] = snap.role
    /\ lastLog[i] = snap.last_log
    /\ committed[i] = snap.committed
    /\ committedMembershipIndex[i] = snap.committed_mem_index
    /\ effectiveMembershipIndex[i] = snap.effective_mem_index
    /\ committedConfig[i] = JsonConfigOrInitial(snap.committed_configs)
    /\ effectiveConfig[i] = JsonConfigOrInitial(snap.effective_configs)
    /\ leaderActive[i] = snap.leader_active
    /\ progress[i] = SnapProgress(snap)

TraceElect(ev) ==
    /\ ev.name = "Elect"
    /\ EngineSnapshotMatches(ev.nid, ev.pre)
    /\ StartElection(ev.nid)
    /\ EngineSnapshotMatchesNext(ev.nid, ev.post)
    /\ l' = l + 1

TraceHandleVoteResp(ev) ==
    /\ ev.name = "HandleVoteResp"
    /\ EngineSnapshotMatches(ev.nid, ev.pre)
    /\ HandleVoteResp(ev.nid, ev.args.target, ev.args.resp_term, ev.args.resp_node,
                      ev.args.resp_committed, ev.args.granted)
    /\ EngineSnapshotMatchesNext(ev.nid, ev.post)
    /\ l' = l + 1

TraceLeaderAppend(ev) ==
    /\ ev.name = "LeaderAppend"
    /\ EngineSnapshotMatches(ev.nid, ev.pre)
    /\ LeaderAppendEntries(ev.nid, ev.args.count, ev.args.membership_position,
                           JsonConfig(ev.post.effective_configs))
    /\ EngineSnapshotMatchesNext(ev.nid, ev.post)
    /\ l' = l + 1

TraceFollowerCommit(ev) ==
    /\ ev.name = "FollowerCommit"
    /\ EngineSnapshotMatches(ev.nid, ev.pre)
    /\ FollowerCommitEntries(ev.nid,
                             ev.args.leader_commit_term, ev.args.leader_commit,
                             ev.args.prev_log_term, ev.args.prev_log,
                             ev.args.last_entry_term, ev.args.last_entry)
    /\ EngineSnapshotMatchesNext(ev.nid, ev.post)
    /\ l' = l + 1

TraceUpdateCommittedMembership(ev) ==
    /\ ev.name = "UpdateCommittedMembership"
    /\ EngineSnapshotMatches(ev.nid, ev.pre)
    /\ UpdateCommittedMembership(ev.nid, ev.args.new_term, ev.args.new_index,
                                 JsonConfig(ev.args.new_configs))
    /\ EngineSnapshotMatchesNext(ev.nid, ev.post)
    /\ l' = l + 1

TraceUpdateProgress(ev) ==
    /\ ev.name = "UpdateProgress"
    /\ EngineSnapshotMatches(ev.nid, ev.pre)
    /\ UpdateProgress(ev.nid, ev.args.target, JLog(ev.args))
    /\ EngineSnapshotMatchesNext(ev.nid, ev.post)
    /\ l' = l + 1

TraceUpdateEffectiveMembership(ev) ==
    /\ ev.name = "UpdateEffectiveMembership"
    /\ EngineSnapshotMatches(ev.nid, ev.pre)
    /\ UpdateEffectiveMembership(ev.nid, ev.args.term, ev.args.index,
                                 JsonConfig(ev.args.configs))
    /\ EngineSnapshotMatchesNext(ev.nid, ev.post)
    /\ l' = l + 1

\* Pure VecProgress::update relation over the real vector order.
TraceProgressUpdate(ev) ==
    /\ ev.name = "ProgressUpdate"
    /\ VecUpdate(JsonProgress(ev.configs, ev.pre_vector, ev.pre_committed),
                 ev.args.target, JLog(ev.args))
       = JsonProgress(ev.configs, ev.post_vector, ev.post_committed)
    /\ UNCHANGED vars
    /\ l' = l + 1

\* Pure VecProgress::upgrade_quorum_set relation.
TraceProgressUpgrade(ev) ==
    /\ ev.name = "ProgressUpgrade"
    /\ UpgradeQuorumSetD(JsonProgress(ev.configs, ev.pre_vector, ev.pre_committed),
                         JsonConfig(ev.new_configs), JLog(ev.default))
       = JsonProgress(ev.new_configs, ev.post_vector, ev.post_committed)
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

\* GreatestMajority (V0) is not accepted: Membership::greatest_majority_value
\* was deleted by the update (membership/membership.rs, old lines 271-307).
TraceStep ==
    LET ev == TraceLog[l].event
    IN CASE ev.name = "Elect" -> TraceElect(ev)
         [] ev.name = "HandleVoteResp" -> TraceHandleVoteResp(ev)
         [] ev.name = "LeaderAppend" -> TraceLeaderAppend(ev)
         [] ev.name = "FollowerCommit" -> TraceFollowerCommit(ev)
         [] ev.name = "UpdateCommittedMembership" -> TraceUpdateCommittedMembership(ev)
         [] ev.name = "UpdateProgress" -> TraceUpdateProgress(ev)
         [] ev.name = "UpdateEffectiveMembership" -> TraceUpdateEffectiveMembership(ev)
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
