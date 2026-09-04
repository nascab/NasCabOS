import { ServerInfo } from '../../models/ServerInfo';
import { AuthService } from '../../AuthService';
import { ServerStorageService } from '../../../core/storage/ServerStorageService';
import { L10n } from '../../../core/localization/L10n';
import { ConfirmDialogState } from '../common/AuthUi';
import { ServerListViewModel } from '../server_list/ServerListViewModel';

@ObservedV2
export class AdminCreateViewModel {
  @Trace username: string = '';
  @Trace password: string = '';
  @Trace securityQuestion: string = '';
  @Trace securityAnswer: string = '';
  @Trace selectedQuestion: string = '';
  @Trace isCustomQuestion: boolean = false;
  @Trace isLoading: boolean = false;

  readonly confirmDialog: ConfirmDialogState = new ConfirmDialogState();

  // 预定义的密保问题列表
  readonly predefinedQuestions: string[] = [
    'admin_create_security_question_option1',
    'admin_create_security_question_option2',
    'admin_create_security_question_option3'
  ];

  readonly customQuestionValue: string = 'custom';
  serverInfo: ServerInfo;
  private authService: AuthService = AuthService.getInstance();
  private listVm: ServerListViewModel;

  constructor(serverInfo: ServerInfo, listVm: ServerListViewModel) {
    this.serverInfo = serverInfo;
    this.listVm = listVm;
  }

  static createDefault(listVm: ServerListViewModel): AdminCreateViewModel {
    return new AdminCreateViewModel(listVm.selectedServer ?? new ServerInfo(), listVm);
  }

  /// 获取本地化的密保问题
  getLocalizedQuestion(questionKey: string): string {
    if (questionKey === 'admin_create_security_question_option1') {
      return L10n.adminCreateSecurityQuestionOption1;
    }
    if (questionKey === 'admin_create_security_question_option2') {
      return L10n.adminCreateSecurityQuestionOption2;
    }
    if (questionKey === 'admin_create_security_question_option3') {
      return L10n.adminCreateSecurityQuestionOption3;
    }
    return questionKey;
  }

  /// 切换密保问题类型
  toggleQuestionType(value: string): void {
    this.selectedQuestion = value;
    this.isCustomQuestion = value === this.customQuestionValue;
    if (!this.isCustomQuestion) {
      this.securityQuestion = '';
    }
  }

  goBack(): void {
    this.listVm.showCreateAdminView = false;
  }

  /// 处理表单提交
  async handleSubmit(): Promise<void> {
    if (this.isLoading) {
      return;
    }
    if (this.username.trim().length === 0) {
      this.showError(L10n.serverAddUsernameRequired);
      return;
    }
    if (this.password.length === 0) {
      this.showError(L10n.serverAddPasswordRequired);
      return;
    }
    if (this.password.length < 6) {
      this.showError(L10n.authPasswordTooShort);
      return;
    }
    if (this.selectedQuestion.length === 0) {
      this.showError(L10n.adminCreateSecurityQuestionRequired);
      return;
    }
    if (this.isCustomQuestion && this.securityQuestion.trim().length === 0) {
      this.showError(L10n.adminCreateSecurityQuestionRequired);
      return;
    }
    if (this.securityAnswer.trim().length === 0) {
      this.showError(L10n.adminCreateSecurityAnswerRequired);
      return;
    }

    this.isLoading = true;
    try {
      // 获取密保问题
      const question = this.isCustomQuestion
        ? this.securityQuestion.trim()
        : this.getLocalizedQuestion(this.selectedQuestion);

      // 调用创建管理员API
      const createResult = await this.authService.createSuperAdmin(
        this.username.trim(),
        this.password,
        question,
        this.securityAnswer.trim()
      );

      if (!createResult.success) {
        this.showError(createResult.message ?? L10n.adminCreateFailure);
        return;
      }

      // 更新服务器信息中的令牌信息
      const updatedServerInfo = new ServerInfo();
      updatedServerInfo.serverId = this.serverInfo.serverId;
      updatedServerInfo.serverUrl = this.serverInfo.serverUrl;
      updatedServerInfo.serverName = this.serverInfo.serverName;
      updatedServerInfo.serverHost = this.serverInfo.serverHost;
      updatedServerInfo.serverPortHttp = this.serverInfo.serverPortHttp;
      updatedServerInfo.serverPortHttps = this.serverInfo.serverPortHttps;
      updatedServerInfo.serverHostName = this.serverInfo.serverHostName;
      updatedServerInfo.serverPlatform = this.serverInfo.serverPlatform;
      updatedServerInfo.username = this.username.trim();
      updatedServerInfo.password = this.password;
      updatedServerInfo.accessToken = createResult.accessToken;
      updatedServerInfo.refreshToken = createResult.refreshToken;
      updatedServerInfo.lastLoginTime = Date.now();

      // 保存服务器信息到本地
      const saveResult = await ServerStorageService.getInstance().addServer(updatedServerInfo);
      if (!saveResult) {
        this.showError(L10n.serverAddSaveFailure);
        return;
      }

      // 显示成功提示
      this.showSuccessDialog();
    } catch (e) {
      this.showError(L10n.adminCreateFailure);
    } finally {
      this.isLoading = false;
    }
  }

  private showSuccessDialog(): void {
    this.confirmDialog.showInfo(L10n.adminCreateSuccess, L10n.adminCreateSuccessMessage, () => {
      void this.listVm.refreshSavedServers();
      this.goBack();
    });
  }

  private showError(message: string): void {
    this.confirmDialog.showError(message, L10n.adminCreateFailure);
  }
}
