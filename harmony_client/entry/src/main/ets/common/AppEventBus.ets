type AuthSessionExpiredListener = () => void;

export class AppEventBus {
  private static authSessionExpiredListeners: AuthSessionExpiredListener[] = [];

  static onAuthSessionExpired(listener: AuthSessionExpiredListener): void {
    AppEventBus.authSessionExpiredListeners.push(listener);
  }

  static emitAuthSessionExpired(): void {
    for (const listener of AppEventBus.authSessionExpiredListeners) {
      listener();
    }
  }
}
