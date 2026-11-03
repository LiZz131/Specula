# Specula 规格到 SandTable 可执行规格

把已经写好的 Specula 规格变成控制器可以逐条回放的规格。协议公式留在 `<run>/spec/base.tla` 和 `MC.tla`。可执行副本放在本轮目录里。

`<run>` 和 `<ce>` 的定义见 `sandtable-workflow-overview.md`。本轮要改的系统源码、驱动和 SandTable 源码都在 `<ce>` 里。

## 输入 / 输出

**输入**：`<run>/spec/base.tla`、`MC.tla`、`MC.cfg`、每一份 `MC_hunt_*.cfg`，以及被测系统源码。开始时把系统源码拷进 `<ce>/system/`，把正在使用的 SandTable 源码树整份拷进 `<ce>/sandtable/`。之后只改这两份副本，不改上游检出，也不改别的轮次。

**输出**（都在 `<ce>` 里）：

| 文件 | 作用 |
|---|---|
| `spec/base_for_sandtable.tla` | `base.tla` 的副本，加上辅助变量 `scr` 和消息字段 `seq` |
| `spec/MC_for_sandtable.tla` | `MCNext` 含 `Next` 里的每一个 action |
| `spec/MC_for_sandtable.cfg` 及按配置分开的 cfg | 界限与对应的 Specula 配置相同。30 步用 `DepthBound == TLCGet("level") < 31` |
| `sandtable/` 里该系统的驱动 | 为受控执行新增或修改的驱动 |
| `sandtable/testcase_generator.py` | 状态里有 `scr` 时按 `pc` 发命令 |

驱动写在 `<ce>/sandtable/` 里该系统原来的驱动目录。没有这个目录就在副本里建，并在轮次说明里写路径。不在副本外面再留一份。

## 可以改的和要留在原文件里的

`<run>/spec/base.tla`、`MC.tla` 的动作公式保持不动。`<ce>/spec/` 里的新文件可以加辅助状态：`scr.pc`、`scr.nSent`、消息上的 `seq`。这些变量指导生成器，不进入协议不变量。

`MCNext` 包含 `Next` 里的每一个 action，协议更新沿用该 action 的公式。`seq` 等于拦截器的捕获序号。某一个 action 不能因为 stock 驱动没有命令就被删掉或并进另一个 action。

对齐时守三条，都相对「当前这一步的公式」：

1. 公式这一步会发出的消息，在同一步盖上 `seq` 并进入消息袋。实现若额外发出公式这一步没有的字节，这些字节不进入袋子，发送仍返回成功，好让这一步走完。不要把这些字节记成当前 action 的发送，也不要因此从 `Next` 里删掉另一个本来就要单独受控的 action。
2. 这一步走哪条分支，由这一步的 `label` 或步前状态决定。不要把公式改成未改过的驱动碰巧会走的那一条。公式里已经写成偏离的行为留在公式里。和实现不一致时按协议语义归类，不把模型值当成实现应当达到的结果，见 `sandtable-replay` 的 `references/mismatch-record.md`。
3. 持久内容按 `references/controllability.md` 判定，不在这里点名变量。驱动必须把持久内容写到可重读的副本。崩溃留下这份副本。恢复从副本读回，再按公式写易失内容。只改内存、不读副本，不算执行了恢复。

对 `<ce>/sandtable` 和 `<ce>/system` 的修改同时写入 `<ce>/patches/`。步骤见 `references/patches.md`。整棵副本不提交进 case-studies。

## 步骤

1. 复制 `<run>/spec/base.tla` 为 `<ce>/spec/base_for_sandtable.tla`，模块名一并改掉。为模型里的每一个 server 声明一个有名常量。生成器按这个集合把模型节点映射到实现节点。个数等于 server 集合，不默认三个。
2. 增加 `VARIABLE scr`。初始状态把它设为 `[pc |-> <<"Init">>, nSent |-> 0]`。`pc` 让生成器知道刚执行的是哪一个 action，`nSent` 是已经盖过序号的消息条数。
3. 为 `Next` 里的每一个 action 写可执行副本，包括崩溃、恢复、丢失、复制，以及公式里每一个独立的发送。发送时调用统一的盖章公式：`seq` 从 `scr.nSent + 1` 起，按实现的发送顺序递增。字段名必须写成 `"seq" :> n`，单独的 `seq` 是 TLC 运算符。`@@` 保留左边已有的字段，新序号要写在左边。
4. 处理一条消息、丢掉一条、复制一条，都按 `label` 里的序号只动这一条。不要求它是通道上最老的一条，也不要用清空整条通道来丢掉一条。
5. 写 `<ce>/spec/MC_for_sandtable.tla`，`EXTENDS base_for_sandtable`。`MCNext` 的成员见 `references/controllability.md`。计数器只在原规格有对应界限的 action 上增加。
6. 每种 Specula 配置写一份 cfg，规则见 `references/config-mapping.md`。
7. 生成器在 `states[0]` 含有 `scr` 时走 `pc` 路径，否则保留原来的状态差路径，让没有 `scr` 的旧反例还能回放。与协议无关的命令见 `references/pc-seq.md`。某一个系统的命令见 `examples/`。未知的 `pc` 直接失败，不要猜一条命令。
8. 副本相对基线有差异时，按 `references/patches.md` 写 `<ce>/patches/`。回放期间驱动或脚本又改过的，轮次结束时再生成一次。

## Sanitizer 轮次

覆盖率轮次的二进制保持 `--coverage`，不要同时打开 sanitizer。sanitizer 另开一轮次，复用覆盖率轮次已经生成的 `MC.out`，不重新采样。

被测库和驱动加上 `-fsanitize=address,undefined`。启动时设置 `ASAN_OPTIONS=detect_leaks=0`。这一轮不查泄漏。泄漏要查时再另开一轮，并在轮次报告里写明开了泄漏检测。

覆盖率和 sanitizer 的构建产物记在 `<ce>/system/` 和 `<ce>/sandtable/` 里的驱动目录。

有 sanitizer 报告、且当前 label 不是受控的崩溃时，按 `sandtable-replay` 记失败类 `crash`，即使进程退出码是 0。这份 gcda 不并入覆盖率轮次的 `lcov.info`。

## 完成标准

任选一条带 `scr.pc` 的 TLC `-tool` 行为，生成器能写出 `traces.txt`，控制器能把这条轨迹跑到比较点。这一步只证明链路通。一批轨迹是否对齐，交给 `sandtable-replay`。
