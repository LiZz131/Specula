# 覆盖率报告

每种建模配置一个 `controlled-execution-runs/<轮次>/<配置>/coverage.json`。同一配置追加 trace 时往这份文件的数组后面加对象，不另起一份。

## 每条轨迹

| 字段 | 含义 |
|---|---|
| `trace` | `t001` 这种编号 |
| `replay_s` | 这一次 `run_one_testcase.sh` 的墙钟秒数 |
| `ok` | 与 `sandtable-replay` 的变量判决一致 |
| `line_pct` | 累计到本条为止的 Lines executed |
| `branch_taken_pct` | 累计到本条为止的 Taken at least once |
| `files` | 每个源文件的行覆盖、分支覆盖、行数和分支数 |

配置一节再写：轨迹条数、变量一致的条数、墙钟合计、平均、最短、最长、曲线封顶的条数。封顶指行覆盖最后一次上升的那条轨迹。

## 汇总表

配置一行。列：变量一致条数、平均耗时、合计耗时、最终行覆盖、最终分支覆盖、封顶条数。

正文说明行覆盖的分母是被测源文件的可执行行合计，分支覆盖的分母是 gcov 统计的分支数。几个配置的百分比不要加总；gcda 在配置之间清零，百分比是各配置自己的累计。

## 未覆盖清单

`controlled-execution-runs/<轮次>/uncovered.txt` 从各配置已经落盘的 `gcov/*.gcov` 合并而来。一行在任一配置里次数大于 0 就不写入。写入的是次数都为 0 的可执行行，格式 `文件名:行号`。

动作名出现在 `pc` 里，而对应函数仍是 `called 0`，在 `uncovered.txt` 末尾用 `# called 0 <函数名>` 标出。这通常表示发送了消息但没有投递，或 dump 过早。交给 `sandtable-coverage-gaps` 之前先排除 dump 问题。

## 曲线

横轴是该配置内的轨迹条数，纵轴是累计百分比，一条线一个配置。行覆盖和分支覆盖各一张图。正文指出台阶对应的第一种新动作，例如第一次 `TakeSnapshot`。
