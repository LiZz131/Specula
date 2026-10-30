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

比较的变量是 `commitIdx`、`currentTerm`、`log`、`state`。领导者还有 `nextIdx`、`matchIdx`。快照元数据和 `lastApplied` 不在这组比较里。加载快照是否发生，要到节点自己的日志里看 `loaded snapshot`，不能只看变量断言。

## 队列长度

`compare net-len` 不相等时，控制器打印警告并继续，不以这条警告断言退出：

```
Net mgs length compare failed
Code: ...
Model: ...
```

警告说明捕获条数和模型袋的大小差了。变量仍然可以全相等。判决里单独计这一类，不把它写成变量失败。

自动扫描时要分开两句日志。`Variable` 那句和 `Net mgs length` 那句都含有 “compare failed”。只搜这四个单词会把警告算成断言。

## 通过

同时满足：

- 回放进程留下的 `log.host` 以 `logout` 结束
- 没有 `Variable ... compare failed`，也没有 `Assertion`
- 若有 `Net mgs length` 警告，在判决里标出来，轨迹仍算变量一致

`logout` 出现在断言之后时，以断言为准，这条轨迹失败。
