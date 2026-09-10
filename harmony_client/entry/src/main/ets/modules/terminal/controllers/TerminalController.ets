import { webSocket } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
import pasteboard from '@ohos.pasteboard';
import { L10n } from '../../../core/localization/L10n';
import { ToastUtil } from '../../../common/ToastUtil';
import { PreferencesStore } from '../../../core/storage/PreferencesStore';
import { DeviceFingerprint } from '../../../core/device/DeviceFingerprint';
import {
  TerminalUiConfig, TerminalLine, TerminalLineSource,
  TERMINAL_MAX_LINES, TERMINAL_COPY_MAX_LINES, ansiFgColor
} from '../models/TerminalModels';
import {
  buildTerminalConnectUrl, buildTerminalFallbackUrl, isServerWin32, TerminalConnectOptions
} from '../services/TerminalUrlService';

const TAG = '[Terminal]';
/** 连接超时（对齐 Flutter _kConnectTimeout，仅记录日志不断开） */
const CONNECT_TIMEOUT_MS = 20000;
/** 心跳间隔（对齐 Flutter 20s ping） */
const PING_INTERVAL_MS = 20000;
/** 输出批量刷新间隔（ms）：高频输出合并后一次性更新 UI */
const FLUSH_INTERVAL_MS = 50;
/** 光标闪烁间隔（ms） */
const CURSOR_BLINK_MS = 530;
/** 重连退避上限（对齐 Flutter 15s） */
const RECONNECT_MAX_DELAY_MS = 15000;
/** 断开后等待服务端处理 terminate 的延时（对齐 Flutter 260ms） */
const TERMINATE_DELAY_MS = 260;

/**
 * 终端控制器（对齐 Flutter TerminalController）：
 * - WebSocket 连接 /api/terminal/connect，ready/output/restore/ping/pong/exit/error 协议逐条对齐
 * - 输出进入简化 VT 解析器（SGR 颜色/粗体、\r 覆写、\b、行清除、OSC 剥离），50ms 批量渲染
 * - 手动重连指数退避自动重连、win32 shell 切换、UI 配置持久化、剪贴板复制/粘贴
 */
@ObservedV2
export class TerminalController {
  private static instance: TerminalController | undefined = undefined;

  static getInstance(): TerminalController {
    if (!TerminalController.instance) {
      TerminalController.instance = new TerminalController();
    }
    return TerminalController.instance;
  }

  // ===== 响应式状态 =====
  @Trace connecting: boolean = false;
  @Trace connected: boolean = false;
  @Trace statusText: string = '';
  /** win32 下当前 shell（'powershell' | 'cmd'），仅用于切换 WS URL 参数，不持久化 */
  @Trace currentShell: string = 'powershell';
  @Trace isWin32: boolean = false;
  /** UI 配置（修改必须整体替换实例，保证 V2 刷新） */
  @Trace uiConfig: TerminalUiConfig = TerminalUiConfig.defaults();
  /** 正在输出中的最后一行（未收到换行） */
  @Trace liveText: string = '';
  @Trace liveColor: string = '';
  @Trace liveBold: boolean = false;
  /** 光标可见性（闪烁定时器驱动） */
  @Trace cursorVisible: boolean = true;
  /** 已提交行版本号：每次有新增提交行时自增（供视图监听滚动） */
  @Trace revision: number = 0;

  /** 已提交行数据源（LazyForEach 虚拟化渲染） */
  readonly source: TerminalLineSource = new TerminalLineSource();

  private instanceId: string = 'terminal';
  private ws: webSocket.WebSocket | undefined = undefined;
  private pingTimer: number = -1;
  private reconnectTimer: number = -1;
  private connectTimeoutTimer: number = -1;
  private flushTimer: number = -1;
  private blinkTimer: number = -1;
  private manualClose: boolean = false;
  private autoReconnectDisabled: boolean = false;
  private reconnectAttempt: number = 0;
  private nextConnectUrlOverride: string = '';
  private triedWsSchemeFallback: boolean = false;
  private clientDeviceId: string = '';
  private readonly terminalConnId: string = `conn_${Date.now()}_${Math.floor(Math.random() * 100000)}`;
  private sessionId: string = '';
  private hasRenderedSessionContent: boolean = false;
  private attached: boolean = false;

