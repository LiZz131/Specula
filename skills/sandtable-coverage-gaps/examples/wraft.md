# WRaft 未覆盖代码的一次分类

测量来自投票配置的累计 gcov，加上 `bugs/random/deep3/s001/` 那条 80 步轨迹。case study 里的全文是 `未覆盖代码分类.md`。

## 已经补上的 B 类

`raft_begin_load_snapshot`、`raft_end_load_snapshot`、`log_load_from_snapshot` 读写任期、投票、日志、提交点和快照点，对应 `HandleInstallSnapshot`。600 条 30 步轨迹里该 `pc` 一次都没有；InstallSnapshot 在快照步已经进入消息袋。

`MC_for_sandtable_deep` 把上界放到 level 81。种子 1 回放通过。`raft_begin_load_snapshot` 执行 5 次，成功 1 次。`raft_server.c:1383` 的计数是 1，写入的 `last_included_term` 是 4，与当时的任期相同。

函数内部仍有提前返回没走到：index 或任期为 0、低于 `last_applied`、低于当前日志、已经加载过。这些是防御性拒绝，成功路径已经走过。

## 仍重要、模型里已有

`raft_delete_entry_from_idx`、`log_delete`、`raft_pop_log`。AppendEntries 在同一下标发现不同任期时删掉该下标及后缀（`raft_server.c:467` 与 `:495`）。`SandHandleAppendEntriesRequest` 的 `firstConflict` 就是这个守卫。上述 gcov 里调用次数是 0。`Value` 只有 `v1`，冲突只能来自不同任期。下一步是针对该守卫加采样，而不是把函数标成死代码。

## 交给 Specula 的场景

成员变更：`raft_add_non_voting_node`、`raft_remove_node`、投票权变更、`has_sufficient_logs`、addition committed。现有 `Value` 只有普通条目，规格里没有配置变更条目，也没有非投票节点。这些函数读写节点表和投票权。

## 白名单与低优先级

防御性：`raft_cancel_snapshot`；日志环形缓冲的 `mod`，当前日志很短。

销毁与配置：`raft_free`、`log_free`、`raft_node_free`、`log_clear_entries`、`log_empty`、`raft_clear`；`raft_set_heap_functions`、`raft_set_election_timeout`、`raft_set_request_timeout`。驱动在 `raft_new` 里写超时。

驱动没有调用的查询：`raft_get_voted_for`、`raft_get_current_leader`、`raft_get_num_nodes`、`raft_is_follower`、`raft_is_connected`、`raft_get_last_applied_entry`、`raft_node_get_udata`。回放比较的是 `currentTerm`、`log`、`state`、`commitIdx`。
