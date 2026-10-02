/// 最小库用例：解析一段内嵌的 unified diff，打印人读摘要和聚合数。
/// 运行：moon run examples/basic
///
/// 外部调用方照这个包的 moon.pkg 写 import（起个别名，这里叫 @moonreview），
/// 然后走 @moonreview.parse_diff。解析可能失败，catch 里拿到的
/// BadDiff(行号, 说明) 直接告诉你错在哪一行。

///|
let sample : String = "diff --git a/src/a.txt b/src/a.txt\n" +
  "index 1234567..89abcde 100644\n" +
  "--- a/src/a.txt\n" +
  "+++ b/src/a.txt\n" +
  "@@ -1,3 +1,4 @@\n" +
  " alpha\n" +
  "-beta\n" +
  "+BETA\n" +
  " gamma\n" +
  "+delta\n"

///|
fn main {
  let d = @moonreview.parse_diff(sample) catch {
    @moonreview.BadDiff(no, msg) => {
      println("解析失败（第 \{no} 行）：\{msg}")
      return
    }
  }
  println(d.format_stat())
  println("")
  println(
    "files: \{d.file_count()}, hunks: \{d.hunk_count()}, +\{d.added_count()} -\{d.removed_count()}",
  )
  println("touched: \{d.touched_paths().join(", ")}")
}
