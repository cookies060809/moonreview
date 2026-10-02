# moonreview

[![CI](https://github.com/cookies060809/moonreview/actions/workflows/ci.yml/badge.svg)](https://github.com/cookies060809/moonreview/actions/workflows/ci.yml)

把 `git diff` 吐出来的 unified diff 文本解析成结构化数据，再渲染成人能看的改动摘要。

MoonBit 写的，库那层是纯函数，不碰文件也不碰网络；命令行读 stdin 和文件用的是 native 运行时自带的 C 符号，联网评审则把请求交给系统的 curl，所以整个项目零第三方依赖。

## 构建

需要 MoonBit 工具链（`moon`），`moonc` 不低于 0.10.14。装好后：

```bash
moon build cmd/moonreview    # 产物在 _build/native/debug/build/cmd/moonreview/moonreview.exe
moon test                    # 60 个测试
bash scripts/smoke.sh        # 真进程冒烟：stdin、退出码、临时文件清理
```

也可以直接跑：`moon run cmd/moonreview -- --stat`。

仓库里还带了一个最小库用例，`moon run examples/basic` 直接跑：解析一段内嵌的 diff，打印摘要和聚合数，也是外部代码调用这个库的标准写法。

当作库引入：`moon add cookies060809/moonreview`。

## 命令行

不传文件名时从标准输入读，`-` 也表示标准输入，给多个文件会把内容按顺序拼起来。

```bash
git diff HEAD~1 HEAD | moonreview
moonreview --detail commit.diff
moonreview --check pr.diff
```

| 选项 | 作用 |
| --- | --- |
| 默认 / `--stat` | 每个文件一行变更量，末尾给总计，形式同 `git diff --stat` |
| `--detail` / `-d` | 逐文件打印状态、hunk 头和每一行的 +/- |
| `--json` | 输出结构化 JSON，字段固定，给别的程序读 |
| `--review-prompt` | 只生成给模型看的评审提示词，不联网 |
| `--review` | 把提示词发给模型，打印它的评审意见 |
| `--check` | 不输出内容，只用退出码告诉你这份 diff 干不干净 |
| `-h` / `-V` | 帮助、版本 |

退出码：`0` 成功，`1` 是 `--check` 下发现了改动或 `--review` 没拿到意见，`2` 是用法错误、读不到输入或 diff 解析失败。

## 自动评审

`--review` 需要一个大模型接口。任何 OpenAI 兼容的 `/chat/completions` 都能用，靠环境变量配：

| 变量 | 含义 |
| --- | --- |
| `MOONREVIEW_API_KEY` | 必填，没设时退而读 `OPENAI_API_KEY` |
| `MOONREVIEW_BASE_URL` | 接口地址，默认 `https://token.sensenova.cn/v1`（商汤 SenseNova） |
| `MOONREVIEW_MODEL` | 模型名，默认 `sensenova-6.7-flash-lite` |

```bash
export MOONREVIEW_API_KEY=...
git diff HEAD~1 HEAD | moonreview --review
```

MoonBit 的 native 后端没有 HTTPS 标准库，所以这一层是就地把请求体和 curl 配置写成当前目录下的隐藏临时文件，执行 `curl -K .moonreview-curl.cfg`，读回响应再删掉文件。两个刻意的取舍：

- 密钥只出现在配置文件里，不进命令行参数。进程列表是整机可见的。
- 要执行的命令是一个常量字符串，diff 内容和密钥都不会被拼进去，所以交给 shell 没有注入面。

响应不是 JSON（网关的 HTML、502）或者接口返回 `error.message` 时，都会变成一句人话打印出来，退出码 `1`，不会崩。

没有网、没有 curl、或者在 wasm/js 后端编译时，用 `--review-prompt`：提示词照生成，调模型的那步交给别的程序。

## 例子

下面是一份真实的 `git diff` 输出（一个文件有改动、一个二进制新文件、一个改名），过 `moonreview` 的结果：

```
$ moonreview --stat sample.diff
       src/a.txt |    3 ++-
    src/logo.png |    0
 src/renamed.txt |    0
3 files changed, 2 insertion(+), 1 deletion(-)

$ moonreview -d sample.diff
modified  src/a.txt
@@ -1,3 +1,4 @@
 alpha
-beta
+BETA
 gamma
+delta
new file  src/logo.png
  (binary)
renamed  src/renamed.txt
```

同一份 diff 的 `--json`（只留 `src/a.txt` 那个 hunk 的开头，其余用 `…` 省略）：

```json
{
  "summary": { "file_count": 3, "hunk_count": 1, "added": 2, "removed": 1 },
  "files": [
    {
      "old_path": "src/a.txt",
      "new_path": "src/a.txt",
      "path": "src/a.txt",
      "status": "modified",
      "binary": false,
      "old_mode": null,
      "new_mode": null,
      "added": 2,
      "removed": 1,
      "hunks": [
        {
          "old_start": 1, "old_count": 3, "new_start": 1, "new_count": 4,
          "heading": "",
          "no_newline_old": false, "no_newline_new": false,
          "lines": [
            { "kind": "context", "old_line": 1, "new_line": 1, "content": "alpha" },
            { "kind": "removed", "old_line": 2, "new_line": null, "content": "beta" },
            { "kind": "added", "old_line": null, "new_line": 2, "content": "BETA" },
            …
          ]
        }
      ]
    },
    …
  ]
}
```

## 库

`moon.pkg` 里给包起个别名，调用时走 `@别名.`（当前 MoonBit 版本没有 `包名::名字` 这种写法）：

```moonbit
// import { "cookies060809/moonreview" @moonreview, }

let d = @moonreview.parse_diff(text)   // 失败 raise DiffError::BadDiff(行号, 说明)
d.format_stat()                      // 上面那份摘要
d.format_detail()                    // 上面那份逐行输出
d.file_count()
d.hunk_count()
d.added_count()
d.removed_count()
d.touched_paths()                    // 这次动过的文件
d.review_prompt()                    // 给模型看的评审提示词（纯文本，不联网）
d.chat_body("模型名")                 // 同一个提示词拆成 chat 请求体
@moonreview.chat_reply(raw)          // 把接口响应解成 (成功?, 文本)
```

数据结构是 `Diff` → `FileDiff` → `Hunk` → `Line`，`Line` 带 `old_line` / `new_line` 两个行号，所以拿到意见之后能准确回指到文件的某一行。

解析器按 `@@` 头声明的行数驱动，而不是逐行看前缀。这一点很重要：diff 里删掉一行 `-- foo` 会渲染成 `--- foo`，长得和文件头一模一样。

覆盖到的格式细节包括 GNU 的"计数省略当作 1"、计数为 0 的纯增/纯删、`\ No newline at end of file` 归属改动前还是改动后、`/dev/null`、`new file mode` / `rename from` / `old mode` / `Binary files ... differ`、带空格路径的引号、`---` 行尾的时间戳、CRLF。

## 还没做的

- 意见回来后没有再解析成结构化的「哪一行有什么问题」，现在打印的是模型给的原样文本。
- 只解析，不应用 diff，也不生成 diff（生成请用 `moonbitlang/core` 自带的 `diff` 模块，它只能生成不能解析，这两件事不冲突）。

## 与同类项目的对比

MoonBit 社区已有两个处理 diff 的项目，功能重叠和分工边界在这里说清楚。三个项目都认得 unified diff 这一种文本格式，但解决的问题不同：

- [yuzhiblue/moon-diff](https://github.com/yuzhiblue/moon-diff)（8 月黑客松项目）：从两段文本**计算**差异（LCS、Myers、Patience、Histogram、Hirschberg 五种算法），把结果渲染成 unified diff、应用回文本，另有三方合并、JSON Patch、目录树 diff。它解决"补丁从哪来"——没有两段原文就没有它。本工具正相反：输入就是 `git diff` 已经产出的文本，不算差异、不应用补丁，解决"这份改动怎么给人看、给模型看"。两者是上下游：moon-diff 生成的 unified diff，正是 moonreview 要解析的输入。
- `mizchi/bit_apply`（[mooncakes 包](https://mooncakes.io/package/mizchi/bit_apply)，源码在 [bit-vcs/bit](https://github.com/bit-vcs/bit) 仓库的 `modules/bit_apply`，是 bit-vcs 这个 MoonBit VCS 的组件）：把 git 风格补丁解析成**文件级**元数据（`PatchInfo`：新旧路径与模式、rename/copy/new/delete 标记、增删行数、相似度指数），并提供反向补丁。它和本工具重叠最大——都在"读" git diff 文本——但它的公开接口到文件为止，没有 hunk 和行的结构；本工具建模到每一行、每行带改动前后的双行号，并在这层数据上提供摘要渲染、`--json`、退出码门禁和模型评审，这些都不在它的公开接口里，它服务的 VCS 补丁簿记场景本工具也不涉及。
- `moonbitlang/core` 自带的 `diff` 模块：只能从两段文本生成 unified diff，不能解析（见上文"还没做的"）。

把改动交给大模型评审的整条链路（带双行号的提示词构造、OpenAI 兼容接口调用、响应解包与离线降级），三个项目里只有本工具做了。

## 许可

Apache-2.0，见 `LICENSE`。
