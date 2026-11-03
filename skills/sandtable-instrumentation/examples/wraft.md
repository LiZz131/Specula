# willemt/raft 命令对照

节点是模型的 `s1`、`s2`、`s3`，实现名是 `n1`、`n2`、`n3`。选举超时在库里是 `[1000, 2000)` 毫秒。

| pc | 命令 |
|---|---|
| `Init` | `init 3`，每个节点 `net connectall`、`raft init`，然后 `wait-init 3` |
| `Timeout` | 只在该节点上 `intercept inc_time_ms 2000`，再 `raft periodic 2000`。其它动作不再推进时钟 |
| `HandleRequestVoteRequest` | 先 `raft vote-mode lease` 或 `raft vote-mode open`，再按序号投递请求。`lease` 把 `current_leader` 设成自己并把已流逝时间清零；`open` 清掉 `current_leader`。投递前不调用 `raft_periodic` |
| `HandleRequestVoteResponse`、`HandleAppendEntriesRequest`、`HandleAppendEntriesResponse`、`HandleInstallSnapshot` | `deliver-unordered` 该序号，再 `raft recvfrom`。处理请求时库回调里的额外发送不进入消息袋，公式里的那一条回复由驱动在回调之后发出 |
| `ClientRequest` | `raft cli <值>`。库内部随这条命令发出的 AppendEntries 不进入消息袋 |
| `SendAppendEntries`、`SendInstallSnapshot` | `raft send <对端>`。返回 0 或需要快照都算这条公式发送成功 |
| `BroadcastAppendEntries` | 按 `s1`、`s2`、`s3` 的顺序，对 `pc` 里的每个对端各发一次 `raft send` |
| `TakeSnapshot` | `raft snapshot`。快照结束时库自己发出的消息不进入消息袋 |
| `Crash` | `raft crash`：把库回调写过的任期、投票和日志留在磁盘上，停掉进程。这一步不是失败 |
| `Recover` | `raft recover`：只读磁盘上的那份副本，再把角色写成 Follower，`commitIndex` 和 `lastApplied` 写成 0 |
| `LoseMessage` | `drop-unordered`。控制器会把该捕获序号永久标成已丢，所以袋里还有同一公式序号的副本时，丢掉的是复制时新分配的那个捕获序号 |
| `DuplicateMessage` | `duplicate-unordered`。控制器会移动已投递的捕获，同一序号不能投递两次；第二次投递使用复制时新分配的捕获序号 |

`compare variable` 比三个节点的 `commitIndex`、`currentTerm`、`log`、`state`、`lastApplied`、`votedFor`、`votesGranted`、`snapshotLastIdx`、`snapshotLastTerm`、`crashed`、`nextIndex`、`matchIndex`。然后 `compare net-len`。`net-len` 不相等只是警告。