  // 输出解析缓冲
  private pendingRaw: string = '';
  // SGR 状态（跨消息持续）
  private ansiFg: string = '';
  private ansiBold: boolean = false;

  // 命令历史（会话内持续）
  private history: string[] = [];
  private historyIndex: number = -1;
  private historyDraft: string = '';

  // ===== 生命周期 =====

  /**
   * 页面挂载后调用（对齐 Flutter onInit）：加载 UI 配置并连接。
   * 重复调用被忽略；页面退出时必须调用 detach()。
   */
  async attach(instanceId: string): Promise<void> {
    if (this.attached) {
      return;
    }
    this.attached = true;
    this.instanceId = instanceId.trim().length > 0 ? instanceId.trim() : 'terminal';
    this.isWin32 = isServerWin32();
    this.loadUiConfig();
    this.startBlink();
    await this.connect(false, false);
  }

  /** 页面退出调用（对齐 Flutter onClose）：手动关闭，禁止自动重连 */
  detach(): void {
    if (!this.attached) {
      return;
    }
    this.attached = false;
    this.manualClose = true;
    this.autoReconnectDisabled = true;
    this.stopBlink();
    this.disposeChannel();
  }

  // ===== UI 配置 =====

  private uiConfigStorageKey(): string {
    return `terminal_config_${this.instanceId}`;
  }

  private loadUiConfig(): void {
    try {
      const raw = PreferencesStore.getInstance().getString(this.uiConfigStorageKey(), '');
      if (raw === undefined || raw.trim().length === 0) {
        return;
      }
      const parsed = TerminalUiConfig.tryFromJsonString(raw);
      if (parsed !== undefined) {
        this.uiConfig = parsed;
      }
    } catch (_e) {
      // 配置损坏时忽略，使用默认值
    }
  }

  setUiConfig(next: TerminalUiConfig): void {
    const blinkChanged = next.cursorBlink !== this.uiConfig.cursorBlink;
    this.uiConfig = next;
    if (blinkChanged) {
      this.restartBlink();
    }
  }

  saveUiConfig(): Promise<void> {
    return PreferencesStore.getInstance()
      .setString(this.uiConfigStorageKey(), JSON.stringify(this.uiConfig.toJson()))
      .catch((_e: Object): void => {
        // 持久化失败不阻塞
      });
  }

  /** 取消未保存的修改（对齐 Flutter _openSettings 关闭时回滚快照） */
  restoreFromJsonString(text: string): void {
    const parsed = TerminalUiConfig.tryFromJsonString(text);
    if (parsed !== undefined) {
      this.setUiConfig(parsed);
    }
  }

  // ===== 光标闪烁 =====

  private startBlink(): void {
    this.cursorVisible = true;
    if (this.blinkTimer >= 0 || !this.uiConfig.cursorBlink) {
      return;
    }
    this.blinkTimer = setInterval((): void => {
      this.cursorVisible = !this.cursorVisible;
    }, CURSOR_BLINK_MS);
  }

  private stopBlink(): void {
    if (this.blinkTimer >= 0) {
      clearInterval(this.blinkTimer);
      this.blinkTimer = -1;
    }
    this.cursorVisible = true;
  }

  private restartBlink(): void {
    this.stopBlink();
    this.startBlink();
  }

  // ===== 连接管理 =====

