// 联网评审的数据层：造请求体、造 curl 配置、解析响应。
//
// 这一整层都是纯函数——不联网、不碰文件，所以能离线跑测试。真正调 curl 的那半
// 在 cmd/moonreview，因为 MoonBit 的 native 目标没有 HTTPS 标准库，发请求只能借外部
// 程序；把「发什么」和「怎么发」分开，换供应商时只需要改常量和环境变量。
//
// 一个刻意的取舍：API Key 只写进 curl 配置文件，绝不出现在命令行参数里。
// 进程列表是整机可见的，命令行带密钥等于泄露给同一台机器上的所有用户。

///|
/// 供应商相关的默认值。用 OpenAI 兼容接口的服务都能跑，
/// 靠 MOONREVIEW_BASE_URL / MOONREVIEW_MODEL 覆盖成自己那家。
let default_base_url : String = "https://token.sensenova.cn/v1"

///|
let default_model : String = "sensenova-6.7-flash-lite"

///|
/// 请求体、curl 配置、响应都落在当前目录的隐藏文件里：
/// 用相对路径可以绕开 Windows 反斜杠在 curl 配置里被当转义符的坑，
/// 也让命令本身变成一个不含任何外部输入的固定字符串。
pub let body_file : String = ".moonreview-body.json"

///|
pub let config_file : String = ".moonreview-curl.cfg"

///|
pub let response_file : String = ".moonreview-response.json"

///|
/// OpenAI 兼容接口都是 base_url 再加一段路径；末尾多余的斜杠会拼出 `//v1//`
/// 这种地址，所以先去掉再拼。
fn drop_trailing_slash(s : String) -> String {
  guard s.has_suffix("/") && s.length() > 1 else { return s }
  s.unsafe_substring(start=0, end=s.length() - 1)
}

///|
pub fn chat_endpoint(base_url : String) -> String {
  drop_trailing_slash(base_url) + "/chat/completions"
}

///|
/// curl 配置里的值用双引号包住，串里的 `\` 和 `"` 要再转义一层，
/// 否则密钥里带个引号就能把后面的行改成别的配置项。
fn curl_quote(value : String) -> String {
  let escaped = value
    .replace_all(old="\\", new="\\\\")
    .replace_all(old="\"", new="\\\"")
  "\"" + escaped + "\""
}

///|
/// curl 的配置文件格式，对应 `curl -K <config_file>`。
/// 请求体走 `data-binary = "@file"`，只有文件名进配置，正文不进。
pub fn curl_config(base_url : String, api_key : String) -> String {
  [
    "silent",
    "show-error",
    "max-time = \"180\"",
    "request = \"POST\"",
    "url = " + curl_quote(chat_endpoint(base_url)),
    "header = \"Content-Type: application/json\"",
    "header = " + curl_quote("Authorization: Bearer " + api_key),
    "data-binary = " + curl_quote("@" + body_file),
    "output = " + curl_quote(response_file),
  ].join("\n") +
  "\n"
}

///|
/// 固定命令串：不含任何来自 diff、密钥或环境的内容，所以交给 shell 执行是安全的。
pub let curl_command : String = "curl -K " + config_file

///|
/// 请求体：system 消息放规则，user 消息放逐文件的 diff 文本。
pub fn Diff::chat_body(self : Diff, model : String) -> String {
  let files : Array[String] = self.files.map(file_text)
  jobj([
    ("model", jstr(model)),
    (
      "messages",
      jarr([
        jobj([("role", jstr("system")), ("content", jstr(prompt_rules))]),
        jobj([("role", jstr("user")), ("content", jstr(files.join("\n\n")))]),
      ]),
    ),
    ("stream", jbool(false)),
  ]).stringify()
}

///|
fn json_get(j : Json?, key : String) -> Json? {
  match j {
    Some(Object(obj)) => obj.get(key)
    _ => None
  }
}

///|
fn json_item(j : Json?, index : Int) -> Json? {
  match j {
    Some(Array(items)) =>
      if index >= 0 && index < items.length() {
        Some(items[index])
      } else {
        None
      }
    _ => None
  }
}

///|
fn json_text(j : Json?) -> String? {
  match j {
    Some(String(s)) => Some(s)
    _ => None
  }
}

///|
/// 成功时返回模型写的正文，失败时返回一句能直接给人看的说明。
/// 用元组而不是新类型，是为了不把错误类型的构造器再导出一次。
pub fn chat_reply(raw : String) -> (Bool, String) {
  let root : Json? = Some(
    @json.parse(raw.view()) catch {
      _ => return (false, "接口返回的不是 JSON： " + trim_one_line(raw))
    },
  )
  let api_error = json_get(json_get(root, "error"), "message") |> json_text
  match api_error {
    Some(msg) => (false, "接口报错： " + msg)
    None => {
      let message = json_get(json_item(json_get(root, "choices"), 0), "message")
      let text = json_get(message, "content") |> json_text
      match text {
        Some(t) => (true, t)
        None =>
          (
            false,
            "响应里没有 choices[0].message.content： " +
            trim_one_line(raw),
          )
      }
    }
  }
}

///|
/// 原始响应可能很长（也可能根本不是 JSON），只留够排查的一段。
///
/// 按字符数裁，不按字节数：`unsafe_substring` 的下标是字节下标，落在多字节字符
/// 中间会切出非法 UTF-8，而响应正文里带中文是常态（网关的报错就是中文）。
fn trim_one_line(s : String) -> String {
  let one_line = s
    .replace_all(old="\r\n", new=" ")
    .replace_all(old="\r", new=" ")
    .replace_all(old="\n", new=" ")
  let cs = one_line.to_array()
  if cs.length() <= 400 {
    one_line
  } else {
    String::from_array(cs[:400]) + " …"
  }
}

///|
/// base_url 和 model 都允许不传，这时用默认值。
pub fn resolve_base_url(value : String?) -> String {
  match value {
    None | Some("") => default_base_url
    Some(v) => v
  }
}

///|
pub fn resolve_model(value : String?) -> String {
  match value {
    None | Some("") => default_model
    Some(v) => v
  }
}
