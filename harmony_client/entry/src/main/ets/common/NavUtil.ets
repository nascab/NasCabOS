/**
 * 全局导航栈持有者（对齐 Flutter Navigator.push/pop）：
 * 供无参视图（如 PhotoAlbumHomeView）与弹层/回调等非组件上下文推入、弹出路由页。
 * NavPathStack 为 ArkUI 内置类型；在 Index.ets 入口初始化。
 */
export class NavUtil {
  private static stack: NavPathStack | undefined = undefined;

  static init(stack: NavPathStack): void {
    NavUtil.stack = stack;
  }

  /** 推入路由页（param 缺省时传空对象，与 Index.pageMap 的 instanceof 缺省分支配套） */
  static push(name: string, param?: Object): void {
    if (NavUtil.stack) {
      NavUtil.stack.pushPathByName(name, param ?? new Object());
    }
  }

  /** 弹出栈顶路由页 */
  static pop(): void {
    if (NavUtil.stack) {
      NavUtil.stack.pop();
    }
  }

  /** 连续弹出栈顶同名页面直到栈顶不是该名称（对齐 Flutter Navigator.popUntil 反向关闭子页） */
  static popUntilTopNot(name: string): void {
    if (!NavUtil.stack) {
      return;
    }
    const names = NavUtil.stack.getAllPathName();
    while (names.length > 0 && names[names.length - 1] === name) {
      NavUtil.stack.pop();
      names.pop();
    }
  }
}
