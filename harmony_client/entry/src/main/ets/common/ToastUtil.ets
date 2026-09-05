import { UIContext } from '@ohos.arkui.UIContext';

/**
 * 全局 Toast 工具（对齐 Flutter ToastUtil）：
 * 在入口页调用 ToastUtil.init(uiContext) 后，任何非组件上下文（如控制器）均可弹出。
 */
export class ToastUtil {
  private static uiContext: UIContext | undefined = undefined;

  static init(uiContext: UIContext): void {
    ToastUtil.uiContext = uiContext;
  }

  static show(message: string): void {
    const ctx = ToastUtil.uiContext;
    if (!ctx) {
      return;
    }
    try {
      ctx.getPromptAction().showToast({ message: message, duration: 2000 });
    } catch (_e) {
      // UI 上下文失效时忽略
    }
  }
}
