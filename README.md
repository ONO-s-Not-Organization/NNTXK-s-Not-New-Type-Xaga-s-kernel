# 如何向 Android Common Kernels 提交补丁

1. **最佳方式（BEST）：** 将你的所有修改提交到上游 Linux。如果合适，将其向后移植（backport）到稳定版本。
   这些补丁会自动合并到对应的 Common Kernel 中。如果该补丁已经存在于上游 Linux 中，则提交该补丁的 backport 版本，并使其符合下面的补丁要求。

   * 不要向上游发送仅包含符号导出的补丁。若要让上游 Linux 考虑接受 `EXPORT_SYMBOL_GPL()` 的新增导出，则必须存在一个使用该符号的、位于内核源码树（in-tree）中的模块化驱动——因此，应当在包含该导出的同一组补丁（patchset）中，同时包含这个新驱动，或者对现有驱动的修改。
   * 向上游发送补丁时，提交信息（commit message）必须清楚说明为什么需要该补丁，以及该补丁能够为社区带来什么好处。**启用树外（out-of-tree）驱动或功能并不是一个有说服力的理由。**

2. **较不推荐的方式（LESS GOOD）：** 在上游 Linux 的视角下，以树外（out-of-tree）的方式开发你的补丁。除非这些补丁是在修复 Android 特有的 bug，否则除非已经与 `kernel-team@android.com` 协调过，否则它们几乎不可能被接受。如果你仍然希望继续，请提交一个符合下面补丁要求的补丁。

# Common Kernel 补丁要求

* 所有补丁必须符合 Linux 内核编码规范，并通过 `script/checkpatch.pl`。
* 补丁不得破坏以下架构的 `gki_defconfig` 或 `allmodconfig` 构建：
  `arm`、`arm64`、`x86`、`x86_64`
  （参见 https://source.android.com/setup/build/building-kernels）
* 如果补丁不是从上游分支合并而来的，则提交主题（subject）必须使用以下补丁类型标签之一：
  `UPSTREAM:`、`BACKPORT:`、`FROMGIT:`、`FROMLIST:` 或 `ANDROID:`。
* 所有补丁都必须包含 `Change-Id:` 标签（参见 https://gerrit-review.googlesource.com/Documentation/user-changeid.html）。
* 如果已经分配了 Android bug，则必须包含 `Bug:` 标签。
* 所有补丁都必须包含作者和提交者的 `Signed-off-by:` 标签。

下面根据补丁类型列出其他要求。

## 从主线 Linux 进行 backport 的要求：`UPSTREAM:`、`BACKPORT:`

* 如果该补丁是从 Linux 主线（mainline）直接 cherry-pick 而来，并且**完全没有任何修改**：

  * 在补丁主题前添加 `UPSTREAM:` 标签。
  * 添加上游提交信息，使用 `(cherry picked from commit ...)` 这一行。
  * 示例：

    * 如果上游提交信息为：

```text
        important patch from upstream

        This is the detailed description of the important patch

        Signed-off-by: Fred Jones <fred.jones@foo.org>
```

```
- 那么 Joe Smith 应当将该补丁以如下形式上传到 Common Kernel：
```

```text
        UPSTREAM: important patch from upstream

        This is the detailed description of the important patch

        Signed-off-by: Fred Jones <fred.jones@foo.org>

        Bug: 135791357
        Change-Id: I4caaaa566ea080fa148c5e768bb1a0b6f7201c01
        (cherry picked from commit c31e73121f4c1ec41143423ac6ce3ce6dafdcec1)
        Signed-off-by: Joe Smith <joe.smith@foo.org>
```

* 如果该补丁相对于上游版本需要进行**任何修改**，则使用 `BACKPORT:`，而不是 `UPSTREAM:`。

  * 使用与 `UPSTREAM:` 相同的标签。
  * 在 `(cherry picked from commit ...)` 这一行下面添加关于所做修改的注释。
  * 示例：

```text
        BACKPORT: important patch from upstream

        This is the detailed description of the important patch

        Signed-off-by: Fred Jones <fred.jones@foo.org>

        Bug: 135791357
        Change-Id: I4caaaa566ea080fa148c5e768bb1a0b6f7201c01
        (cherry picked from commit c31e73121f4c1ec41143423ac6ce3ce6dafdcec1)
        [joe: Resolved minor conflict in drivers/foo/bar.c ]
        Signed-off-by: Joe Smith <joe.smith@foo.org>
```

## 其他 backport 的要求：`FROMGIT:`、`FROMLIST:`

* 如果该补丁已经被合并到上游维护者（maintainer）的代码树中，但尚未合并到 Linux 主线：

  * 在补丁主题前添加 `FROMGIT:` 标签。
  * 添加补丁来源信息，格式为：
    `(cherry picked from commit <sha1> <repo> <branch>)`
    这里必须使用一个稳定的维护者分支（不能是经过 rebase 的分支，因此例如不要使用 `linux-next`）。
  * 如果需要进行修改，则使用 `BACKPORT: FROMGIT:`。
  * 示例：

    * 如果维护者代码树中的提交信息为：

```text
        important patch from upstream

        This is the detailed description of the important patch

        Signed-off-by: Fred Jones <fred.jones@foo.org>
```

```
- 那么 Joe Smith 应当将该补丁以如下形式上传到 Common Kernel：
```

```text
        FROMGIT: important patch from upstream

        This is the detailed description of the important patch

        Signed-off-by: Fred Jones <fred.jones@foo.org>

        Bug: 135791357
        (cherry picked from commit 878a2fd9de10b03d11d2f622250285c7e63deace
         https://git.kernel.org/pub/scm/linux/kernel/git/foo/bar.git test-branch)
        Change-Id: I4caaaa566ea080fa148c5e768bb1a0b6f7201c01
        Signed-off-by: Joe Smith <joe.smith@foo.org>
```

* 如果该补丁已经提交到 LKML，但尚未被任何维护者代码树接受：

  * 在补丁主题前添加 `FROMLIST:` 标签。
  * 添加一个 `Link:` 标签，并附上该补丁在 `lore.kernel.org` 上的提交链接。
  * 添加一个 `Bug:` 标签，并填写 Android bug（对于尚未被维护者代码树接受的补丁，这是必需的）。
  * 如果需要进行修改，则使用 `BACKPORT: FROMLIST:`。
  * 示例：

```text
        FROMLIST: important patch from upstream

        This is the detailed description of the important patch

        Signed-off-by: Fred Jones <fred.jones@foo.org>

        Bug: 135791357
        Link: https://lore.kernel.org/lkml/20190619171517.GA17557@someone.com/
        Change-Id: I4caaaa566ea080fa148c5e768bb1a0b6f7201c01
        Signed-off-by: Joe Smith <joe.smith@foo.org>
```

## Android 特有补丁的要求：`ANDROID:`

* 如果该补丁用于修复 Android 特有代码中的 bug：

  * 在补丁主题前添加 `ANDROID:` 标签。
  * 添加一个 `Fixes:` 标签，引用包含该 bug 的补丁。
  * 示例：

```text
        ANDROID: fix android-specific bug in foobar.c

        This is the detailed description of the important fix

        Fixes: 1234abcd2468 ("foobar: add cool feature")
        Change-Id: I4caaaa566ea080fa148c5e768bb1a0b6f7201c01
        Signed-off-by: Joe Smith <joe.smith@foo.org>
```

* 如果该补丁是一个新功能：

  * 在补丁主题前添加 `ANDROID:` 标签。
  * 添加一个 `Bug:` 标签，并填写 Android bug（对于 Android 特有功能，这是必需的）。
