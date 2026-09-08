# Checklist

- [x] VideoListPage.ets 的 PageScaffold `actions`/`content` 均使用箭头函数包装，无直接方法引用
- [x] VideoSettingsPage.ets 的 PageScaffold `content` 使用箭头函数包装，无直接方法引用
- [x] 全工程 grep `actions: this\.` / `content: this\.` / `overlayContent: this.` 无残留（排除 PageScaffold.ets 自身）
- [x] VideoHomeController.refreshAll 在 `!res.success` 时输出 error 日志（含 code/message）
- [x] VideoHomeController.refreshAll 有 try/catch 兜底，异常被捕获并输出 error 日志，不再冒泡
- [x] refreshAll 的 UI 行为保持静默（失败不弹 toast，与 Flutter 一致）
- [x] hvigorw 全量编译 BUILD SUCCESSFUL
- [x] 提醒用户重装最新 HAP 并实测：首页可加载数据、点击悬浮"电影"正常切列表、进影音设置不崩溃
