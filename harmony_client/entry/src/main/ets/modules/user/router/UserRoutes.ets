/**
 * 用户管理模块路由（对齐 Flutter 移动端形态 app_user_management_scaffold.dart：
 * 用户列表页 → 点击进入用户详情页；用户表单/2FA 绑定为弹窗，不占路由）。
 * 控制器为模块内单例（对齐 Flutter GetView 共享 controller），页面间共享数据。
 */
export class UserRoutes {
  /** 用户管理主页（用户列表） */
  static readonly PAGE_MAIN: string = 'UserManagementPage';
  /** 用户详情页（信息卡 + 2FA/登录记录/操作日志/权限 Tabs） */
  static readonly PAGE_DETAIL: string = 'UserDetailPage';
}

/** 用户管理主页路由参数 */
export class UserManagementPageParam {
  title: string = '';
}

/** 用户详情页路由参数 */
export class UserDetailPageParam {
  /** 目标用户 id（进入前主页已调用 ctrl.selectUser(uid)） */
  uid: number = 0;

  constructor(uid: number = 0) {
    this.uid = uid;
  }
}
