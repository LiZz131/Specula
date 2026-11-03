# 轮次报告

每一轮次结束时写 `controlled-execution-runs/<轮次>/轮次报告.md`。这是给人读的全文。明细仍放在旁边的 tsv、lcov 和 `potential-bugs/`，报告里只给计数和路径。

```markdown
# <轮次>

## 启动
挂载盘路径、节点数、启动命令。采样步数。30 步用 `DepthBound`，加长用 `MC_for_sandtable_deep`。覆盖率二进制和 sanitizer 二进制分开写。

## 轨迹
每种配置的条数、变量一致条数、墙钟合计。各配置的行覆盖和分支覆盖。写明这些百分比各自从零累计，不能相加。

## 失败
`failures.tsv` 的全表。交出去的这一轮没有 `adapter` 和 `spec`。`adapter`：写修了什么、新轮次的目录名。`bug`：链到 `potential-bugs/<短名>/`，给出每条轨迹的复现命令，写违反的协议规则和协议要求的结果，并写 `KNOWN` 或 `NOT_FOUND` 与链接。模型值不同时注明它不是修补目标。发现过 `spec` 的轮次：链到 `potential-bugs/<短名>/` 和 `<ce>/spec-repairs.md`，写原公式、源码位置、改后的公式，以及重新插桩后的新轮次目录。计划外 `crash` 单独列出。已经改成 `bug` 或 `spec` 的崩溃写在对应类下面，并注明表现是崩溃或 sanitizer。受控的崩溃和恢复成功时不出现在这张表里。

## Sanitizer
若另开了一轮：复用的轨迹目录、`-fsanitize=address,undefined`、`ASAN_OPTIONS=detect_leaks=0`。这一轮的 `crash` 行数。它的 gcda 不并入下面的并集覆盖率。

## 并集覆盖率
`lcov.info` 的已执行行 / 全部可执行行。调整后覆盖率见 `未覆盖代码分类.md`。

## 未覆盖
分类计数，以及 `scenarios.md` 里交回 Specula 的场景。下一步是继续在本轮加 trace，还是新开一轮。

## 补丁
`<ce>/patches/` 里的文件名和基线提交。没有 `system.patch` 时写明被测源码未改。
```

有未归类的失败时不要写「本轮完成」。`failures.tsv` 里还有 `adapter` 或 `spec` 时也不要写「本轮完成」。
