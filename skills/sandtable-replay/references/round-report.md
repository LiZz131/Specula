# 轮次报告

每一轮次结束时写 `controlled-execution-runs/<轮次>/轮次报告.md`。这是给人读的全文。明细仍放在旁边的 tsv、lcov 和 `potential-bugs/`，报告里只给计数和路径。

```markdown
# <轮次>

## 启动
挂载盘路径、节点数、`run_round.py` 的参数。采样步数。30 步用 `DepthBound`，加长用 `MC_for_sandtable_deep`。

## 轨迹
每种配置的条数、变量一致条数、墙钟合计。各配置的行覆盖和分支覆盖。写明这些百分比各自从零累计，不能相加。

## 失败
`failures.tsv` 的全表。适配层或模型问题：写修了什么、新轮次的目录名。潜在 bug：链到 `potential-bugs/<短名>/`，并给出每条轨迹的复现命令。崩溃单独列出。

## 并集覆盖率
`lcov.info` 的已执行行 / 全部可执行行。调整后覆盖率见 `未覆盖代码分类.md`。

## 未覆盖
分类计数，以及 `scenarios.md` 里交回 Specula 的场景。下一步是继续在本轮加 trace，还是新开一轮。
```

有未归类的失败时不要写「本轮完成」。
