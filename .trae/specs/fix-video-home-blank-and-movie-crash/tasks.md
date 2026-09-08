# Tasks

- [x] Task 1: 修复 VideoListPage 的 @BuilderParam 直接方法引用反模式（点击悬浮"电影"崩溃的根因）
  - [x] SubTask 1.1: `VideoListPage.ets:112-113` 的 `actions: this.listActions, content: this.listContent` 改为箭头函数包装 `actions: (): void => { this.listActions() }, content: (): void => { this.listContent() }`
- [x] Task 2: 修复 VideoSettingsPage 同类反模式（进设置页必崩）
  - [x] SubTask 2.1: `VideoSettingsPage.ets:24` 的 `content: this.SettingsContent` 改为 `content: (): void => { this.SettingsContent() }`
- [x] Task 3: 影音首页加载失败补诊断日志（保持 UI 静默对齐 Flutter）
  - [x] SubTask 3.1: `VideoHomeController.refreshAll` 中 `!res.success` 分支增加 `console.error`（含接口路径、code、message）
  - [x] SubTask 3.2: `refreshAll` 增加 try/catch 兜底（当前 try/finally 无 catch，异常会冒泡导致组件异常），catch 中输出 error 日志并保持静默
- [x] Task 4: 全量编译验证
  - [x] SubTask 4.1: 运行 `cd harmony_client && /Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw assembleHap --mode module -p product=default --no-daemon`，确认 BUILD SUCCESSFUL
- [x] Task 5: 全局复查与 checklist 核验
  - [x] SubTask 5.1: grep 确认全工程无 `actions: this.` / `content: this.` / `overlayContent: this.` 直接方法引用残留
  - [x] SubTask 5.2: 提醒用户重新安装最新 HAP 验证（用户日志时间 14:49 早于当日 overlayContent 修复，需排除旧包干扰）；若首页仍空白，依据 Task 3 日志定位接口失败原因后另行修复

# Task Dependencies
- Task 4 依赖 Task 1、2、3 全部完成
- Task 5 依赖 Task 4
