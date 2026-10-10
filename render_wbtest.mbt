// 输出层的白盒测试。解析部分在 diff_parser_wbtest.mbt 里已经覆盖，
// 这里只盯住渲染：对齐、总计、状态名、以及截断条的长度。

///|
test "format_stat aligns paths and totals" {
  let d = parse(
    src([
      "diff --git a/short.txt b/short.txt", "--- a/short.txt", "+++ b/short.txt",
      "@@ -1,1 +1,2 @@", "-x", "+y1", "+y2", "diff --git a/a-much-longer-name.txt b/a-much-longer-name.txt",
      "--- a/a-much-longer-name.txt", "+++ b/a-much-longer-name.txt", "@@ -1,2 +1,1 @@",
      "-a", "-b", "+c",
    ]),
  )
  debug_inspect(
    d.format_stat(),
    content=(
      #|"              short.txt |    3 ++-\n a-much-longer-name.txt |    3 +--\n2 files changed, 3 insertion(+), 3 deletion(-)"
    ),
  )
}

///|
test "format_stat on an empty diff" {
  debug_inspect(
    Diff::empty().format_stat(),
    content=(
      #|"no changes"
    ),
  )
}

///|
test "format_stat counts binary and mode-only files as zero" {
  let d = parse(
    src([
      "diff --git a/logo.png b/logo.png", "Binary files a/logo.png and b/logo.png differ",
      "diff --git a/run.sh b/run.sh", "old mode 100644", "new mode 100755",
    ]),
  )
  debug_inspect(
    d.format_stat(),
    content=(
      #|" logo.png |    0\n   run.sh |    0\n2 files changed, 0 insertion(+), 0 deletion(-)"
    ),
  )
}

///|
test "stat bar is capped at twenty per side" {
  let lines : Array[String] = [
    "--- a/f.txt", "+++ b/f.txt", "@@ -1,25 +1,25 @@",
  ]
  for i in 0..<25 {
    lines.push("-o\{i}")
  }
  for i in 0..<25 {
    lines.push("+n\{i}")
  }
  let d = parse(src(lines))
  debug_inspect(
    d.format_stat(),
    content=(
      #|" f.txt |   50 ++++++++++++++++++++--------------------\n1 file changed, 25 insertion(+), 25 deletion(-)"
    ),
  )
}

///|
test "format_detail shows status, hunk header and markers" {
  let d = parse(
    src([
      "diff --git a/old.txt b/new.txt", "rename from old.txt", "rename to new.txt",
      "@@ -1,2 +1,2 @@ fn main()", " keep", "-gone", "+here", "\\ No newline at end of file",
    ]),
  )
  debug_inspect(
    d.format_detail(),
    content=(
      #|"renamed  new.txt\n@@ -1,2 +1,2 @@ fn main()\n keep\n-gone\n+here\n\\ No newline at end of file"
    ),
  )
}

///|
test "format_detail on a deleted file keeps the old name" {
  let d = parse(
    src([
      "diff --git a/gone.txt b/gone.txt", "deleted file mode 100644", "--- a/gone.txt",
      "+++ /dev/null", "@@ -1,1 +0,0 @@", "-bye",
    ]),
  )
  debug_inspect(
    d.format_detail(),
    content=(
      #|"deleted  gone.txt\n@@ -1,1 +0,0 @@\n-bye"
    ),
  )
}

///|
test "mode-only detail prints the mode transition" {
  let d = parse(
    src(["diff --git a/run.sh b/run.sh", "old mode 100644", "new mode 100755"]),
  )
  debug_inspect(
    d.format_detail(),
    content=(
      #|"mode change  run.sh\n  mode 100644 -> 100755"
    ),
  )
}

///|
test "line prefixes match the diff alphabet" {
  debug_inspect(
    [Context, Added, Removed].map(fn(k) { k.prefix() }),
    content=(
      #|[" ", "+", "-"]
    ),
  )
}

///|
test "every status has a label" {
  debug_inspect(
    [Modified, NewFile, Deleted, Renamed, Copied, ModeOnly].map(fn(s) {
      s.label()
    }),
    content=(
      #|[
      #|  "modified",
      #|  "new file",
      #|  "deleted",
      #|  "renamed",
      #|  "copied",
      #|  "mode change",
      #|]
    ),
  )
}

///|
test "format_detail marks binary files" {
  // 二进制文件没有 hunk，靠 (binary) 这一行告诉人为什么下面是空的
  let d = parse(
    src([
      "diff --git a/logo.png b/logo.png", "index 1111111..2222222 100644", "Binary files a/logo.png and b/logo.png differ",
    ]),
  )
  assert_eq(d.format_detail(), "modified  logo.png\n  (binary)")
}

///|
test "format_detail prints the copied path and the mode line" {
  let d = parse(
    src([
      "diff --git a/src.txt b/copy.txt", "similarity index 95%", "copy from src.txt",
      "copy to copy.txt", "diff --git a/s.sh b/s.sh", "old mode 100644", "new mode 100755",
    ]),
  )
  assert_eq(
    d.format_detail(),
    "copied  copy.txt\nmode change  s.sh\n  mode 100644 -> 100755",
  )
}
