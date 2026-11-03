# 本轮副本的补丁

`<ce>/sandtable/` 和 `<ce>/system/` 是整棵拷贝，不提交进 case-studies。副本相对基线的差异写成 `<ce>/patches/`。轮次结束、以及驱动或脚本在回放期间又改过之后，按这里重新生成，覆盖同名补丁。

## 基线

SandTable 基线是拷进 `<ce>/sandtable` 时的那个仓库提交。被测源码基线是拷进 `<ce>/system` 的那棵树，通常在 `<run>/artifact/` 下。两棵基线的路径和提交号写进 `README.md`。比较的是这两棵基线，不比较上游工作区里后来又改过的文件。

## 产出

路径相对各自的根，使下面两条命令能打回本轮副本：

```text
patch -p1 -d <ce>/sandtable < <ce>/patches/sandtable.patch
patch -p1 -d <ce>/system < <ce>/patches/system.patch
```

| 文件 | 何时写 |
|---|---|
| `sandtable.patch` | `<ce>/sandtable` 和 SandTable 基线有差异，包括新增的脚本 |
| `system.patch` | `<ce>/system` 和被测源码基线有差异 |
| `README.md` | 每次生成都写。列出基线提交、每份补丁里的路径，以及上面的 `patch -p1` 命令 |

库没有改动时不写 `system.patch`。`README.md` 写明被测源码和基线逐文件相同。

比较时排除 `.git`、`build`、`cmake-build-*`、`mount`、`__pycache__`、`*.pyc`。新文件的左侧用 `/dev/null`。补丁用 `diff -u` 的标签 `a/<相对路径>` 和 `b/<相对路径>`。

## 核对

在临时目录放上基线里的对应文件，用 `patch -p1` 打入，再和本轮副本逐文件比较。对不上就重写补丁。对不上的补丁不留在 `<ce>/patches/`。
