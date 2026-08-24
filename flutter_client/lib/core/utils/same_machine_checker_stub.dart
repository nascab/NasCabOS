/// 非 Web 平台：无法通过浏览器获取本机 hostname，返回空字符串。
/// 同机检测依赖 localhost 127.0.0.1 探测即可，此函数仅作 Web 端 CORS 被阻时的 fallback。
String getLocalBrowserHostname() => '';
