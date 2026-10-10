///|
fn two_file_diff() -> Diff raise DiffError {
  parse_diff(
    src([
      "diff --git a/a.txt b/a.txt", "--- a/a.txt", "+++ b/a.txt", "@@ -1,1 +1,1 @@",
      "-old", "+new", "diff --git a/skip.txt b/skip.txt", "Binary files a/skip.txt and b/skip.txt differ",
    ]),
  )
}

///|
test "chat_endpoint appends the path and tolerates a trailing slash" {
  assert_eq(
    chat_endpoint("https://token.sensenova.cn/v1"),
    "https://token.sensenova.cn/v1/chat/completions",
  )
  assert_eq(
    chat_endpoint("https://token.sensenova.cn/v1/"),
    "https://token.sensenova.cn/v1/chat/completions",
  )
}

///|
test "curl_config keeps the key on one line and out of the command" {
  let cfg = curl_config("https://api.example/v1", "sk-test")
  assert_true(cfg.has_prefix("silent\nshow-error\n"))
  assert_true(cfg.contains("url = \"https://api.example/v1/chat/completions\""))
  assert_true(cfg.contains("header = \"Authorization: Bearer sk-test\""))
  assert_true(cfg.contains("data-binary = \"@.moonreview-body.json\""))
  assert_true(cfg.contains("output = \".moonreview-response.json\""))
  // 命令是常量：diff 内容和密钥都不会出现在进程列表里
  assert_eq(curl_command, "curl -K .moonreview-curl.cfg")
}

///|
test "curl_quote escapes what curl would otherwise re-interpret" {
  // 引号不转义的话，密钥里的一个引号就能把后半行变成别的配置项
  let cfg = curl_config("https://api.example/v1", "a\"b\\c")
  assert_true(cfg.contains("Bearer a\\\"b\\\\c"))
}

///|
test "chat_body is a valid two-message chat request carrying the diff" {
  let body = two_file_diff().chat_body("m1")
  // 合法性交给 json 包自己判，比逐字节比字符串稳
  assert_true(@json.valid(body.view()))
  assert_true(body.contains("m1"))
  assert_true(body.contains("system"))
  assert_true(body.contains("user"))
  // 规则里的输出约定，和逐文件展开的 diff 正文
  assert_true(body.contains("LGTM"))
  assert_true(body.contains("a.txt"))
  assert_true(body.contains("skip.txt"))
}

///|
test "chat_reply pulls the model text out of a normal response" {
  let raw = "{\"choices\":[{\"message\":{\"role\":\"assistant\",\"content\":\"a.txt:1: 少了一个判空\"}}]}"
  let (ok, text) = chat_reply(raw)
  assert_true(ok)
  assert_eq(text, "a.txt:1: 少了一个判空")
}

///|
test "chat_reply reports what the API said went wrong" {
  let (ok, text) = chat_reply("{\"error\":{\"message\":\"invalid api key\"}}")
  assert_eq(ok, false)
  assert_true(text.contains("invalid api key"))
}

///|
test "chat_reply copes with a response that is not JSON at all" {
  // 网关、登录页这类响应都是 HTML，不能直接 panic
  let (ok, text) = chat_reply("<html>502 Bad Gateway</html>")
  assert_eq(ok, false)
  assert_true(text.contains("不是 JSON"))
  assert_true(text.contains("502"))
}

///|
test "chat_reply says so when the shape is right but the field is not there" {
  let (ok, text) = chat_reply("{\"choices\":[{\"index\":0}]}")
  assert_eq(ok, false)
  assert_true(text.contains("choices[0].message.content"))
}

///|
test "curl_quote escapes every quote and backslash, not just the first" {
  // 只转第一处的话，第二个引号就能把后面的内容变成别的配置项
  let cfg = curl_config("https://api.example/v1", "a\"b\"c\\d\\e")
  assert_true(cfg.contains("Bearer a\\\"b\\\"c\\\\d\\\\e\""))
}

///|
test "curl_config does not leak the diff body or the key into argv" {
  let cfg = curl_config("https://api.example/v1", "sk-secret-value")
  // 密钥在配置文件里，配置文件里不含 diff 正文
  assert_true(!cfg.contains("a.txt"))
  assert_eq(curl_command.split(" ").to_array().length(), 3)
}

///|
test "trim_one_line folds newlines and cuts by characters, not bytes" {
  assert_eq(trim_one_line("a\r\nb\rc"), "a b c")
  let boundary = "x".repeat(400)
  assert_eq(trim_one_line(boundary), boundary)
  // 「错」占 3 字节：按字节切到 400 会落在字符中间，切出非法 UTF-8
  let cjk = trim_one_line("错".repeat(500))
  assert_eq(cjk.to_array().length(), 402)
  assert_eq(cjk.to_array()[399], '错')
  assert_true(cjk.has_suffix(" …"))
}

///|
test "chat_reply survives a choices field that is not a usable array" {
  // 网关返回千奇百怪，choices 是对象、是空数组、content 不是字符串都不能 panic
  let (ok1, t1) = chat_reply("{\"choices\":{}}")
  assert_eq(ok1, false)
  assert_true(t1.contains("choices[0].message.content"))
  let (ok2, _) = chat_reply("{\"choices\":[]}")
  assert_eq(ok2, false)
  let (ok3, _) = chat_reply("{\"choices\":[{\"message\":{\"content\":42}}]}")
  assert_eq(ok3, false)
  let (ok4, _) = chat_reply("null")
  assert_eq(ok4, false)
}

///|
test "base_url and model fall back to the provider we tested against" {
  assert_eq(resolve_base_url(None), "https://token.sensenova.cn/v1")
  assert_eq(resolve_base_url(Some("https://other/v1")), "https://other/v1")
  assert_eq(resolve_model(Some("")), "sensenova-6.7-flash-lite")
  assert_eq(resolve_model(Some("glm-4.5")), "glm-4.5")
}
