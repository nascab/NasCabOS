import { common, ApplicationStateChangeCallback } from '@kit.AbilityKit';
import { CurrentUserStore } from '../../../core/user/CurrentUserStore';
import { MonitorApiService } from '../services/MonitorApiServices';
import { MonitorCpuInfo, MonitorMetrics } from '../models/MonitorModels';

/** 格式化 CPU 信息（对齐 Flutter monitor_view._formatCpuInfo）：厂商 型号 N(P+E) Cores */
export function formatMonitorCpuInfo(info: MonitorCpuInfo | undefined): string {
  if (info === undefined) {
    return '';
  }
  let text = '';
  if (info.manufacturer.length > 0) {
    text += `${info.manufacturer} `;
  }
  if (info.brand.length > 0) {
    text += `${info.brand} `;
  }
  if (info.cores > 0) {
    text += `${info.cores}`;
    if (info.performanceCores >= 0 && info.efficiencyCores >= 0) {
      text += `(${info.performanceCores}+${info.efficiencyCores})`;
    }
    text += ' Cores';
  }
  return text;
}

/**
 * 硬件指标控制器（对齐 Flutter HwMetricsController）：
 * 每 3 秒轮询 /api/hw/metrics，仅前台 + 已登录时拉取；应用切后台暂停、回前台续轮。
 * 全局单例（Flutter Get.put permanent 对应实现）。
 */
@ObservedV2
export class MonitorController {
  private static instance: MonitorController | undefined = undefined;

  static getInstance(): MonitorController {
    if (!MonitorController.instance) {
      MonitorController.instance = new MonitorController();
    }
    return MonitorController.instance;
  }

  private static readonly INTERVAL_MS: number = 3000;

  /** 最近一次成功拉取的指标（失败时置 undefined，对齐 Flutter _metrics.value = null） */
  @Trace metrics: MonitorMetrics | undefined = undefined;
  /** 最近一次失败信息（成功后清空） */
  @Trace lastError: string = '';

  private running: boolean = false;
  private fetching: boolean = false;
  private isForeground: boolean = true;
  private timer: number = -1;
  private lastRequestAt: number = 0;
  /** 应用前后台监听（对齐 Flutter _LifecycleObserver，注册后常驻） */
  private appContext: common.ApplicationContext | undefined = undefined;
  private stateCallback: ApplicationStateChangeCallback | undefined = undefined;

  private constructor() {
  }

  // ===== 生命周期（对齐 start/stop 与 _LifecycleObserver） =====

  start(context?: common.Context): void {
    if (this.running) {
      return;
    }
    this.running = true;
    if (context !== undefined && this.appContext === undefined) {
      this.registerLifecycleObserver(context);
    }
    this.scheduleNext();
  }

  stop(): void {
    this.running = false;
    this.clearTimer();
  }

  private registerLifecycleObserver(context: common.Context): void {
    try {
      const appContext = context.getApplicationContext();
      const callback: ApplicationStateChangeCallback = {
        onApplicationForeground: (): void => {
          this.onApplicationForeground();
        },
        onApplicationBackground: (): void => {
          this.onApplicationBackground();
        }
      };
      appContext.on('applicationStateChange', callback);
      this.appContext = appContext;
      this.stateCallback = callback;
    } catch (_e) {
      // 前后台监听注册失败不阻塞轮询（仅失去后台暂停能力）
    }
  }

  private onApplicationForeground(): void {
    if (!this.isForeground) {
      this.isForeground = true;
      if (this.running) {
        this.scheduleNext();
      }
    }
  }

  private onApplicationBackground(): void {
    if (this.isForeground) {
      this.isForeground = false;
      this.clearTimer();
    }
  }

  // ===== 轮询调度（对齐 _scheduleNext/_tick） =====

  private get shouldSchedule(): boolean {
    return this.running && this.isForeground;
  }

  private get shouldFetch(): boolean {
    return this.shouldSchedule && CurrentUserStore.getInstance().isLoggedIn;
  }

  private clearTimer(): void {
    if (this.timer >= 0) {
      clearTimeout(this.timer);
      this.timer = -1;
    }
  }

  private scheduleNext(): void {
    if (!this.shouldSchedule) {
      return;
    }
    if (this.timer >= 0) {
      return;
    }
    const now = Date.now();
    const elapsed = this.lastRequestAt <= 0
      ? MonitorController.INTERVAL_MS
      : now - this.lastRequestAt;
    const delay = elapsed >= MonitorController.INTERVAL_MS
      ? 0
      : MonitorController.INTERVAL_MS - elapsed;
    this.timer = setTimeout((): void => {
      this.timer = -1;
      void this.tick();
    }, delay);
  }

  private async tick(): Promise<void> {
    if (!this.shouldSchedule) {
      return;
    }
    if (!this.shouldFetch) {
      this.clearTimer();
      this.scheduleNext();
      return;
    }
    if (this.fetching) {
      this.clearTimer();
      this.scheduleNext();
      return;
    }

    this.fetching = true;
    this.lastRequestAt = Date.now();
    try {
      const resp = await MonitorApiService.getMetrics();
      if (resp.success) {
        this.metrics = resp.data;
        this.lastError = '';
      } else {
        this.lastError = resp.message;
        this.metrics = undefined;
      }
    } catch (e) {
      this.lastError = `${e instanceof Error ? e.message : JSON.stringify(e)}`;
    } finally {
      this.fetching = false;
    }

    this.clearTimer();
    this.scheduleNext();
  }
}
