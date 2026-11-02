# 配置映射

每一份要随机游走的 Specula 配置，对应一份 SandTable cfg。标准收敛用 `MC.cfg`，每种 hunt 用对应的 `MC_hunt_*.cfg`。界限数字保持原样。`MCNext` 里的 action 继续受这些界限约束。

## 必须改的 cfg 项

- `SPECIFICATION` 指向 `MC_for_sandtable` 的 `MCSpec`。
- 规格是 `MCInit /\ [][MCNext]_<<allVars, scr, mcVars>>`。下标带上 `scr` 和计数器，避免只改辅助变量的一步被当成 stutter。
- 节点常量写成有名常数，个数等于模型的 server，不默认三个。对称归约会把模型节点置换离开实现节点，回放时去掉 `SYMMETRY`。
- 保留 `CONSTRAINT MsgBufferConstraint`。
- 原配置里的不变量照抄。`CountersOK` 若引用了可执行模块里没有的计数器，从 cfg 删掉这一条，避免 TLC 报未知运算符。
- 增加 `DepthBound == TLCGet("level") < N`，并放进 `INVARIANTS`。模拟在违反它时停下，`-tool` 会打印到此为止的行为。level 1 是初始状态，`N = 31` 表示最多 30 步。

`DepthBound` 是采样截断，放在可执行模块里。要看更长的行为时另写一个模块，只把上界加大，cfg 改查新的上界，原来的 30 步配置不动。

## 不变量与性质

安全性不变量可以留在 cfg 里。模拟过程中若真的违反安全性，退出码同样是 12，要用 TLC 打印的「哪一条不变量被违反」把深度截断和真反例分开。

时序性质沿用原模块的写法。下标用协议变量 `allVars`，这样只改 `scr` 或计数器的一步对该性质是 stutter。
