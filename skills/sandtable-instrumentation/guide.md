# Specula 规格到 SandTable 可执行规格

把已经写好的 Specula 规格变成控制器可以逐条回放的规格。协议公式留在原来的 `base.tla` 和 `MC.tla`。可执行副本放在新文件里。

## 输入 / 输出

**输入**：`base.tla`、`MC.tla`、标准 `MC.cfg`、每一份 `MC_hunt_*.cfg`，以及目标系统在 SandTable 里的 stock 驱动命令。

**输出**：

| 文件 | 作用 |
|---|---|
| `base_for_sandtable.tla` | `base.tla` 的副本，加上辅助变量 `scr` 和消息字段 `seq` |
| `MC_for_sandtable.tla` | `MCNext` 只含驱动能执行的 `Sand*` 动作 |
| `MC_for_sandtable.cfg` 及每种建模配置一份 cfg | 界限与对应的 Specula 配置相同 |
| 生成器 | 状态里有 `scr` 时按 `pc` 发命令 |

## 可以改的和要留在原文件里的

`base.tla`、`MC.tla` 的动作公式保持不动。新文件可以加辅助状态：`scr.pc`、`scr.nSent`、消息上的 `seq`。这些变量指导生成器，不进入协议不变量。

`Sand*` 动作里的协议更新沿用原动作的公式。执行上需要两处对齐，使 `seq` 等于拦截器的捕获序号，并使回放和未改动的库比较相等：

1. 同一次发送系统调用发出的消息，在同一步里盖上 `seq` 并记入消息袋。代码在成为领导者、追上的客户端追加、响应重试、快照结束时额外发出的消息，折进触发它们的那一步。
2. 原规格用非确定性概括的地方，`Sand*` 走 stock 驱动实际会走的那条控制流。原规格已经写成 bug 的偏离保留在公式里，不用可执行副本来把它抹平。分歧怎么归类见 `sandtable-replay`。

被测源码和 SandTable 驱动保持仓库原样。需要改源码才能对齐时，写出报告并停下来等审阅。

## 步骤

1. 复制 `base.tla` 为 `base_for_sandtable.tla`，模块名一并改掉。声明节点常量（`s1`、`s2`、`s3`），使生成器能把模型节点固定映射到 `n1`、`n2`、`n3`。
2. 增加 `VARIABLE scr`。`SandInit` 把它设为 `[pc |-> <<"Init">>, nSent |-> 0]`。
3. 为每个要回放的动作写 `Sand*`。发送时调用统一的盖章公式：`seq` 从 `scr.nSent + 1` 起，按 peer 名字顺序递增。字段名必须写成 `"seq" :> n`，单独的 `seq` 是 TLC 运算符。
4. 处理动作只在该消息是此 TCP 通道上最老的一条时启用。`deliver-unordered` 按序号投递指定消息，但按队列计数弹出队首；通道上必须保持 FIFO，序号才不会和队列错位。
5. 写 `MC_for_sandtable.tla`，`EXTENDS base_for_sandtable`。`MCNext` 的成员见 `references/controllability.md`。计数器只在原规格有对应界限的动作上增加。
6. 每种 Specula 配置写一份 cfg，规则见 `references/config-mapping.md`。
7. 生成器在 `states[0]` 含有 `scr` 时走 `pc` 路径，否则保留原来的状态差路径，让没有 `scr` 的旧反例还能回放。`pc` 到命令的对照见 `references/pc-seq.md`。未知的 `pc` 直接失败，不要猜一条命令。

## 完成标准

任选一条带 `scr.pc` 的 TLC `-tool` 行为，生成器能写出 `traces.txt`，控制器能把这条轨迹跑到比较点。这一步只证明链路通。一批轨迹是否对齐，交给 `sandtable-replay`。
