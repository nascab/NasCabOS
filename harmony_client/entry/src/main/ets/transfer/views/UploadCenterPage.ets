import { window } from '@kit.ArkUI';
import { L10n } from '../../core/localization/L10n';
import { AppTheme } from '../../core/theme/AppTheme';
import { PageScaffold } from '../../common/PageScaffold';
import { BorderedIconButton } from '../../common/components/BorderedIconButton';
import { UploadController } from '../controllers/UploadController';
import { UploadCenterUploadingTab } from './UploadCenterUploadingTab';
import { UploadCenterCompletedTab } from './UploadCenterCompletedTab';

/** 页面参数：从文件浏览器等入口带入的上传目标目录 */
export class UploadCenterParam {
  initialTargetDir: string = '';

  constructor(initialTargetDir: string = '') {
    this.initialTargetDir = initialTargetDir;
  }
}

/**
 * 快速上传中心（对齐 Flutter app_upload_center_view.dart）：
 * 标题栏（已完成页显示清理按钮）+ 上传中/已完成两个 Tab + 屏幕常亮。
 */
@ComponentV2
export struct UploadCenterPage {
  @Param param: UploadCenterParam = new UploadCenterParam();
  @Param pushPage: (name: string, param?: object) => void = (_n: string, _p?: object): void => {
  };
  @Param popPage: () => void = (): void => {
  };
  @Local currentTab: number = 0;
  private ctrl: UploadController = UploadController.getInstance();

  aboutToAppear(): void {
    void this.ctrl.bootstrapTargetDir(this.param.initialTargetDir);
    this.keepScreenOn(true);
  }

  aboutToDisappear(): void {
    this.keepScreenOn(false);
  }

  /** 对齐 Flutter WakelockPlus：传输期间保持屏幕常亮 */
  private keepScreenOn(enable: boolean): void {
    try {
      window.getLastWindow(getContext(this)).then((w: window.Window) => {
        w.setWindowKeepScreenOn(enable);
      });
    } catch (_e) {
      // 忽略窗口获取失败
    }
  }

  private palette() {
    return AppTheme.current();
  }

  build() {
    PageScaffold({
      title: L10n.homeQuickUpload,
      onBack: (): void => {
        this.popPage();
      },
      actions: (): void => {
        this.HeaderActions()
      },
      content: (): void => {
        this.PageContent()
      }
    })
  }

  @Builder
  HeaderActions() {
    if (this.currentTab === 1 && this.ctrl.hasCompleted()) {
      BorderedIconButton({
        icon: $r('sys.symbol.trash'),
        iconColor: this.palette().onSurface,
        onTap: (): void => {
          this.ctrl.clearCompleted();
        }
      })
    }
  }

  @Builder
  TabLabel(label: string, index: number) {
    Column({ space: 4 }) {
      Text(label)
        .fontSize(15)
        .fontWeight(this.currentTab === index ? FontWeight.Bold : FontWeight.Normal)
        .fontColor(this.currentTab === index ? this.palette().primary : this.palette().subText)
      Divider()
        .strokeWidth(2)
        .color(this.currentTab === index ? this.palette().primary : '#00000000')
        .width(36)
    }
    .constraintSize({ minWidth: 72 })
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .height('100%')
  }

  @Builder
  PageContent() {
    Column() {
      Tabs({ index: this.currentTab, barPosition: BarPosition.Start }) {
        TabContent() {
          UploadCenterUploadingTab({ ctrl: this.ctrl })
        }
        .tabBar(this.TabLabel(L10n.t('task_uploading', '上传中'), 0))

        TabContent() {
          UploadCenterCompletedTab({ ctrl: this.ctrl })
        }
        .tabBar(this.TabLabel(L10n.t('task_completed', '已完成'), 1))
      }
      .barMode(BarMode.Fixed)
      .onChange((index: number) => {
        this.currentTab = index;
      })
      .width('100%')
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
  }
}
