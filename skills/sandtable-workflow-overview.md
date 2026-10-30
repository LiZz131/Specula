# SandTable 受控执行

Specula 套件已经存在之后，用 SandTable 把模型轨迹放到未改动的实现上执行。这条管道不重写 `base.tla` 的协议公式，也不插桩被测源码。`harness-generation` 打的是 NDJSON；这里打的是控制器命令。

## 四个阶段

```
Specula 套件
base.tla、MC.tla、MC.cfg、MC_hunt_*.cfg
        │
        ▼
1. sandtable-instrumentation
   base_for_sandtable.tla、MC_for_sandtable*.tla/cfg、生成器按 scr.pc 发命令
        │
        ▼
2. sandtable-replay
   每种配置的随机轨迹、受控执行判决、实现侧墙钟、潜在 bug 记录
        │
        ▼
3. sandtable-coverage
   行覆盖和分支覆盖随条数的曲线、从未执行的函数和行
        │
        ▼
4. sandtable-coverage-gaps
   四条标准分类
        │
        ├─ 模型能走到 → 回到 2，加长或加采样，再用 3 验收
        └─ 模型没建模 → 写成场景，交回 spec_generation
```

适配层改完之后，阶段 2 和 3 对全部建模配置重跑。

## 和现有 skill 的边界

| 现有 skill | 关系 |
|---|---|
| `spec_generation` | 仍负责 `base.tla` 和 hunt 配置。缺口阶段只把「没建模」退回这里 |
| `harness-generation` | 插桩打 NDJSON。SandTable 不改被测源码 |
| `tla-trace-workflow` | 用实现 trace 校验规格。这里用规格驱动真实进程 |
| `bug-confirmation` | 潜在 bug 记录到可以交接为止。确认和修复仍走原来的 bug skill |

## 交接物

| 阶段 | 目录 | 交给下一阶段的文件 |
|---|---|---|
| 1 | `skills/sandtable-instrumentation/` | `base_for_sandtable.tla`、`MC_for_sandtable.tla`、每种建模配置一份 cfg、能识别 `scr.pc` 的生成器 |
| 2 | `skills/sandtable-replay/` | 每条轨迹的 `MC.out`、`traces.txt`、`log.host`、判决和墙钟；潜在 bug 目录 |
| 3 | `skills/sandtable-coverage/` | 覆盖率曲线、封顶条数、未执行函数和行 |
| 4 | `skills/sandtable-coverage-gaps/` | 分类文档；要么是更深的采样配置，要么是交回 Specula 的场景说明 |