  async connect(manual: boolean = false, forceNew: boolean = false): Promise<void> {
    if (this.connecting) {
      console.info(`${TAG} connect() ignored: connecting`);
      return;
    }
    if (this.connected) {
      console.info(`${TAG} connect() ignored: connected`);
      return;
    }
    if (manual) {
      this.autoReconnectDisabled = false;
      this.triedWsSchemeFallback = false;
    }
    this.manualClose = false;
    this.connecting = true;
    this.statusText = L10n.t('terminal_connecting', '连接中...');
    if (this.clientDeviceId.length === 0) {
      try {
        this.clientDeviceId = DeviceFingerprint.getOrCreateStorageId();
      } catch (_e) {
        this.clientDeviceId = this.instanceId.trim().length > 0 ? this.instanceId.trim() : 'terminal';
      }
    }

    const opts = new TerminalConnectOptions();
    opts.cols = 100;
    opts.rows = 30;
    opts.shell = this.isWin32 ? this.currentShell : '';
    opts.clientDeviceId = this.clientDeviceId;
    opts.terminalConnId = this.terminalConnId;
    opts.forceNew = forceNew;
    let url = this.nextConnectUrlOverride;
    this.nextConnectUrlOverride = '';
    if (url.length === 0) {
      try {
        url = await buildTerminalConnectUrl(opts);
      } catch (_e) {
        url = '';
      }
    }
    if (url.length === 0) {
      console.error(`${TAG} connect failed: url is empty (baseUrl or token missing)`);
      this.connecting = false;
      this.connected = false;
      this.statusText = L10n.t('terminal_connection_failed', '终端连接失败');
      ToastUtil.show(this.statusText);
      return;
    }

    try {
      this.disposeChannel();
      const ws = webSocket.createWebSocket();
      ws.on('message', (_err: Object, value: string | ArrayBuffer): void => {
        this.handleMessage(value);
      });
      ws.on('error', (err: Object): void => {
        this.handleSocketError(err);
      });
      ws.on('close', (_err: Object, _value: webSocket.CloseResult): void => {
        this.handleSocketClose();
      });
      this.ws = ws;
      this.connectTimeoutTimer = setTimeout((): void => {
        this.connectTimeoutTimer = -1;
        if (this.connecting && !this.connected) {
          console.info(`${TAG} connect timeout: no first message in 20s`);
        }
      }, CONNECT_TIMEOUT_MS);
      ws.connect(url, (err: Object, _value: boolean): void => {
        if (err) {
          console.error(`${TAG} ws connect failed: ${JSON.stringify(err)}`);
          this.handleSocketError(err);
          return;
        }
        console.info(`${TAG} ws connected, waiting for server first message`);
      });
      this.startPing();
    } catch (e) {
      console.error(`${TAG} ws create failed: ${e}`);
      this.connecting = false;
      this.connected = false;
      this.statusText = L10n.t('terminal_connection_failed', '终端连接失败');
      ToastUtil.show(this.statusText);
      this.scheduleReconnect();
    }
  }

  /** 手动断开（对齐 Flutter disconnect） */
  disconnect(): void {
    this.manualClose = true;
    const msg: Record<string, string> = { 'type': 'close' };
    this.sendJson(msg);
    this.disposeChannel();
    this.connected = false;
    this.connecting = false;
    this.statusText = L10n.t('terminal_disconnected', '连接已断开');
  }

  /** 终止远端会话（对齐 Flutter terminateSession） */
  terminateSession(): Promise<void> {
    this.manualClose = true;
    this.autoReconnectDisabled = true;
    const terminateMsg: Record<string, string> = { 'type': 'terminate' };
    this.sendJson(terminateMsg);
    const closeMsg: Record<string, string> = { 'type': 'close', 'reason': 'terminate' };
    this.sendJson(closeMsg);
    return new Promise<void>((resolve: () => void) => {
      setTimeout((): void => {
        this.disposeChannel();
        this.connected = false;
        this.connecting = false;
        this.statusText = L10n.t('terminal_disconnected', '连接已断开');
        resolve();
      }, TERMINATE_DELAY_MS);
    });
  }

  /** 立即重连（对齐 Flutter reconnectNow） */
  reconnectNow(): void {
    this.disconnect();
    this.reconnectAttempt = 0;
    void this.connect(true, false);
  }

  /** 发送 Ctrl+C 中断运行中的命令 */
  interruptRunningCommand(): void {
    if (!this.connected) {
      return;
    }
    const msg: Record<string, string> = { 'type': 'input', 'data': '\u0003' };
    this.sendJson(msg);
  }

  /**
   * 仅当服务器为 win32 时有效：切换后断开并重连（新 URL 带 shell 参数）。
   */
  switchShell(shell: string): void {
    const s = shell === 'cmd' ? 'cmd' : 'powershell';
    if (this.currentShell === s) {
      return;
    }
    this.currentShell = s;
    this.disconnect();
    this.reconnectAttempt = 0;
    void this.connect(true, true);
  }

  // ===== 命令输入与历史 =====

  /** 发送一行命令（自动追加回车；记录历史，对齐 xterm 回车键发送 '\r'） */
  sendCommand(text: string): void {
    const msg: Record<string, string> = { 'type': 'input', 'data': `${text}\r` };
    this.sendJson(msg);
    this.recordCommand(text);
  }

