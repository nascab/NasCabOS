import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { AppBootstrap } from '../AppBootstrap';

const DOMAIN = 0x0000;

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    try {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    } catch (err) {
      hilog.error(DOMAIN, 'NasCab', 'Failed to set colorMode: %{public}s', JSON.stringify(err));
    }
    AppBootstrap.init(this.context).then(() => {
      hilog.info(DOMAIN, 'NasCab', 'App bootstrap completed');
    }).catch((err: Object) => {
      hilog.error(DOMAIN, 'NasCab', 'Bootstrap failed: %{public}s', JSON.stringify(err));
    });
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, 'NasCab', 'Failed to load content: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, 'NasCab', 'Succeeded in loading content');
    });
  }
}
