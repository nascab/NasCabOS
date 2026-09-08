# 影音首页空白 + 悬浮菜单"电影"崩溃修复 Spec

## Why
用户实测两个缺陷：1) 影音管理首页（影库 tab）加载不出内容且无任何反馈；2) 点击悬浮菜单"电影"直接崩溃，堆栈指向 `PageScaffold.ets:96 → overlayContent（归因到 photo/views/album/PhotoAlbumListPage.ets:377，release 产物符号错位）`。

## 根因分析（静态排查结论）

### 缺陷 2：点击"电影"崩溃（高置信根因，证据链完整）
- 点击路径：`VideoMainPage.FloatingModeBar` "电影" chip → `libraryIndex = 1` → `TabBody` → `EmbeddedList('movie','')` → 实例化 `VideoListPage(embedded: true)`。
- [VideoListPage.ets:112-113](../../../harmony_client/entry/src/main/ets/video/views/VideoListPage.ets) 使用 **@BuilderParam 直接方法引用**反模式：
  - `actions: this.listActions`
  - `content: this.listContent`
- ArkTS 规则：@BuilderParam 必须用箭头函数包装（`() => { this.xxx() }`）。直接传方法引用会丢失 this 绑定且不经编译器 builder 转换，调用时抛 JSError（`RTStub_CallRuntime + GetJSError` 崩溃签名吻合）。photo 模块全部页面均使用正确的箭头包装写法，video 模块仅此页（及设置页）例外——对比强烈。
- 崩溃堆栈归因到 PhotoAlbumListPage.ets:377 是 release 产物中匿名箭头函数按同名属性（overlayContent）错误归因，不代表实际渲染了 photo 页面。

### 缺陷 1：影音首页空白
- `VideoHomePage`（activeTab=0, libraryIndex=0 默认分支）UI 三态（加载中/空态/数据区）齐全；`VideoHomeController` 非响应式但通过 `onDataChanged → tick++` 刷新机制完备；`parseVideoHomeData` 字段名与 Flutter 端 `VideoHomeData.fromJson` 完全对齐（含 snake_case 双兜底）。
- Flutter 端失败同样静默 return（`if (!res.success) return;`），故失败提示行为不应改变。
- 剩余唯一可静态判断的缺陷：`refreshAll` 中 `!res.success` 与异常路径**完全静默且无日志**，接口失败时空白无任何线索；且不能排除用户设备运行的是旧 HAP（14:49 崩溃时间早于当日 14:55 的 overlayContent 修复会话）。
- 修复策略：失败路径补日志（输出 code/message），保持 UI 行为对齐 Flutter；实施后先抓日志定位，若日志显示接口/解析错误再按错误修正。

## What Changes
- **MODIFIED** [VideoListPage.ets](../../../harmony_client/entry/src/main/ets/video/views/VideoListPage.ets)：`actions: this.listActions, content: this.listContent` → 箭头函数包装 `actions: (): void => { this.listActions() }, content: (): void => { this.listContent() }`。
- **MODIFIED** [VideoSettingsPage.ets](../../../harmony_client/entry/src/main/ets/video/views/VideoSettingsPage.ets)：`content: this.SettingsContent` → 箭头函数包装（同类反模式，进设置页必崩）。
- **MODIFIED** [VideoHomeController.ets](../../../harmony_client/entry/src/main/ets/video/controllers/VideoHomeController.ets)：`refreshAll` 失败分支（`!res.success`）与 catch 路径增加 `console.error` 日志（接口 code/message），UI 行为保持静默（对齐 Flutter）。
- 全局复查 video 模块无第三处 @BuilderParam 直接方法引用（已 grep 确认）。
- 无 BREAKING 变更。

## Impact
- Affected specs: 无既有 spec（.trae/specs 为空，本次为首个）。
- Affected code:
  - `harmony_client/entry/src/main/ets/video/views/VideoListPage.ets`
  - `harmony_client/entry/src/main/ets/video/views/VideoSettingsPage.ets`
  - `harmony_client/entry/src/main/ets/video/controllers/VideoHomeController.ets`
- 不涉及 Flutter 端，不涉及 photo 模块（photo 写法已全部正确）。

## ADDED Requirements

### Requirement: @BuilderParam 传参正确性
video 模块所有 PageScaffold 及组件的 @BuilderParam 赋值 SHALL 使用箭头函数包装形式（`() => { this.xxxBuilder() }`），SHALL NOT 直接传方法引用（`this.xxxBuilder`）。

#### Scenario: 点击悬浮菜单"电影"
- **WHEN** 用户在影音管理首页点击悬浮菜单"电影"
- **THEN** 影库 tab 切换为电影列表（embedded VideoListPage），正常渲染数据，不崩溃

#### Scenario: 打开影音设置页
- **WHEN** 用户进入影音设置页
- **THEN** 来源设置与其他设置两个 Tab 正常渲染，不崩溃

### Requirement: 首页加载失败可诊断
VideoHomeController.refreshAll 在接口失败（!res.success）或抛异常时 SHALL 输出包含接口路径、code、message 的 error 日志；UI 行为保持与 Flutter 一致的静默处理。

#### Scenario: 首页接口失败
- **WHEN** `/api/video/home/data` 请求失败或解析失败
- **THEN** hilog 中出现包含失败原因的 error 日志，UI 显示既有空态，不崩溃

## REMOVED Requirements
（无）
