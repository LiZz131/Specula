# MCNext 里留哪些动作

SandTable 控制的是进程边界：按序号投递、虚拟时钟、客户端操作、`clear`。它不控制源码行上的分支。

`MCNext` 只放入 stock 驱动已经有命令的动作。

| 模型动作 | 驱动里有的做法 | 是否进入 MCNext |
|---|---|---|
| 超时并竞选 | `inc_time_ms` 后 `raft periodic` | 进入 |
| 客户端请求 | `raft cli` | 进入 |
| 向所有 peer 发 AppendEntries | 领导者路径上的 `raft periodic` | 进入。这是一次 send-all，不用 `BroadcastLimit` 再数一次 |
| 打快照 | `raft snapshot` | 进入 |
| 处理已捕获的消息 | `deliver-unordered` 后 `raft recvfrom` | 进入 |
| 丢掉一条消息 | `clear src dst` 会丢掉整条 TCP 通道 | 仅当通道上只有这一条时进入 |
| 崩溃、恢复 | 驱动没有重启命令。恢复还会重置易失状态并保留任期、日志和投票 | 留在外面 |
| 复制一条已捕获消息 | 控制器的 `duplicate` 只对 UDP | TCP 系统留在外面 |
| 向任意单个 peer 发送 | 没有对应的 stock 系统调用 | 用 send-all 代替 |

cfg 里可以继续声明原来的 `CrashLimit`、`DuplicateLimit`、`BroadcastLimit`，好让数字和 Specula 文件对照。`MCNext` 不读取这些界限。文档里写明：随机游走探索的是可控制子集，崩溃恢复场景没有执行。

`LoseLimit` 仍然限制丢消息次数。启用条件比原规格更紧，因为 `clear` 不能只删通道中间的一条。
