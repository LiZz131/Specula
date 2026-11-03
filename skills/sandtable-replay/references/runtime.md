# 一条轨迹怎么在 SandTable 里跑

权威副本是本轮的 `<ce>/system/` 和 `<ce>/sandtable/`。容器读的是挂载盘上的工作副本。不改上游 SandTable 检出，也不改别的轮次。`<ce>` 的定义见 `sandtable-workflow-overview.md`。

## 进程

| 容器 | 做什么 |
|---|---|
| `controller` | 读 `traces.txt`，按序发命令：投递、推进虚拟时钟、客户端操作、分区、按序号丢掉或复制一条、停止或拉起节点 |
| 节点容器 | 在拦截器下跑驱动。个数等于模型的 server，不默认三个 |

拦截器按 `seq` 把指定消息交给对应节点。投递、丢失和复制都按这个序号只动一条。控制器若仍然只弹出通道队首，就不能用来处理非队首的消息，要在本轮的 `<ce>/sandtable/` 里改成按序号取出。

每个节点把 gcov 写到自己的 `GCOV_PREFIX`（`/tmp/gcov-n<编号>`），避免各节点共用一份 gcda。合并在 `controller` 里用 `gcov-tool` 做。宿主机上的 `gcov-tool` 打不开容器里的 gcda。

## 启动

超过一条轨迹的回放放在后台。正常轨迹不通知。每一条不一致、失败、崩溃、异常退出都通知。

循环调用生成器，再调用 `run_one_testcase.sh <MC.out> <节点数>`。不要加 `-it`。`<ce>/sandtable/scripts/run_round.py` 是这个循环的一种实现，技能不要求这个文件名。

后台任务在 `adapter` 和 `crash` 上停住。通知发出之后可以另一次启动来续跑，并跳过已经有判决的轨迹。`crash` 从下一条还没有判决的编号接着跑。`adapter` 只在修好后的新轮次里跑。`bug` 和 `spec` 通知后由同一次后台任务继续。

把 `<ce>/system/` 和 `<ce>/sandtable/` 同步到挂载盘，再在容器里执行。挂载盘的具体路径以当次启动命令为准，并写进 `轮次报告.md`。早先轮次用过 `sandtable/build/mount/specula-ce`，容器内是 `/root/sandtable/specula-ce`。

跑完把 `traces.txt`、`log.host` 和该配置的 gcov 留在 `controlled-execution-runs/<轮次>/`。超时、容器没起来、进程非 0 时也留下 `replay.status`。挂载盘上的副本可以删，记录以 `<run>` 为准。
