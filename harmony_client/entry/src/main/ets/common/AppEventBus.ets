type AuthSessionExpiredListener = () => void;
type GenericListener = (data: string) => void;

export class AppEventBus {
  private static authSessionExpiredListeners: AuthSessionExpiredListener[] = [];
  private static genericListeners: Map<string, GenericListener[]> = new Map();

  static onAuthSessionExpired(listener: AuthSessionExpiredListener): void {
    AppEventBus.authSessionExpiredListeners.push(listener);
  }

  static emitAuthSessionExpired(): void {
    for (const listener of AppEventBus.authSessionExpiredListeners) {
      listener();
    }
  }

  static on(event: string, listener: GenericListener): void {
    let list = AppEventBus.genericListeners.get(event);
    if (!list) {
      list = [];
      AppEventBus.genericListeners.set(event, list);
    }
    list.push(listener);
  }

  static off(event: string, listener: GenericListener): void {
    const list = AppEventBus.genericListeners.get(event);
    if (!list) {
      return;
    }
    const idx = list.indexOf(listener);
    if (idx >= 0) {
      list.splice(idx, 1);
    }
  }

  static emit(event: string, data: string = ''): void {
    const list = AppEventBus.genericListeners.get(event);
    if (!list) {
      return;
    }
    for (const listener of list) {
      listener(data);
    }
  }
}
