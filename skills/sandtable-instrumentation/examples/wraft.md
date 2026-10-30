# WRaft 上的执行对齐

系统是 willemt/raft。源码在 `<run>/artifact/raft/`。协议文件留在 `spec/base.tla`。可执行副本是 `spec/base_for_sandtable.tla` 和 `spec/MC_for_sandtable.tla`。生成器是 `<run>/sandtable/testcase_generator.py`，驱动改动在 `<run>/sandtable/driver/`。

时钟：`Timeout` 用 2000 ms，`AppendEntriesAll` 用 200 ms。前者是选举超时的推进量，后者是 `request_timeout`。

下面三处是 `Sand*` 相对原动作的执行对齐。原规格里的 bug 注释，包括 `raft_begin_load_snapshot` 把 `current_term` 写成 `last_included_term`，保留在加载快照的公式里。

## 领导者收到 RequestVote

`WRaft.cpp` 在投递 RequestVote 之前，只对非领导者调用 `raft_periodic(election_timeout)`。领导者的 `timeout_elapsed` 因此仍小于选举超时，`raft_recv_requestvote` 在更新任期之前拒绝。`base.tla` 里这条租约拒绝本来就是允许的分支。`SandHandleRequestVoteRequest` 在接收者是 Leader 时回复 not granted，任期不变。跟随者和候选者被驱动推进时钟之后，走 `__should_grant_vote`。

## 快照结束时的发送

`raft_end_snapshot` 在领导者上，向每个 `next_idx < snapshot_last_idx` 的 peer 发 InstallSnapshot。`SandTakeSnapshot` 按 peer 名字顺序把这些消息盖进同一步。跟随者打快照时库直接返回，不发送。

## 空 AppendEntries

`log_get_from_idx` 在 `idx <= base` 时返回 0 条。快照之后 base 就是 `snapshotLastIdx`，所以 `next = snapshotLastIdx` 是一条没有条目的 AppendEntries。`EntriesFrom` 在 `next <= snapshotLastIdx` 时给出空序列。`next < snapshotLastIdx` 的那一支由 `WireMsg` 改成 InstallSnapshot，不使用这段日志。

## AppendEntries 响应里的提交点

`raft_recv_appendentries_response` 先 `raft_set_commit_idx`，再 `raft_send_appendentries`。发出去的 `leader_commit` 是新值。`WireMsg` 带一个提交点参数；成功响应这支传入更新后的值，其余调用点传入当前的 `commitIndex`。