  /** 仅发送原始输入（不追加回车、不记录历史），供粘贴直发等场景 */
  sendRawInput(data: string): void {
    if (data.length === 0) {
      return;
    }
    const msg: Record<string, string> = { 'type': 'input', 'data': data };
    this.sendJson(msg);
  }

  private recordCommand(cmd: string): void {
    const t = cmd.trim();
    if (t.length === 0) {
      return;
    }
    const last = this.history.length > 0 ? this.history[this.history.length - 1] : '';
    if (last !== t) {
      this.history.push(t);
      if (this.history.length > 200) {
        this.history.splice(0, this.history.length - 200);
      }
    }
    this.historyIndex = -1;
    this.historyDraft = '';
  }

  /** 上一条历史（无历史返回原文） */
  historyBack(current: string): string {
    if (this.history.length === 0) {
      return current;
    }
    if (this.historyIndex === -1) {
      this.historyDraft = current;
      this.historyIndex = this.history.length - 1;
    } else if (this.historyIndex > 0) {
      this.historyIndex--;
    }
    return this.history[this.historyIndex] ?? current;
  }

  /** 下一条历史（越过最早一条回到未发送草稿） */
  historyForward(): string {
    if (this.historyIndex === -1) {
      return '';
    }
    this.historyIndex++;
    if (this.historyIndex >= this.history.length) {
      this.historyIndex = -1;
      return this.historyDraft;
    }
    return this.history[this.historyIndex] ?? '';
  }

  // ===== 剪贴板 =====

  /** 复制最近缓冲到剪贴板（无选区渲染，取最近 500 行，对齐 Flutter 复制后 toast 提示） */
  copyBufferToClipboard(): void {
    const lines: string[] = [];
    const total = this.source.totalCount();
    const from = Math.max(0, total - TERMINAL_COPY_MAX_LINES);
    for (let i = from; i < total; i++) {
      lines.push(this.source.getData(i).text);
    }
    if (this.liveText.length > 0) {
      lines.push(this.liveText);
    }
    const text = lines.join('\n');
    if (text.trim().length === 0) {
      return;
    }
    try {
      const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
      pasteboard.getSystemPasteboard().setPasteData(data);
      ToastUtil.show(L10n.t('quick_share_copied', '已复制'));
    } catch (_e) {
      // 剪贴板不可用时忽略
    }
  }

  /** 读取系统剪贴板文本（放入命令输入行，由用户回车发送） */
  async pasteFromClipboard(): Promise<string> {
    try {
      const pasteData = await pasteboard.getSystemPasteboard().getPasteData();
      return pasteData?.getPrimaryText() ?? '';
    } catch (_e) {
      return '';
    }
  }

  // ===== WS 消息处理（对齐 Flutter _handleServerMessage / onError / onDone） =====

  private markConnected(): void {
    this.connected = true;
    this.statusText = '';
    this.autoReconnectDisabled = false;
    this.reconnectAttempt = 0;
  }

  private handleMessage(value: string | ArrayBuffer): void {
    const text = typeof value === 'string' ? value : TerminalController.decodeBytes(value);
    this.cancelConnectTimeout();
    const decoded = TerminalController.tryParseJson(text);
    if (this.connecting) {
      console.info(`${TAG} first server message received`);
    }
    this.connecting = false;
    if (decoded === undefined) {
      // 非 JSON：原始终端数据直写
      this.markConnected();
      this.feed(text);
      return;
    }
    const typeVal = decoded['type'];
    const type = typeVal === undefined || typeVal === null ? '' : `${typeVal}`;
    if (type === 'ready') {
      const sid = TerminalController.strField(decoded, 'sessionId');
      if (this.sessionId.length > 0 && this.sessionId !== sid) {
        this.hasRenderedSessionContent = false;
      }
      this.sessionId = sid;
      this.markConnected();
      this.triedWsSchemeFallback = false;
      return;
    }
    if (type === 'output') {
      this.hasRenderedSessionContent = true;
      this.markConnected();
      this.triedWsSchemeFallback = false;
      this.feed(TerminalController.strField(decoded, 'data'));
      return;
    }
    if (type === 'restore') {
      const sid = TerminalController.strField(decoded, 'sessionId');
      const data = TerminalController.strField(decoded, 'data');
      if (data.length === 0) {
        return;
      }
      if (this.hasRenderedSessionContent && this.sessionId.length > 0 && this.sessionId === sid) {
        return;
      }
      if (sid.length > 0) {
        this.sessionId = sid;
      }
      this.hasRenderedSessionContent = true;
      this.feed(data);
      return;
    }
    if (type === 'ping') {
      const msg: Record<string, string> = { 'type': 'ping' };
      this.sendJson(msg);
      return;
    }
    if (type === 'pong') {
      return;
    }
    if (type === 'exit') {
      this.connected = false;
      this.statusText = L10n.t('terminal_disconnected', '连接已断开');
      this.scheduleReconnect();
      return;
    }
    if (type === 'error') {
      this.handleServerError(decoded);
      return;
    }
  }

