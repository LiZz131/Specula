# pc 与 seq

`scr.pc` 是给生成器的命令元组，第一步是命令名。`seq` 是发送序号，等于拦截器捕获数组的下标加一。

## 序号

同一步里按 peer 名字顺序盖章。节点名 `n1 < n2 < n3` 与库把节点插入数组的顺序一致，也和跳过自己之后的发送顺序一致。三节点时：

| 发送者 | peer 顺序 |
|---|---|
| s1 | s2，s3 |
| s2 | s1，s3 |
| s3 | s1，s2 |

`nSent` 在这一步加上发出的条数。丢消息不增加 `nSent`：`clear` 不从捕获数组里删条目，后面的序号仍然有效。

一条通道上若会一次发出多条，模型里的后续消息必须仍然是该通道上更晚的序号。处理动作的启用条件是：袋里每条同源同宿的消息，序号都大于等于当前这条。

## pc 与命令

生成器用每一步**之后**的状态里的 `pc`。节点名 `sN` 写成 `nN`。

| pc | 控制器命令 |
|---|---|
| `<<"Init">>` | `init`、各节点 `net connectall` 与 `raft init`、`wait-init`、`net isallconnected`，然后一次不带毫秒数的 `raft periodic` |
| `<<"Timeout", i>>` | 对该节点 `intercept inc_time_ms`，再 `raft periodic`。毫秒数取库里选举超时的推进量，让非领导者进入选举 |
| `<<"ClientRequest", i, v>>` | `raft cli` |
| `<<"AppendEntriesAll", i>>` | `raft periodic`，毫秒数取库的 `request_timeout`，使领导者对所有 peer 发送 |
| `<<"TakeSnapshot", i>>` | `raft snapshot` |
| `<<"LoseMessage", src, dst, seq>>` | `clear src dst`。仅当该通道上只有这一条消息时，模型才启用这一步 |
| `<<"Handle…", dst, src, seq>>` | `deliver-unordered src dst seq`，然后循环 `intercept dst check_has_recv_queue src`，再 `execute dst raft recvfrom src` |

时钟推进按节点单独拦截。选举超时和请求超时是两个不同的毫秒数，分别对应 `Timeout` 和 `AppendEntriesAll`。

每步之后生成器对每个节点比较 `commitIdx`、`currentTerm`、`log`、`state`；领导者再比较 `nextIdx` 和 `matchIdx`。然后比较 `net-len`，也就是袋中消息条数。

## 发送折进同一步

库在下面这些时刻会发出模型原动作没有单独列出的消息。可执行动作把它们盖进触发步，peer 顺序与上面的表相同：

- 成为领导者时向所有 peer 发送
- 客户端追加之后，若 `next` 已经追上，向 peer 发送
- AppendEntries 响应处理完后的重试发送。成功路径上，提交点先更新，发出去的 `leaderCommit` 用更新后的值
- `raft_end_snapshot` 在领导者上，向每个 `next_idx < snapshot_last_idx` 的 peer 发送 InstallSnapshot
- 收到 InstallSnapshot 后，驱动总会回一条 AppendEntries 响应

`next_idx < snapshot_last_idx` 时发送的是快照。`next_idx` 等于快照基址时，库的取日志函数返回 0 条，这一步是空的 AppendEntries。`next_idx` 大于基址时，条目从 `next_idx - snapshot_last_idx` 起到日志末尾。
