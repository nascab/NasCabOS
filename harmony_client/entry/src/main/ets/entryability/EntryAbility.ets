import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import type { Configuration } from '@ohos.app.ability.Configuration';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { AppBootstrap } from '../AppBootstrap';
import { ThemeManager } from '../core/theme/ThemeManager';

const DOMAIN = 0x0000;

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    try {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    } catch (err) {
      hilog.error(DOMAIN, 'NasCab', 'Failed to set colorMode: %{public}s', JSON.stringify(err));
    }
  }

  async onWindowStageCreate(windowStage: window.WindowStage): Promise<void> {
    // 等待初始化完成后再加载页面，保证 preferences 就绪（服务器列表等本地数据可读取）
    try {
      await AppBootstrap.init(this.context, this.context.config?.colorMode);
      hilog.info(DOMAIN, 'NasCab', 'App bootstrap completed');
    } catch (err) {
      hilog.error(DOMAIN, 'NasCab', 'Bootstrap failed: %{public}s', JSON.stringify(err));
    }
    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, 'NasCab', 'Failed to load content: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, 'NasCab', 'Succeeded in loading content');
    });
  }

  /** 系统配置变化（深浅色切换）：通知 ThemeManager，system 模式下广播刷新 */
  onConfigurationUpdate(newConfig: Configuration): void {
    ThemeManager.getInstance().onSystemColorModeChanged(newConfig.colorMode);
  }
}
