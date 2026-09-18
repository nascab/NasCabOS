import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import { wantAgent } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { WindowStore } from '../../common/WindowStore';

/**
 * 传输类后台保活（对齐 Flutter WakelockPlus + 前台服务语义的最小实现）：
 * - 引用计数：首个任务开始时申请长时任务（TASK_KEEPING）并保持屏幕常亮，归零时释放
 * - 全部容错：无权限/模拟器不支持时静默跳过，仅失去后台保活能力，不阻断上传
 */
export class BackgroundWorkKeeper {
  private static refCount: number = 0;
  private static started: boolean = false;

  /** 传输任务开始时调用 */
  static async acquire(): Promise<void> {
    BackgroundWorkKeeper.refCount += 1;
    if (BackgroundWorkKeeper.started) {
      return;
    }
    BackgroundWorkKeeper.started = true;
    try {
      const ctx = WindowStore.appContext;
      if (!ctx) {
        return;
      }
      const info: wantAgent.WantAgentInfo = {
        wants: [{
          bundleName: ctx.abilityInfo.bundleName,
          abilityName: ctx.abilityInfo.name
        }],
        operationType: wantAgent.OperationType.START_ABILITY,
        requestCode: 0,
        wantAgentFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
      };
      const agent = await wantAgent.getWantAgent(info);
      await backgroundTaskManager.startBackgroundRunning(ctx,
        backgroundTaskManager.BackgroundMode.TASK_KEEPING, agent);
    } catch (_e) {
      // 长时任务申请失败（无 TASK_KEEPING 特权等）：仅前台继续，不阻断传输
    }
    BackgroundWorkKeeper.keepScreenOn(true);
  }

  /** 传输任务结束时调用（与 acquire 配对） */
  static async release(): Promise<void> {
    if (BackgroundWorkKeeper.refCount > 0) {
      BackgroundWorkKeeper.refCount -= 1;
    }
    if (BackgroundWorkKeeper.refCount > 0) {
      return;
    }
    BackgroundWorkKeeper.keepScreenOn(false);
    if (!BackgroundWorkKeeper.started) {
      return;
    }
    BackgroundWorkKeeper.started = false;
    try {
      const ctx = WindowStore.appContext;
      if (ctx) {
        await backgroundTaskManager.stopBackgroundRunning(ctx);
      }
    } catch (_e) {
      // 任务可能未成功申请过
    }
  }

  /** 对齐 Flutter WakelockPlus：传输期间保持屏幕常亮（仅前台窗口生效） */
  private static keepScreenOn(enable: boolean): void {
    try {
      const w = WindowStore.getMainWindow();
      if (w) {
        w.setWindowKeepScreenOn(enable);
      }
    } catch (_e) {
      // 忽略窗口获取失败
    }
  }
}
