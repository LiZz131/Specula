# TLC 随机采样

在规格目录运行。必须带 `-tool`，否则 `trace_reader.py` 不认输出。`-workers 1` 和 `-seed` 使同一条种子可重复。

```
java -Xmx512m -jar tla2tools.jar -tool -workers 1 -simulate \
  -depth 50 -seed <N> -metadir /tmp/tlc-<配置>-<N> \
  -config <MC_for_sandtable_*.cfg> MC_for_sandtable
```

`-depth` 要大于 `DepthBound` 的层数，模拟才会被不变量截停并打印行为。`DepthBound` 为 `TLCGet("level") < 31` 时，`-depth 50` 足够。

退出码 12 表示有不变量被违反。打印的是 `Invariant DepthBound is violated` 时，行为就是要的轨迹。打印的是安全性不变量时，把该行为交给 `sandtable-replay` 的归类，不要当成普通样本混进通过数。

死锁时 TLC 可能以非 12 的退出码提前停下，`-tool` 仍会打印已经走出的状态。状态里有 `pc |->` 就可以回放，步数少于上界。

采样结束后删掉 `-metadir`。并行度保持在机器能承受的 TLC 进程数以内，每个种子单独一个 metadir。

更长的游走另用一份只加大层数上界的模块和 cfg，见 `sandtable-instrumentation` 的 `references/config-mapping.md`。原来的 30 步配置继续用于横向比较。
