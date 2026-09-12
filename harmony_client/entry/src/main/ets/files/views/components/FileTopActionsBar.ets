import { AppTheme } from '../../../core/theme/AppTheme';
import { BorderedIconButton } from '../../../common/components/BorderedIconButton';

/**
 * 文件浏览顶部操作栏（通用组件，对齐 Flutter app_file_top_actions_bar）：
 * - 根页（showBack=false）：[新建] 标题 [任务中心]
 * - 子页（showBack=true）：[返回] [关闭] 标题 [新建] [任务中心]
 */
@ComponentV2
export struct FileTopActionsBar {
  @Param title: string = '';
  @Param showBack: boolean = true;
  @Param showClose: boolean = false;
  @Param onBack: () => void = (): void => {
  };
  @Param onClose: () => void = (): void => {
  };
  @Param onCreate: () => void = (): void => {
  };
  @Param onTask: () => void = (): void => {
  };

  build() {
    Row() {
      if (!this.showBack) {
        BorderedIconButton({
          icon: $r('sys.symbol.plus'),
          onTap: (): void => {
            this.onCreate();
          }
        })
      }
      if (this.showBack) {
        BorderedIconButton({
          icon: $r('sys.symbol.arrow_left'),
          onTap: (): void => {
            this.onBack();
          }
        })
      }
      if (this.showClose) {
        BorderedIconButton({
          icon: $r('sys.symbol.xmark'),
          onTap: (): void => {
            this.onClose();
          }
        })
          .margin({ left: 10 })
      }
      Text(this.title)
        .fontSize(17)
        .fontWeight(FontWeight.Medium)
        .fontColor(AppTheme.current().onSurface)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
        .textAlign(TextAlign.Center)
      if (this.showBack) {
        BorderedIconButton({
          icon: $r('sys.symbol.plus'),
          onTap: (): void => {
            this.onCreate();
          }
        })
          .margin({ left: 10 })
      }
      BorderedIconButton({
        icon: $r('sys.symbol.checkmark_clipboard'),
        onTap: (): void => {
          this.onTask();
        }
      })
        .margin({ left: 10 })
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 8, bottom: 6 })
  }
}
