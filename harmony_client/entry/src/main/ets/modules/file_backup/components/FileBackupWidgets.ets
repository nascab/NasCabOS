import { AppTheme, ThemePalette } from '../../../core/theme/AppTheme';
import { L10n } from '../../../core/localization/L10n';
import { NavUtil } from '../../../common/NavUtil';
import { AppRouter } from '../../../router/AppRouter';
import { FileBrowserParam } from '../../../files/views/FileBrowserPage';

/**
 * 磁盘间备份模块公共小组件（对齐 Flutter backup_common_widgets.dart 的 _KeyValueRow
 * 与列表卡片操作按钮 CustomButton）。
 */

/** 状态文案（对齐 Flutter _statusText） */
export function backupStatusText(status: string): string {
  if (status === 'running') {
    return L10n.t('file_backup_status_running', '运行中');
  }
  if (status === 'stopped') {
    return L10n.t('file_backup_status_stopped', '已停止');
  }
  if (status === 'disabled') {
    return L10n.t('file_backup_status_disabled', '已禁用');
  }
  if (status === 'error') {
    return L10n.t('file_backup_status_error', '异常');
  }
  return status;
}

/** 模式文案（对齐 Flutter _typeText） */
export function backupTypeText(type: string): string {
  if (type === 'sync') {
    return L10n.t('file_backup_type_sync', '同步');
  }
  return L10n.t('file_backup_type_copy', '复制');
}

/** 状态颜色（对齐 Flutter _statusColor：running 主色 / error 错误色 / 其余弱化） */
export function backupStatusColor(status: string): string {
  if (status === 'running') {
    return AppTheme.current().primary;
  }
  if (status === 'error') {
    return AppTheme.current().error;
  }
  return AppTheme.withAlpha(AppTheme.current().onSurface, 0.65);
}

/** 打开服务器文件浏览器定位到目录（对齐 Flutter _openFolderInFileBrowser → AppRoutes.toFiles） */
export function openFolderInFileBrowser(targetPath: string): void {
  const target = targetPath.trim();
  if (target.length === 0) {
    return;
  }
  const p = new FileBrowserParam();
  p.initialPath = target;
  p.isRootPage = false;
  NavUtil.push(AppRouter.FILES, p);
}

/**
 * 键值信息行（对齐 Flutter _KeyValueRow：120 标签列 + 可选 [查看] + 值，
 * 值可点（多源/错误全文弹窗），[查看] 直接跳转文件浏览器）。
 */
@ComponentV2
export struct BackupKeyValueRow {
  @Param label: string = '';
  @Param value: string = '';
  /** 非空时在值前展示 [查看]，点击打开文件浏览器 */
  @Param viewPath: string = '';
  @Param valueColor: string = '';
  @Param valueMaxLines: number = 1;
  /** 值点击（对齐 Flutter onTap：多源/错误全文弹窗） */
  @Param onValueTap: () => void = (): void => {
  };

  private palette(): ThemePalette {
    return AppTheme.current();
  }

  private text(): string {
    return this.value.length > 0 ? this.value : '-';
  }

  private canView(): boolean {
    return this.viewPath.trim().length > 0 && this.value.trim().length > 0;
  }

  build() {
    Row() {
      Text(this.label)
        .fontSize(12)
        .fontColor(this.palette().subText)
        .width(120)
      if (this.canView()) {
        Text(`[${L10n.t('perm_view', '查看')}]`)
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.palette().primary)
          .margin({ right: 8 })
          .onClick((): void => {
            openFolderInFileBrowser(this.viewPath);
          })
      }
      Text(this.text())
        .fontSize(12)
        .fontColor(this.valueColor.length > 0 ? this.valueColor : this.palette().onSurface)
        .maxLines(this.valueMaxLines)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
        .onClick((): void => {
          this.onValueTap();
        })
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
  }
}

/**
 * 面板操作按钮（对齐 Flutter CustomButton：图标 + 文字胶囊，primary 填充/次要描边，
 * 加载态图标替换为小加载圈，对齐 opLoading 时嵌入的 CircularProgressIndicator）。
 */
@ComponentV2
export struct BackupPanelButton {
  @Param label: string = '';
  @Param icon: Resource = $r('sys.symbol.plus');
  @Param primary: boolean = false;
  @Param btnEnabled: boolean = true;
  @Param loading: boolean = false;
  @Param onTap: () => void = (): void => {
  };

  private palette(): ThemePalette {
    return AppTheme.current();
  }

  build() {
    Row({ space: 5 }) {
      if (this.loading) {
        LoadingProgress()
          .width(15)
          .height(15)
          .color(this.primary ? this.palette().buttonText : this.palette().onSurface)
      } else {
        SymbolGlyph(this.icon)
          .fontSize(15)
          .fontColor([this.primary ? this.palette().buttonText : this.palette().onSurface])
      }
      Text(this.label)
        .fontSize(13)
        .fontColor(this.primary ? this.palette().buttonText : this.palette().onSurface)
        .maxLines(1)
    }
    .padding({ left: 12, right: 12, top: 7, bottom: 7 })
    .borderRadius(18)
    .backgroundColor(this.primary ? this.palette().buttonBg : AppTheme.withAlpha(this.palette().onSurface, 0.06))
    .border({
      width: 1,
      color: this.primary ? this.palette().buttonBg : this.palette().divider
    })
    .opacity(this.btnEnabled ? 1 : 0.45)
    .onClick((): void => {
      if (this.btnEnabled) {
        this.onTap();
      }
    })
  }
}
