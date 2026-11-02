# 怎样判一条回放

控制器日志是 `test/log.host`。成功时文件末尾有一行 `logout`，行尾可能有空格，用子串判断。

## 变量

`compare variable` 不相等时，控制器在 `Command.cpp` 里断言退出。日志里有：

```
Variable "<名字>" compare failed
Code (<节点>): ...
Model(<节点>): ...
```

这是一条失败。记录变量名、节点、两边的值，以及该步的 `pc` 注释（`# [k] ...`）。

每一步比较该 action 在 `base.tla` 里读或写的变量。不在这里列举某一个系统的变量名。

持久变量是崩溃之后、恢复时仍然保留的那些。怎么判定见 `sandtable-instrumentation` 的 `references/controllability.md`。恢复之后，这些值必须来自驱动写下的副本，不来自停掉之前的进程内存。副本没有写下，或读回的值与公式不一致，是失败。

易失变量是崩溃丢掉、或恢复按公式重设的那些。比较的是公式给出的新值。

## 队列长度

`compare net-len` 不相等时，控制器打印警告并继续，不以这条警告断言退出：

```
Net mgs length compare failed
Code: ...
Model: ...
```

警告说明捕获条数和模型袋的大小差了。变量仍然可以全相等。判决里单独计这一类，不把它写成变量失败。

自动扫描时要分开两句日志。`Variable` 那句和 `Net mgs length` 那句都含有 “compare failed”。只搜这四个单词会把警告算成断言。

## 计划外崩溃

下面任一情况记失败类 `crash`，和变量不一致分开。当前 label 是受控的崩溃或恢复时，不把这一步记入这里。立刻写入 `failures.tsv`，拷贝 `log.host`、`replay.status` 和 sanitizer 输出，并停住这条之后的采样。

- 进程退出码非 0
- 没有 `logout`
- 容器没有起来
- 回放超时
- 库或 sanitizer 的输出里有 `Assertion`、`Sanitizer`、`stack smashing`

有 `Variable ... compare failed` 时归 `bug` 或 `adapter`，不归 `crash`。那是控制器的变量断言。只读后返回错误码、进程仍在的防御性分支也不是 `crash`。

超时或容器没起来时，循环仍要留下 `replay.status` 和 `failures.tsv` 的一行。不要在没有这一行的情况下让整个回放进程退出。

## 通过

同时满足：

- 回放进程留下的 `log.host` 以 `logout` 结束
- 退出码是 0
- 没有 `Variable ... compare failed`
- 没有库或 sanitizer 的 `Assertion`、`Sanitizer`、`stack smashing`
- 若有 `Net mgs length` 警告，在判决里标出来，轨迹仍算变量一致

`logout` 出现在变量断言之后时，以变量断言为准，这条轨迹失败。失败立刻写入该轮次的 `failures.tsv`，归类见 `mismatch-record.md`。
