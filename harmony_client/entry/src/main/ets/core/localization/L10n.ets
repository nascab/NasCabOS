export class L10n {
  static currentLanguageCode: string = 'zh-CN';

  static readonly appName: string = 'NasCabOS';
  static readonly networkFailure: string = '网络请求失败，请检查服务器连接';
  static readonly serviceSessionExpired: string = '登录已过期，请重新登录';
  static readonly authLoginFailure: string = '登录失败';
  static readonly tip: string = '提示';
  static readonly ok: string = '确定';
  static readonly cancel: string = '取消';
  static readonly serverListTitle: string = '登录NasCabOS服务器';
  static readonly addServer: string = '添加服务器';
  static readonly discoveredServers: string = '发现的服务器';
  static readonly savedServers: string = '已保存的服务器';
  static readonly password: string = '密码';
  static readonly username: string = '用户名';
  static readonly login: string = '登录';
  static readonly pairCode: string = '配对码';
  static readonly serverUrl: string = '服务器地址';
  static readonly twofaCode: string = '验证码';
  static readonly twofaTitle: string = '两步验证';
  static readonly connecting: string = '连接中...';
  static readonly featureComingSoon: string = '功能开发中';
  static readonly homeQuickUpload: string = '快速上传';
  static readonly homeDownloadCenter: string = '下载中心';
  static readonly homePhotoBackup: string = '相册备份';
  static readonly searchApps: string = '搜索应用';
  static readonly requirePasswordEveryLogin: string = '每次登录输入密码';

  // ===== auth 模块（与 Flutter 端翻译 key 对应） =====
  static readonly edit: string = '编辑';
  static readonly delete: string = '删除';
  static readonly error: string = '错误';
  static readonly language: string = '语言';
  static readonly operationFailed: string = '操作失败';
  static readonly authTokenRefreshFailure: string = '令牌刷新失败';

  static readonly serverSaved: string = '已保存服务器';
  static readonly serverScanned: string = '自动发现服务器';
  static readonly serverLocalServer: string = '本机';
  static readonly serverAddByPairCodeTitle: string = '使用配对码添加服务器';
  static readonly serverAddByPairCodeContent: string = '请输入配对码';
  static readonly serverPairCodeScanQr: string = '扫描二维码';
  static readonly serverPairCodeScanInvalid: string = '匹配码无效';
  static readonly serverPairCodeHowTitle: string = '如何获取配对码?';
  static readonly serverPairCodeHowContent: string =
    '登录后，服务->远程访问 中开启，即可获得配对码，使用配对码可以随时随地找到您的主机';
  static readonly serverPairCodeHowLink: string = '如何获取配对码?';
  static readonly serverPairCodeEmpty: string = '配对码不能为空';
  static readonly serverPairCodeInvalid: string = '验证码不正确或服务端不在线';
  static readonly serverPairCodeLabel: string = '配对码';
  static readonly serverConnecting: string = '正在连接...';
  static readonly serverLoginPasswordRequired: string = '需要输入密码';
  static readonly serverLoginPasswordRequiredMessage: string =
    '该服务器已设置为每次登录都需要输入密码，请先输入密码再登录';
  static readonly serverEditPairCodeTitle: string = '修改配对码';
  static readonly serverEditPairCodeContent: string = '请输入新的配对码';
  static readonly serverListExitTitle: string = '退出确认';
  static readonly serverListExitContent: string = '确定要退出应用吗？';
  static readonly serverConnectFail: string = '无法连接到服务器，请检查网络连接或服务器地址';
  static readonly serverInit: string = '服务器初始化';
  static readonly serverInitContent: string =
    '此服务器尚未初始化，点击【确定】创建管理员，管理员账号保存在您的服务器磁盘上，非网络账号。';
  static readonly serverAddNameLabel: string = '服务器名称';
  static readonly serverAdd: string = '添加服务器';
  static readonly serverAddNameRequired: string = '请输入服务器名称';
  static readonly serverAddProtocol: string = '协议:';
  static readonly serverAddAddressLabel: string = '服务器地址 (含端口)';
  static readonly serverAddAddressHint: string = '例如: 192.168.1.100:9000';
  static readonly serverAddAddressRequired: string = '请输入服务器地址';
  static readonly serverAddAddressInvalid: string = '请输入有效的服务器地址';
  static readonly serverAddUsernameRequired: string = '请输入用户名';
  static readonly serverAddPasswordRequired: string = '请输入密码';
  static readonly serverNeedInputPasswordEveryTime: string = '每次登录都需要输入密码';
  static readonly serverAddButton: string = '添加服务器';
  static readonly serverAddInvalidServer: string = '该服务器不是有效的NasCab服务器，请检查服务器地址是否正确';
  static readonly serverAddFailure: string = '登录失败';
  static readonly serverAddSuccess: string = '登录成功';
  static readonly serverAddSuccessMessage: string = '服务器已成功添加';
  static readonly serverAddExitTitle: string = '退出确认';
  static readonly serverAddExitContent: string = '确定要退出添加服务器吗？';
  static readonly serverAddSaveFailure: string = '保存服务器信息失败，请重试';

  static readonly authLoginLoading: string = '正在登录';
  static readonly authLoginButton: string = '登录';
  static readonly authPasswordError: string = '密码错误';
  static readonly authPasswordErrorMessage: string = '密码错误，请重新输入密码';
  static readonly authPasswordHint: string = '请输入密码';
  static readonly authPasswordTooShort: string = '密码长度不能小于6位';
  static readonly authWelcomeTitle: string = '欢迎使用NasCab OS';
  static readonly authPairCodeLabel: string = '配对码';
  static readonly authPairCodeConnect: string = '连接';
  static readonly authForgotPassword: string = '找回密码';
  static readonly authPrivacyPolicy: string = '隐私政策';
  static readonly authUserAgreement: string = '用户协议';
  static readonly authHelp: string = '帮助';
  static readonly auth2faTitle: string = '双重验证';
  static readonly auth2faCodeLabel: string = '输入验证器中显示的验证码';
  static readonly auth2faCodeHint: string = '请输入6位验证码';
  static readonly auth2faCannotVerify: string = '无法验证?';
  static readonly auth2faCannotVerifyHint: string =
    '当您的2FA无法验证，管理员账号可以通过服务端界面进行重置，普通用户联系管理员进行重置';
  static readonly auth2faVerifyButton: string = '验证并登录';
  static readonly auth2faCodeRequired: string = '请输入2FA验证码';
  static readonly authRecoverInfoFailure: string = '获取找回密码信息失败';
  static readonly authRecoverTip: string =
    '管理员无法通过密保问题找回时，可以在服务端界面修改，普通用户无法找回时，可以联系管理员修改。';
  static readonly authRecoverSecurityQuestionLabel: string = '密保问题';

  static readonly adminCreateTitle: string = '创建管理员';
  static readonly adminCreateButton: string = '创建管理员';
  static readonly adminCreateFailure: string = '创建失败';
  static readonly adminCreateSuccess: string = '管理员账户已成功创建';
  static readonly adminCreateSuccessMessage: string =
    '创建成功，此账号保存在您的NasCab服务器磁盘上，非联网账号，请您牢记。';
  static readonly adminCreateSecurityQuestionLabel: string = '选择密保问题';
  static readonly adminCreateSecurityQuestionOption1: string = '我的手机号码是什么?';
  static readonly adminCreateSecurityQuestionOption2: string = '我的真实姓名是什么?';
  static readonly adminCreateSecurityQuestionOption3: string = '我的身份证号码是什么?';
  static readonly adminCreateSecurityQuestionCustom: string = '自定义问题';
  static readonly adminCreateSecurityQuestionRequired: string = '请选择或输入密保问题';
  static readonly adminCreateSecurityAnswerLabel: string = '密保答案';
  static readonly adminCreateSecurityAnswerRequired: string = '请输入密保答案';

  static readonly recoverTitle: string = '找回密码';
  static readonly recoverButton: string = '找回密码';
  static readonly recoverFailure: string = '找回失败';
  static readonly recoverSuccess: string = '找回成功';
  static readonly recoverSuccessMessage: string = '管理员密码已更新，请使用新密码登录';
  static readonly recoverAnswerLabel: string = '密保答案';
  static readonly recoverAnswerRequired: string = '请输入密保答案';
  static readonly recoverNewPasswordLabel: string = '新密码';

  static readonly privacyConsentTitle: string = '隐私政策提示';
  static readonly privacyConsentMessage1: string = '为保障您的权益，请在使用前阅读《用户协议》和《隐私政策》。';
  static readonly privacyConsentMessage2: string = '我们将依法收集、使用必要信息以提供服务。';
  static readonly privacyConsentMessage3: string = '点击“同意”即表示您已阅读并同意相关条款；不同意请退出应用。';
  static readonly privacyConsentAgree: string = '同意';
  static readonly privacyConsentDisagree: string = '不同意';

  static serverPairCodeDisplay(code: string): string {
    return `配对码：${code}`;
  }

  static authConnectedHost(host: string): string {
    return `已连接主机：${host}`;
  }

  static serverDeleteConfirmMessage(serverName: string): string {
    return `确定要删除服务器 ${serverName} 吗？`;
  }

  static serverStatusCheckFailedWithError(error: string): string {
    return `服务器状态检查失败: ${error}`;
  }
}