  private handleServerError(decoded: Record<string, Object>): void {
    const code = TerminalController.strField(decoded, 'code');
    const message = TerminalController.strField(decoded, 'message');
    const codeUpper = code.trim().toUpperCase();
    const noPermission = TerminalController.isNoPermissionError(code, message);
    const nonRetryable = TerminalController.isNonRetryableErrorCode(code);
    if (codeUpper === 'TERMINAL_DISABLED') {
      this.manualClose = true;
      this.autoReconnectDisabled = true;
      if (message.length > 0) {
        this.statusText = message;
        ToastUtil.show(message);
      }
    } else if (noPermission) {
      this.manualClose = true;
      this.autoReconnectDisabled = true;
      this.statusText = L10n.t('terminal_access_denied', '无权限访问终端');
      ToastUtil.show(this.statusText);
    } else if (codeUpper === 'TERMINAL_TAKEN_OVER') {
      this.manualClose = true;
      this.autoReconnectDisabled = true;
      this.statusText = L10n.t('terminal_taken_over', '终端已在其他页面打开');
      ToastUtil.show(this.statusText);
    } else if (nonRetryable) {
      this.autoReconnectDisabled = true;
      if (message.length > 0) {
        this.statusText = message;
      }
    } else if (message.length > 0) {
      ToastUtil.show(message);
    }
    if (message.length > 0) {
      this.feed(`\r\n${message}\r\n`);
    }
    this.connected = false;
    this.connecting = false;
    if (noPermission || nonRetryable) {
      this.disposeChannel();
    }
  }

  private handleSocketError(err: Object): void {
    console.error(`${TAG} ws onError: ${JSON.stringify(err)}`);
    this.cancelConnectTimeout();
    const raw = `${JSON.stringify(err)}`;
    if (!this.triedWsSchemeFallback
      && (raw.includes('WRONG_VERSION_NUMBER') || raw.includes('HandshakeException'))) {
      const fallback = buildTerminalFallbackUrl(this.clientDeviceId, this.terminalConnId);
      if (fallback.length > 0) {
        this.triedWsSchemeFallback = true;
        this.nextConnectUrlOverride = fallback;
        this.disposeChannel();
        this.connecting = false;
        this.connected = false;
        this.reconnectAttempt = 0;
        setTimeout((): void => {
          void this.connect(false, false);
        }, 120);
        return;
      }
    }
    const noPermission = TerminalController.isNoPermissionError('', raw);
    if (noPermission) {
      this.manualClose = true;
      this.autoReconnectDisabled = true;
      this.statusText = L10n.t('terminal_access_denied', '无权限访问终端');
      ToastUtil.show(this.statusText);
    }
    this.disposeChannel();
    this.connecting = false;
    this.connected = false;
    if (!noPermission) {
      this.statusText = L10n.t('terminal_connection_failed', '终端连接失败');
      ToastUtil.show(this.statusText);
    }
    this.scheduleReconnect();
  }

  private handleSocketClose(): void {
    console.info(`${TAG} ws onClose: connection closed`);
    this.cancelConnectTimeout();
    this.disposeChannel();
    this.connecting = false;
    this.connected = false;
    this.statusText = L10n.t('terminal_disconnected', '连接已断开');
    this.scheduleReconnect();
  }

  // ===== 重连退避 =====

  private scheduleReconnect(): void {
    if (this.manualClose || this.autoReconnectDisabled || this.reconnectTimer >= 0) {
      return;
    }
    this.reconnectAttempt += 1;
    const delayMs = TerminalController.computeBackoffMs(this.reconnectAttempt);
    this.reconnectTimer = setTimeout((): void => {
      this.reconnectTimer = -1;
      void this.connect(false, false);
    }, delayMs);
  }

