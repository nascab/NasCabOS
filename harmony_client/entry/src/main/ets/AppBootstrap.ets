import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { PreferencesStore } from './core/storage/PreferencesStore';
import { APIClient } from './core/network/APIClient';
import { CurrentUserStore } from './core/user/CurrentUserStore';
import { P2PService } from './p2p/P2PService';
import { L10n } from './core/localization/L10n';
import { LanguageService } from './core/localization/LanguageService';
import { ThemeManager } from './core/theme/ThemeManager';

export class AppBootstrap {
  static async init(context: common.Context, systemColorMode?: ConfigurationConstant.ColorMode): Promise<void> {
    await PreferencesStore.getInstance().init(context);
    await L10n.init(context.resourceManager);
    await LanguageService.getInstance().init();
    ThemeManager.getInstance().init(context.getApplicationContext(), systemColorMode);
    APIClient.getInstance().loadStoredTokens();
    CurrentUserStore.getInstance().loadFromCache();
    P2PService.getInstance();
  }
}
