# WRaft 行分类示例

用来对照未覆盖行的集合，不是某一轮次的全表。全表写在 `controlled-execution-runs/<轮次>/行分类.tsv`。次数大于 0 的行不出现在表里。

| 行 | 集合 | 依据 |
|---|---|---|
| `raft_server.c:1383` `current_term = last_included_term` | A | 改写任期。动作是 `HandleInstallSnapshot`。30 步里消息在袋中但处理步来不及，下一步加长 `DepthBound`。 |
| `raft_server.c:467` 从 `prev_log_idx` 删后缀 | A | 改写日志。守卫是 `log` 与 `commitIndex` 上的谓词。采样没走到不等于死代码。 |
| `raft_begin_load_snapshot` 里低于 `last_applied` 的 `return -1` | B | 防御性，守卫能写成 `lastApplied` 上的谓词。 |
| 与已提交条目冲突时的 `RAFT_ERR_SHUTDOWN` | B | 只读 `commitIndex` 后错误返回。TLC 应找这条守卫，看拒绝是否掩盖了规格允许的状态。 |
| `__ensurecapacity` 的扩容 | B | 不改写 spec 变量。`Len(log)` 超过缓冲容量可以写成谓词。`MaxLogLength = 4` 时装不满，要换更大的常量配置，而不是在原配置上加 trace。 |
| `assert(node != NULL)` | C | 防御性，写不出 spec 谓词。 |
| `raft_free`、`log_free`、`raft_clear` | D | 销毁。可能有泄漏，本次不采样。 |
| `raft_set_election_timeout`、驱动不调用的 `raft_get_voted_for` | D | 配置或未使用的查询。驱动在 `raft_new` 里写超时；回放比较的是 `currentTerm`、`log`、`state`。 |
| `raft_add_non_voting_node`、`raft_remove_node`、投票权变更 | E | 现有 `Value` 没有配置条目，规格没有非投票节点。交给 `spec_generation`。 |