  private static computeBackoffMs(attempt: number): number {
    const exp = attempt > 8 ? 8 : attempt;
    const base = 500 * Math.pow(2, exp);
    return base > RECONNECT_MAX_DELAY_MS ? RECONNECT_MAX_DELAY_MS : base;
  }

  // ===== 心跳与通道清理 =====

  private startPing(): void {
    if (this.pingTimer >= 0) {
      return;
    }
    this.pingTimer = setInterval((): void => {
      if (!this.connected) {
        return;
      }
      const msg: Record<string, string> = { 'type': 'ping' };
      this.sendJson(msg);
    }, PING_INTERVAL_MS);
  }

  private cancelConnectTimeout(): void {
    if (this.connectTimeoutTimer >= 0) {
      clearTimeout(this.connectTimeoutTimer);
      this.connectTimeoutTimer = -1;
    }
  }

  private disposeChannel(): void {
    this.cancelConnectTimeout();
    if (this.reconnectTimer >= 0) {
      clearTimeout(this.reconnectTimer);
      this.reconnectTimer = -1;
    }
    if (this.pingTimer >= 0) {
      clearInterval(this.pingTimer);
      this.pingTimer = -1;
    }
    if (this.flushTimer >= 0) {
      clearTimeout(this.flushTimer);
      this.flushTimer = -1;
    }
    const ws = this.ws;
    this.ws = undefined;
    if (ws !== undefined) {
      try {
        ws.off('message');
        ws.off('error');
        ws.off('close');
      } catch (_e) {
        // 回调可能未注册
      }
      try {
        ws.close();
      } catch (_e) {
        // 已断开
      }
    }
  }

  private sendJson(obj: Record<string, string>): void {
    const ws = this.ws;
    if (ws === undefined) {
      return;
    }
    try {
      ws.send(JSON.stringify(obj), (_err: Object): void => {
        // 发送失败由 error/close 回调统一处理
      });
    } catch (_e) {
      // 通道已关闭
    }
  }

  // ===== 输出解析与渲染 =====

  /** 收到服务端终端输出：入缓冲，50ms 批量解析刷新（高频输出合并） */
  private feed(data: string): void {
    if (data.length === 0) {
      return;
    }
    this.pendingRaw += data;
    if (this.flushTimer >= 0) {
      return;
    }
    this.flushTimer = setTimeout((): void => {
      this.flushTimer = -1;
      this.flushNow();
    }, FLUSH_INTERVAL_MS);
  }

