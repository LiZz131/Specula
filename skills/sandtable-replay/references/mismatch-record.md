# 失败记录

任何失败立刻追加到 `controlled-execution-runs/<轮次>/failures.tsv`，并暂停继续采样。列是：

`配置`、`轨迹`、`种子`、`归类`、`退出码`、`logout`、`变量`、`代码值`、`模型值`、`pc`、`记录目录`

归类只写 `adapter`、`bug`、`environment`、`crash`。

| 归类 | 接着做什么 |
|---|---|
| `adapter` | 模型或 `Sand*`、生成器、驱动和代码对不齐。修好之后新开一轮次。旧轮次的 gcda 不并入。 |
| `bug` | 规格已经描述这条路径，回放仍不一致；或两边一起写成规格标明的偏离。拷贝文件后在同一轮次继续。 |
| `environment` | 这一步没有在节点上执行。修好环境后在同一轮次继续。 |
| `crash` | 没有 `logout`、进程非 0，或容器没有起来。先按上面三类归。归进 `bug` 的继续本轮，其余新开一轮或修好再继续。 |

`net-len` 警告不是失败，不写入这张表。

## 潜在 bug 目录

同一类的每一条轨迹都拷进 `<run>/potential-bugs/<短名>/`。一条一个子目录：

```
potential-bugs/<短名>/
  README.md
  t0158/MC.out
  t0158/traces.txt
  t0158/log.host
  t0130/MC.out
  ...
```

新开一轮次时不要改已经写好的目录。

`README.md` 写五件事：

1. 配置名、每条轨迹的种子和步号。步号用日志里的 `# [k]`。
2. 不一致的变量、节点、代码值、模型值。两边的值都写上。
3. 库里的位置：`artifact/<system>/` 下的文件、函数、行号。
4. 为什么归成实现差异：规格的哪一条公式已经描述了这条路径。
5. 每条轨迹一条复现命令：`run_one_testcase.sh <potential-bugs 里的 MC.out> <节点数>`。写上期望看到的变量名和失败步。

规格保持不动，不用改 `artifact/<system>/` 或驱动去抹平这条记录。交接给 `bug-confirmation` 时带上这个目录。
