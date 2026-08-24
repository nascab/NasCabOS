import { common } from '@kit.AbilityKit';
import { PreferencesStore } from './core/storage/PreferencesStore';
import { APIClient } from './core/network/APIClient';
import { CurrentUserStore } from './core/user/CurrentUserStore';
import { P2PService } from './p2p/P2PService';

export class AppBootstrap {
  static async init(context: common.Context): Promise<void> {
    await PreferencesStore.getInstance().init(context);
    APIClient.getInstance().loadStoredTokens();
    CurrentUserStore.getInstance().loadFromCache();
    P2PService.getInstance();
  }
}
