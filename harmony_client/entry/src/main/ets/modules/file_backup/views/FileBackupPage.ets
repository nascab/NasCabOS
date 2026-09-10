import { L10n } from '../../../core/localization/L10n';
import { AppTheme, ThemePalette } from '../../../core/theme/AppTheme';
import { AppEventBus } from '../../../common/AppEventBus';
import { LanguageService } from '../../../core/localization/LanguageService';
import { PageScaffold } from '../../../common/PageScaffold';
import { DialogUtil } from '../../../common/DialogUtil';
import { NavUtil } from '../../../common/NavUtil';
import { EmptyState } from '../../../common/components/EmptyState';
import { GlassCard } from '../../../common/components/GlassCard';
import { FileBackupController } from '../controllers/FileBackupController';
import {
  BackupTask, backupLastStatusText, friendlyBackupError, formatBackupLocalTime
} from '../models/FileBackupModels';
import { FileBackupRoutes, FileBackupPageParam, FileBackupEditPageParam } from '../router/FileBackupRoutes';
import {
  BackupKeyValueRow, BackupPanelButton, backupStatusColor, backupStatusText, backupTypeText
} from '../components/FileBackupWidgets';
import { showBackupRecordsDialog } from '../components/FileBackupDialogs';

/**
 * 磁盘间备份主页（对齐 Flutter FileBackupView 移动端形态）：
 * 标题栏（帮助/刷新/新增）+ 任务列表面板（对齐 _ServerBackupListPanel showHeader: false，
 * 刷新/新增动作由标题栏承担）。
 */
@ComponentV2
export struct FileBackupPage {
  @Param param: FileBackupPageParam = new FileBackupPageParam();
  @Param popPage: () => void = (): void => {
  };
  /** 控制器随页面创建销毁（对齐 Flutter GetBuilder 生命周期） */
  @Local ctrl: FileBackupController = new FileBackupController();
  /** 依赖 localeBump：切换语言后触发整页刷新 */
  @Local localeBump: number = 0;
  private localeListener: (data: string) => void = (_data: string): void => {
    this.localeBump++;
  };

  aboutToAppear(): void {
    AppEventBus.on(LanguageService.EVENT_LOCALE_CHANGED, this.localeListener);
    // 对齐 Flutter onInit：静默刷新一次 + 启动 3 秒轮询
    this.ctrl.start();
  }

  aboutToDisappear(): void {
    AppEventBus.off(LanguageService.EVENT_LOCALE_CHANGED, this.localeListener);
    this.ctrl.stop();
  }

  private palette(): ThemePalette {
    return AppTheme.current();
  }

  private showHelp(): void {
    void DialogUtil.showInfoDialog(
      L10n.t('file_backup_menu_disk', '磁盘间备份'),
      L10n.t('file_backup_help_tooltip', '用于在服务器不同目录之间定时备份'));
  }

  private onCreate(): void {
    NavUtil.push(FileBackupRoutes.PAGE_EDIT, new FileBackupEditPageParam());
  }

  build() {
    PageScaffold({
      title: L10n.t('file_backup_menu_disk', '磁盘间备份'),
      showBack: true,
      statusBarBg: AppTheme.current().pageBg,
      onBack: (): void => {
        this.popPage();
      },
      actions: (): void => {
        this.TitleActions()
      },
      content: (): void => {
        this.PageContent()
      }
    })
  }

  @Builder
  TitleActions() {
    SymbolGlyph($r('sys.symbol.questionmark_circle'))
      .fontSize(22)
      .fontColor([AppTheme.current().appBarFg])
      .onClick((): void => {
        this.showHelp();
      })
    SymbolGlyph($r('sys.symbol.arrow_clockwise'))
      .fontSize(22)
      .fontColor([AppTheme.current().appBarFg])
      .onClick((): void => {
        void this.ctrl.refreshList(true);
      })
    SymbolGlyph($r('sys.symbol.plus'))
      .fontSize(22)
      .fontColor([AppTheme.current().appBarFg])
      .onClick((): void => {
        this.onCreate();
      })
  }