  private flushNow(): void {
    const data = this.pendingRaw;
    this.pendingRaw = '';
    if (data.length === 0) {
      return;
    }
    const newCommitted: TerminalLine[] = [];
    let liveBuf = this.liveText;
    let liveColor = this.liveColor;
    let liveBold = this.liveBold;
    let clearAll = false;

    // 简化 VT 状态机：0 正文 / 1 ESC / 2 CSI / 3 OSC / 4 OSC 退出符
    let mode = 0;
    let csiParams = '';
    for (let i = 0; i < data.length; i++) {
      const code = data.charCodeAt(i);
      const ch = data.charAt(i);
      if (mode === 1) {
        if (ch === '[') {
          mode = 2;
          csiParams = '';
        } else if (ch === ']') {
          mode = 3;
        } else {
          mode = 0;
        }
        continue;
      }
      if (mode === 2) {
        if (code >= 0x40 && code <= 0x7e) {
          mode = 0;
          if (ch === 'm') {
            // SGR：更新行颜色/粗体（整行单色近似：以行内最后一次设置为准）
            const params = csiParams.split(';');
            for (let p = 0; p < params.length; p++) {
              const raw = params[p].trim();
              const codeNum = raw.length === 0 ? 0 : parseInt(raw);
              if (Number.isNaN(codeNum)) {
                continue;
              }
              if (codeNum === 0) {
                this.ansiFg = '';
                this.ansiBold = false;
              } else if (codeNum === 1) {
                this.ansiBold = true;
              } else if (codeNum === 22) {
                this.ansiBold = false;
              } else if (codeNum === 39) {
                this.ansiFg = '';
              } else if (codeNum >= 30 && codeNum <= 37) {
                this.ansiFg = ansiFgColor(codeNum - 30);
              } else if (codeNum >= 90 && codeNum <= 97) {
                this.ansiFg = ansiFgColor(codeNum - 90 + 8);
              }
              // 其余（256 色/背景色/斜体等）忽略，保持当前状态
            }
            liveColor = this.ansiFg;
            liveBold = this.ansiBold;
          } else if (ch === 'K') {
            // 行内擦除：近似为清空当前行
            liveBuf = '';
          } else if (ch === 'J') {
            const nums = csiParams.split(';');
            const first = nums.length > 0 && nums[0].length > 0 ? parseInt(nums[0]) : 0;
            if (first === 2 || first === 3) {
              clearAll = true;
            }
          }
          // 其余 CSI（光标移动等）忽略
        } else {
          csiParams += ch;
        }
        continue;
      }
      if (mode === 3) {
        if (code === 0x07) {
          mode = 0;
        } else if (code === 0x1b) {
          mode = 4;
        }
        continue;
      }
      if (mode === 4) {
        mode = 0;
        continue;
      }
      if (code === 0x1b) {
        mode = 1;
        continue;
      }
      if (ch === '\n') {
        newCommitted.push(new TerminalLine(liveBuf, liveColor, liveBold));
        liveBuf = '';
        liveColor = this.ansiFg;
        liveBold = this.ansiBold;
        continue;
      }
      if (ch === '\r') {
        liveBuf = '';
        continue;
      }
      if (code === 0x08) {
        liveBuf = liveBuf.length > 0 ? liveBuf.substring(0, liveBuf.length - 1) : '';
        continue;
      }
      if (code === 0x09) {
        liveBuf += '    ';
        continue;
      }
      if (code < 0x20) {
        continue;
      }
      liveBuf += ch;
    }

    if (clearAll) {
      newCommitted.length = 0;
      liveBuf = '';
      this.source.reset([]);
    } else {
      for (const line of newCommitted) {
        this.source.append(line);
      }
    }
    this.liveText = liveBuf;
    this.liveColor = liveColor;
    this.liveBold = liveBold;
    if (clearAll || newCommitted.length > 0) {
      this.source.trimTo(TERMINAL_MAX_LINES);
      this.revision++;
    }
  }

  // ===== 工具 =====

  private static decodeBytes(buf: ArrayBuffer): string {
    try {
      const decoder = new util.TextDecoder('utf-8');
      return decoder.decodeToString(new Uint8Array(buf));
    } catch (_e) {
      return '';
    }
  }

  private static tryParseJson(text: string): Record<string, Object> | undefined {
    const t = text.trim();
    if (t.length === 0 || (t.charAt(0) !== '{' && t.charAt(0) !== '[')) {
      return undefined;
    }
    try {
      const obj = JSON.parse(t) as Object;
      if (obj !== null && typeof obj === 'object' && !Array.isArray(obj)) {
        return obj as Record<string, Object>;
      }
    } catch (_e) {
      // 非 JSON
    }
    return undefined;
  }

  private static strField(decoded: Record<string, Object>, key: string): string {
    const v = decoded[key];
    return v === undefined || v === null ? '' : `${v}`;
  }

  private static isNoPermissionError(code: string, message: string): boolean {
    const c = code.trim().toUpperCase();
    if (c === 'TERMINAL_ACCESS_DENIED' || c === 'TERMINAL_ADMIN_ONLY' || c === 'TERMINAL_API_NOT_ALLOWED') {
      return true;
    }
    const m = message.trim().toLowerCase();
    if (m.length === 0) {
      return false;
    }
    if (m.includes('access denied') || m.includes('permission denied') || m.includes('no permission')
      || m.includes('forbidden') || m.includes('unauthorized')) {
      return true;
    }
    return message.includes('无权限') || message.includes('权限不足');
  }

  private static isNonRetryableErrorCode(code: string): boolean {
    const c = code.trim().toUpperCase();
    return c === 'TERMINAL_SESSION_LIMIT_REACHED' || c === 'TERMINAL_TAKEN_OVER'
      || c === 'TERMINAL_DISABLED' || c === 'TERMINAL_AUTH_REQUIRED'
      || c === 'TERMINAL_INVALID_TOKEN' || c === 'TOKEN_EXPIRED';
  }
}

/** 默认配置快照（设置页"恢复默认"用） */
export function terminalDefaultConfigJson(): string {
  return JSON.stringify(TerminalUiConfig.defaults().toJson());
}
