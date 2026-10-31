# gcov 计数怎么落盘

## 编译

被测库的 C 文件加上 `--coverage`，和原来的警告级别、`-g`、`-std` 一起用。驱动在链接时加上 `-lgcov --coverage`。优化保持库原来的级别；拦截器自身的优化与这份覆盖率无关。

CMake 若会在下次配置时丢掉这些标志，就把标志记在本参考里，重编时按同一组标志恢复。库的源文件在 `artifact/<system>/`。

## 每个节点一份计数

多个节点共享同一套带 gcno 的二进制。gcda 若写在 gcno 旁边，会互相覆盖。启动脚本为每个节点设置：

```
GCOV_PREFIX=/tmp/gcov-n<编号>
GCOV_PREFIX_STRIP=0
```

`/tmp` 不在共享挂载上。gcno 仍留在构建目录。

## 只在退出时写一次

`__gcov_dump` 第一次调用会把计数写成快照，之后的执行不再进入后续的 gcda。周期线程、短间隔 flush 都会让曲线停在进程前一小段。

沙箱里的驱动常常不会走到 `atexit`，也不会收到可捕获的信号。拦截器在控制器套接字关闭时调用 `_exit`，跳过 `atexit` 和析构。在这次 `_exit` 之前调用一次 dump。

做法：库或驱动导出一个函数，拦截器用弱符号调用它。未做覆盖率链接的系统里弱符号为空，调用被跳过。驱动链接时加上 `-Wl,--export-dynamic`，使主程序里的这个符号能被拦截器的共享库看见。

不要在 `atexit` 里再 dump 一次。第二次 dump 可能用空计数覆盖刚写好的文件。

dump 挂钩和驱动链接行记在 `<run>/sandtable/driver/`。不改 SandTable 仓库里的副本。

## 合并与报告

宿主机上的 `gcov-tool` 打不开容器里拷出的 gcda。合并在控制器容器里做：

```
gcov-tool merge -o m12 n1 n2
gcov-tool merge -o all m12 n3
```

gcno 记录的源码路径是容器内的绝对路径。`gcov -b` 也在容器里、能访问该路径的目录中运行。对 `*.gcno` 运行，让它找到同目录的 gcda。

节点之间用 `docker cp` 经由宿主机中转。容器之间直接 `docker cp` 不可用。宿主机上 `docker cp` 出来的文件属主是 root，清理时用 `sudo rm`。

`-fsanitize=address,undefined` 的二进制不写进这一轮的 gcda。sanitizer 轮次的计数不并入 `lcov.info`。覆盖率轮次不打开泄漏检测。

## 先确认 dump 有效

一条会竞选并成为领导者的短轨迹之后，检查：

- 对应 gcda 的大小大于空文件
- `raft_become_leader` 或等价的「成为领导者」函数计数大于 0
- 领导者节点上处理 AppendEntries 请求的函数可以仍是 0，因为请求发向了别的节点；合并三个节点后再下结论