  @Builder
  PageContent() {
    Column() {
      if (this.ctrl.isLoading && this.ctrl.tasks.length === 0) {
        Column() {
          LoadingProgress()
            .width(32)
            .height(32)
            .color(this.palette().primary)
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
      } else if (this.ctrl.errorText.trim().length > 0 && this.ctrl.tasks.length === 0) {
        Column() {
          EmptyState({ message: this.ctrl.errorText.trim() })
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
      } else if (this.ctrl.tasks.length === 0) {
        Column() {
          EmptyState({ message: '' })
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
      } else {
        List({ space: 8 }) {
          ForEach(this.ctrl.tasks, (item: BackupTask) => {
            ListItem() {
              TaskCard({ item: item, ctrl: this.ctrl })
            }
          }, (item: BackupTask): string => `${item.id}_${item.status}_${item.type}_${item.progress}`
            + `_${item.lastError.length}_${item.sourcePath.length}_${item.excludeList.length}`
            + `_${this.ctrl.isOpLoading(item.id)}`)
        }
        .width('100%')
        .height('100%')
        .padding({ left: 12, right: 12, top: 12, bottom: 12 })
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(AppTheme.current().pageBg)
    // 依赖 localeBump：切换语言后触发整页刷新
    .opacity(this.localeBump >= 0 ? 1 : 1)
  }
}

/**
 * 任务卡片（对齐 Flutter _ServerBackupListItemCard）：
 * 标题行 #id · 模式 + 状态；信息行（源/目标/频率/排除/上次备份时间与状态/进度/错误）；
 * 操作按钮（启停/编辑/删除/备份记录）横向滚动。
 */
@ComponentV2
struct TaskCard {
  @Require @Param item: BackupTask;
  @Require @Param ctrl: FileBackupController;

  private palette(): ThemePalette {
    return AppTheme.current();
  }

  private get opLoading(): boolean {
    return this.ctrl.isOpLoading(this.item.id);
  }

  private get canStop(): boolean {
    return this.item.status === 'running';
  }

  /** 多源/多排除/错误全文 弹窗（对齐 Flutter _showTextDialog） */
  private showTextDialog(title: string, content: string): void {
    void DialogUtil.showInfoDialog(title, content);
  }

  private sourcesText(): string {
    const sources = this.item.sourcePath;
    if (sources.length === 0) {
      return L10n.t('file_backup_source_empty', '未选择源目录');
    }
    if (sources.length === 1) {
      return sources[0];
    }
    return `${sources[0]} (+${sources.length - 1})`;
  }

  private excludeText(): string {
    const excludes = this.item.excludeList;
    if (excludes.length === 0) {
      return '-';
    }
    if (excludes.length === 1) {
      return excludes[0];
    }
    return `${excludes[0]} (+${excludes.length - 1})`;
  }

  /** 错误短行（对齐 Flutter：首行取友好化文案，空则全文） */
  private errorShortLine(): string {
    const full = this.item.lastError.trim();
    if (full.length === 0) {
      return '';
    }
    const firstLine = friendlyBackupError(full.split('\n')[0].trim());
    return firstLine.length === 0 ? full : firstLine;
  }

  private errorFullText(): string {
    return friendlyBackupError(this.item.lastError.trim());
  }

  build() {
    GlassCard({ padValue: 12, cornerRadius: 14 }) {
      Column() {
        // 行 1：#id · 模式 + 状态
        Row() {
          Text(`#${this.item.id} · ${backupTypeText(this.item.type)}`)
            .fontSize(15)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.palette().onSurface)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
          Text(backupStatusText(this.item.status))
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor(backupStatusColor(this.item.status))
            .margin({ left: 8 })
        }
        .width('100%')

        BackupKeyValueRow({
          label: L10n.t('file_backup_source_paths', '源目录'),
          value: this.sourcesText(),
          viewPath: this.item.sourcePath.length > 0 ? this.item.sourcePath[0] : '',
          onValueTap: this.item.sourcePath.length > 1
            ? (): void => {
              this.showTextDialog(L10n.t('file_backup_source_paths', '源目录'),
                this.item.sourcePath.join('\n'));
            }
            : (): void => {
            }
        })
          .margin({ top: 8 })
        BackupKeyValueRow({
          label: L10n.t('file_backup_target_path', '目标目录'),
          value: this.item.targetPath,
          viewPath: this.item.targetPath.trim()
        })
          .margin({ top: 6 })
        BackupKeyValueRow({
          label: L10n.t('file_backup_frequency_hours', '频率(小时)'),
          value: this.item.frenquence > 0 ? `${this.item.frenquence}` : '-'
        })
          .margin({ top: 6 })
        BackupKeyValueRow({
          label: L10n.t('exclude_list', '排除列表'),
          value: this.excludeText(),
          onValueTap: this.item.excludeList.length > 1
            ? (): void => {
              this.showTextDialog(L10n.t('exclude_list', '排除列表'),
                this.item.excludeList.join('\n'));
            }
            : (): void => {
            }
        })
          .margin({ top: 6 })
        BackupKeyValueRow({
          label: L10n.t('file_backup_last_backup_time', '上次备份时间'),
          value: this.item.lastSuccessTime === undefined || this.item.lastSuccessTime === null
            ? '-'
            : formatBackupLocalTime(this.item.lastSuccessTime, '-')
        })
          .margin({ top: 6 })
        BackupKeyValueRow({
          label: L10n.t('file_backup_last_backup_status', '上次备份状态'),
          value: backupLastStatusText(this.item.lastError, this.item.lastSuccessTime)
        })
          .margin({ top: 6 })
        if (this.item.status === 'running') {
          BackupKeyValueRow({
            label: L10n.t('file_backup_progress', '进度'),
            value: this.item.progress.length === 0 ? '-' : this.item.progress
          })
            .margin({ top: 6 })
        }
        if (this.errorShortLine().length > 0) {
          BackupKeyValueRow({
            label: L10n.t('file_backup_last_error', '错误信息'),
            value: this.errorShortLine(),
            valueColor: this.palette().error,
            onValueTap: (): void => {
              this.showTextDialog(L10n.t('file_backup_last_error', '错误信息'), this.errorFullText());
            }
          })
            .margin({ top: 6 })
        }

        // 操作按钮行（横向滚动，对齐 Flutter SingleChildScrollView）
        Scroll() {
          Row({ space: 8 }) {
            BackupPanelButton({
              label: this.canStop
                ? L10n.t('file_backup_stop', '停止')
                : L10n.t('file_backup_start', '启动'),
              icon: this.canStop ? $r('sys.symbol.stop_circle') : $r('sys.symbol.play_circle'),
              primary: true,
              btnEnabled: !this.opLoading,
              loading: this.opLoading,
              onTap: (): void => {
                if (this.canStop) {
                  void this.ctrl.stopTask(this.item.id);
                } else {
                  void this.ctrl.startTask(this.item.id);
                }
              }
            })
            BackupPanelButton({
              label: L10n.t('edit', '编辑'),
              icon: $r('sys.symbol.square_and_pencil'),
              primary: false,
              btnEnabled: this.item.status !== 'running' && !this.opLoading,
              loading: false,
              onTap: (): void => {
                const p = new FileBackupEditPageParam();
                p.initial = this.item;
                NavUtil.push(FileBackupRoutes.PAGE_EDIT, p);
              }
            })
            BackupPanelButton({
              label: L10n.t('delete', '删除'),
              icon: $r('sys.symbol.trash'),
              primary: false,
              btnEnabled: this.item.id > 0,
              loading: false,
              onTap: (): void => {
                void this.ctrl.remove(this.item.id);
              }
            })
            if (this.item.id > 0) {
              BackupPanelButton({
                label: L10n.t('file_backup_run_records', '备份记录'),
                icon: $r('sys.symbol.clock'),
                primary: false,
                btnEnabled: true,
                loading: false,
                onTap: (): void => {
                  showBackupRecordsDialog(this.ctrl, this.item.id);
                }
              })
            }
          }
          .alignItems(VerticalAlign.Center)
        }
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Off)
        .width('100%')
        .margin({ top: 10 })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
  }
}
