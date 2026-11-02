# WRaft 上的执行对齐

本文件只记录 willemt/raft。通用规则在 `references/controllability.md` 和 `references/pc-seq.md`：`base.tla` 的每一个 action 单独受控；持久内容由该规格的崩溃与恢复判定；公式这一步没有的发送不进入袋子。

本轮源码在 `<ce>/system/`。协议公式留在 `<run>/spec/base.tla`。可执行副本在 `<ce>/spec/`。驱动和生成器在 `<ce>/sandtable/`。早先轮次写在 `<run>/artifact/raft/` 和 `<run>/sandtable/driver/`，不要按新路径去搬。

这份规格里，崩溃之后恢复仍然保留的是 `currentTerm`、`votedFor`、`log` 和快照。`state`、`commitIndex`、`lastApplied` 按恢复公式重设。驱动必须把前面那一组真正写出去，恢复时从副本读回。不能只在内存里改三个字段。

## 本系统的命令

三个节点时，盖章顺序与库跳过自己之后的发送顺序一致：s1 发往 s2、s3；s2 发往 s1、s3；s3 发往 s1、s2。节点名 `n1 < n2 < n3`。

时钟：`Timeout` 用 2000 ms，广播心跳用 200 ms。前者是选举超时的推进量，后者是 `request_timeout`。

| 模型动作 | 控制 |
|---|---|
| `Timeout` | 非领导者上推进选举超时，再 `raft periodic` |
| `ClientRequest` | `raft cli` |
| `BroadcastAppendEntries` | 领导者上推进请求超时，或一次向公式给出的那些 peer 发送。不要用它代替单播 |
| `SendAppendEntries`、`SendInstallSnapshot` | 向这一个 peer 发送一次。发送函数按步前状态选择哪一种消息 |
| `TakeSnapshot` | `raft snapshot`。这一步把快照元数据写入持久副本 |
| 五个 `Handle*` | 按序号投递这一条，再 `raft recvfrom` |
| `LoseMessage` | 按序号丢掉一条 |
| `DuplicateMessage` | 按序号再放入一份 |
| `Crash` | 停止该节点，持久副本保留 |
| `Recover` | 从副本读回任期、票、日志和快照，再按公式写易失字段 |

## 旧轮次的记录

下面几节是旧轮次把多出来的发送折进 `Sand*` 的记录，不是现行规则。

原规格里的 bug 注释，包括 `raft_begin_load_snapshot` 把 `current_term` 写成 `last_included_term`，保留在加载快照的公式里。

## 领导者收到 RequestVote

`WRaft.cpp` 在投递 RequestVote 之前，只对非领导者调用 `raft_periodic(election_timeout)`。领导者的 `timeout_elapsed` 因此仍小于选举超时，`raft_recv_requestvote` 在更新任期之前拒绝。`base.tla` 里这条租约拒绝本来就是允许的分支。`SandHandleRequestVoteRequest` 在接收者是 Leader 时回复 not granted，任期不变。跟随者和候选者被驱动推进时钟之后，走 `__should_grant_vote`。

## 快照结束时的发送

`raft_end_snapshot` 在领导者上，向每个 `next_idx < snapshot_last_idx` 的 peer 发 InstallSnapshot。`SandTakeSnapshot` 按 peer 名字顺序把这些消息盖进同一步。跟随者打快照时库直接返回，不发送。

## 空 AppendEntries

`log_get_from_idx` 在 `idx <= base` 时返回 0 条。快照之后 base 就是 `snapshotLastIdx`，所以 `next = snapshotLastIdx` 是一条没有条目的 AppendEntries。`EntriesFrom` 在 `next <= snapshotLastIdx` 时给出空序列。`next < snapshotLastIdx` 的那一支由 `WireMsg` 改成 InstallSnapshot，不使用这段日志。

## AppendEntries 响应里的提交点

`raft_recv_appendentries_response` 先 `raft_set_commit_idx`，再 `raft_send_appendentries`。发出去的 `leader_commit` 是新值。`WireMsg` 带一个提交点参数；成功响应这支传入更新后的值，其余调用点传入当前的 `commitIndex`。

覆盖率二进制保持 `--coverage`。sanitizer 是另一轮构建，见 `guide.md` 的 Sanitizer 轮次。不和这份覆盖率二进制混在一起。
