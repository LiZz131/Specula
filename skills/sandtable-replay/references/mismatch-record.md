# 失败记录

任何失败立刻追加到 `controlled-execution-runs/<轮次>/failures.tsv`，并通知。列是：

`配置`、`轨迹`、`种子`、`归类`、`退出码`、`logout`、`变量`、`代码值`、`模型值`、`pc`、`记录目录`

归类只写 `adapter`、`bug`、`environment`、`crash`。`crash` 是终态，不改写成另外三档。

| 归类 | 接着做什么 |
|---|---|
| `adapter` | 模型或 `Sand*`、生成器、驱动和代码对不齐。通知并停。修好之后新开一轮次。旧轮次的 gcda 不并入。不查上游 issue。 |
| `bug` | 规格已经描述这条路径，回放仍不一致；或两边一起写成规格标明的偏离。拷贝文件，查上游，通知后在同一轮次继续。 |
| `environment` | 这一步没有在节点上执行。通知。修好环境后在同一轮次继续。 |
| `crash` | 当前 label 不是受控的崩溃或恢复，而进程非 0、没有 `logout`、容器没有起来、超时，或库 / sanitizer 打出 `Assertion`、`Sanitizer`、`stack smashing`。通知并停。拷贝 `log.host`、`replay.status` 和 sanitizer 输出。受控的崩溃或恢复执行成功时不写这一行。 |

控制器的 `Variable ... compare failed` 是变量不一致，归 `bug` 或 `adapter`，即使日志里同时有控制器自己的断言。只读后返回错误码、进程仍在的防御性分支不是 `crash`。这条路径把进程打死时才是 `crash`。

`net-len` 警告不是失败，不写入这张表。

## 上游

只查归类已经是 `bug` 的记录。检索该仓库的 issue 和 PR。`potential-bugs/<短名>/README.md` 写 `KNOWN` 或 `NOT_FOUND`，并附链接。

`KNOWN` 保留轨迹和复现命令，不从 `potential-bugs/` 删掉。`NOT_FOUND` 才作为新的潜在 bug 交给 `bug-confirmation`。

`crash` 先保持 `crash`，不查上游。确认它是实现问题之后，把该行的归类改成 `bug`，README 写明表现是崩溃或 sanitizer，再按上面查上游。还不能确定时保持 `crash`。

## 潜在 bug 目录

同一类的每一条轨迹都拷进 `<run>/potential-bugs/<短名>/`。`bug`，以及确认后改成 `bug` 的 `crash`，都放这里。尚未确认的 `crash` 也先拷进这个目录，归类仍写 `crash`。轮次目录里的 `traces/` 被 gitignore，GitHub 上只保留这里的副本。子目录不要命名为 `traces`。一条轨迹一个子目录，里面放 `MC.out`、`traces.txt`、`log.host`，以及同一次回放的 `replay.status`、`tlc.err`、`tlc.status`。`crash` 再放 sanitizer 输出。

```
potential-bugs/<短名>/
  README.md
  t0158/MC.out
  t0158/traces.txt
  t0158/log.host
  t0158/replay.status
  t0130/MC.out
  ...
```

新开一轮次时不要改已经写好的目录。

`README.md` 写这些事：

1. 配置名、每条轨迹的种子和步号。步号用日志里的 `# [k]`。
2. 不一致的变量、节点、代码值、模型值。两边的值都写上。崩溃没有变量差时，写退出码、信号或 sanitizer 摘要。
3. 库里的位置：`<ce>/system/` 下的文件、函数、行号。
4. 为什么归成这一类。`bug` 要指出规格的哪一条公式已经描述了这条路径。
5. 每条轨迹一条复现命令：`run_one_testcase.sh <potential-bugs 里的 MC.out> <节点数>`。写上期望看到的变量名、失败步，或期望看到的崩溃。
6. 归类是 `bug` 时：`KNOWN` 或 `NOT_FOUND`，以及 issue 或 PR 链接。表现是崩溃或 sanitizer 时写明。

规格保持不动，不用改 `<ce>/system/` 或驱动去抹平这条记录。交接给 `bug-confirmation` 时带上这个目录。`NOT_FOUND` 才作为新的潜在 bug 交出去。
