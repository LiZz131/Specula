# WRaft 回放中出现过的差异

可执行规格是 `spec/MC_for_sandtable*.cfg`。样本在 `sandtable/build/mount/systems/WRaft-series/SpeculaWRaft/bugs/random/`。

## 已收进适配层的

这些在修正 `Sand*` 之后，六种配置各 100 条的变量比较通过。

- 领导者拒绝更高任期的 RequestVote，代码不改 `currentTerm`。驱动没有给领导者推进选举超时。见 `sandtable-instrumentation/examples/wraft.md`。
- 领导者 `raft_end_snapshot` 多发出的 InstallSnapshot 没有进消息袋，`net-len` 比代码少 1。
- `next` 等于快照基址时，模型发出快照之后的全部条目，代码发出空 AppendEntries。深轨迹在第 61 步失败：n2 的日志模型是两条，代码是一条。

响应先更新提交点再发送，也是同一类适配修正。修正前，跟随者看到的 `leaderCommit` 是旧值。

## 环境

`potential-bugs/log-t027-tcp-drop/`。向 n2 投递 n1 的 AppendEntries 时连接断开，n2 的 `commitIdx` 停在 1，模型是 3。`MC.out`、`traces.txt`、`log.host` 都在该目录。

## 比较通过仍然要留的实现差异

`raft_begin_load_snapshot`（`raft_server.c:1383`）把 `current_term` 写成 `last_included_term`，任期可以变小。规格的 `HandleInstallSnapshot` 做了同样的赋值。专用轨迹在 `bugs/term_drop/`：n1 的任期从 2 写成 1。

80 步随机轨迹 `bugs/random/deep3/s001/` 也执行了这一行。该次写入的任期仍是 4，可见状态与模型一致，没有构成新的下降。下降的记录以 `bugs/term_drop/` 为准。

过期领导者那条 11 状态反例违反的是当时过强的 `LeaderCompleteness`，case study 的 bug report 把它标成不变量问题。回放材料若还在 `bugs/stale_leader/`，不要把它当成代码 bug。
