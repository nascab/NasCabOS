import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { AppEventBus } from '../../common/AppEventBus';
import { PreferencesStore } from '../storage/PreferencesStore';
import { CacheKeys } from '../storage/CacheKeys';

/** 主题模式（对齐 Flutter ThemeManager） */
export type ThemeMode = 'light' | 'dark' | 'system';

/**
 * 全局主题管理（对齐 Flutter ThemeManager + Get.changeThemeMode）。
 * 通过 ApplicationContext.setColorMode 全局生效，并持久化用户选择。
 * 额外跟踪系统实际深浅色（system 模式下用于解析真实色板），变化时广播刷新。
 */
export class ThemeManager {
  private static instance: ThemeManager | undefined = undefined;
  static readonly EVENT_THEME_CHANGED: string = 'themeChanged';

  private currentMode: ThemeMode = 'system';
  private appContext: common.ApplicationContext | undefined = undefined;
  private systemColorMode: ConfigurationConstant.ColorMode =
    ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET;

  static getInstance(): ThemeManager {
    if (!ThemeManager.instance) {
      ThemeManager.instance = new ThemeManager();
    }
    return ThemeManager.instance;
  }

  /** Ability 启动后调用一次：恢复保存的模式并应用到窗口 */
  init(appContext: common.ApplicationContext, systemColorMode?: ConfigurationConstant.ColorMode): void {
    this.appContext = appContext;
    if (systemColorMode !== undefined) {
      this.systemColorMode = systemColorMode;
    }
    const saved = PreferencesStore.getInstance().getString(CacheKeys.THEME_MODE, 'system') ?? 'system';
    this.currentMode = ThemeManager.normalize(saved);
    this.applyToWindow(this.currentMode);
  }

  getThemeMode(): ThemeMode {
    return this.currentMode;
  }

  /** 当前生效是否为深色（system 模式按系统实际值解析） */
  isDark(): boolean {
    if (this.currentMode === 'light') {
      return false;
    }
    if (this.currentMode === 'dark') {
      return true;
    }
    return this.systemColorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
  }

  async saveThemeMode(mode: ThemeMode): Promise<void> {
    if (mode === this.currentMode) {
      return;
    }
    this.currentMode = mode;
    await PreferencesStore.getInstance().setString(CacheKeys.THEME_MODE, mode);
    this.applyToWindow(mode);
    AppEventBus.emit(ThemeManager.EVENT_THEME_CHANGED, mode);
  }

  /** 系统配置（深浅色）变化回调：更新解析值；system 模式下广播刷新 */
  onSystemColorModeChanged(colorMode?: ConfigurationConstant.ColorMode): void {
    if (colorMode === undefined) {
      return;
    }
    const changed = colorMode !== this.systemColorMode;
    this.systemColorMode = colorMode;
    if (changed && this.currentMode === 'system') {
      AppEventBus.emit(ThemeManager.EVENT_THEME_CHANGED, 'system');
    }
  }

  private applyToWindow(mode: ThemeMode): void {
    if (!this.appContext) {
      return;
    }
    try {
      if (mode === 'light') {
        this.appContext.setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT);
      } else if (mode === 'dark') {
        this.appContext.setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
      } else {
        this.appContext.setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
      }
    } catch (e) {
      // 忽略窗口设置失败
    }
  }

  private static normalize(value: string): ThemeMode {
    if (value === 'light' || value === 'dark' || value === 'system') {
      return value;
    }
    return 'system';
  }
}
