import { L10n } from '../../core/localization/L10n';
import { AppTheme } from '../../core/theme/AppTheme';
import { DialogUtil } from '../../common/DialogUtil';
import { BorderedIconButton } from '../../common/components/BorderedIconButton';
import { EmptyState } from '../../common/components/EmptyState';
import { PickOption, showOptionPickSheet } from '../../common/components/OptionPickSheet';
import { pickTargetFolderViaSheet } from '../../files/views/FolderPickerSheet';
import { TransferTask } from '../models/TransferModels';
import { UploadController } from '../controllers/UploadController';
import { UploadTaskCard } from './UploadTaskCard';

/**
 * 上传中 Tab（对齐 Flutter upload_center_uploading_tab.dart）：
 * 设置卡片（目标目录/同名策略/保存类型）+ 批量操作 + 任务列表 + 底部选择入口。
 */
@ComponentV2
export struct UploadCenterUploadingTab {
  @Param ctrl: UploadController = UploadController.getInstance();
  @Local targetDirDisplay: string = '';

  private palette() {
    return AppTheme.current();
  }

  /** 正在上传的排最前，其余按创建时间倒序（对齐 Flutter 排序） */
  private get uploadingItems(): TransferTask[] {
    return this.ctrl.uploadingTasks();
  }

  aboutToAppear(): void {
    this.targetDirDisplay = this.ctrl.targetDirDisplay;
  }

  private pickTargetDir(): void {
    pickTargetFolderViaSheet(this.ctrl.currentTargetDir, (paths: string[]) => {
      if (paths.length === 0) {
        return;
      }
      void this.ctrl.applyTargetDir(paths[0]).then((): void => {
        this.targetDirDisplay = this.ctrl.targetDirDisplay;
      });
    });
  }

  private showNameStrategySheet(): void {
    showOptionPickSheet(L10n.t('folder_name_strategy', '同名文件策略'), [
      new PickOption('skip', L10n.t('skip', '跳过')),
      new PickOption('overwrite', L10n.t('overwrite', '覆盖')),
      new PickOption('rename', L10n.t('rename', '重命名'))
    ], this.ctrl.nameStrategy, (key: string): void => {
      this.ctrl.nameStrategy = key;
    });
  }

  private showSaveTypeSheet(): void {
    showOptionPickSheet(L10n.t('upload_center_save_type', '保存类型'), [
      new PickOption('', L10n.t('upload_center_save_type_root', '保存到根目录(默认)')),
      new PickOption('day', L10n.t('upload_center_save_type_day', '按年/月/日保存')),
      new PickOption('month', L10n.t('upload_center_save_type_month', '按年/月保存')),
      new PickOption('year', L10n.t('upload_center_save_type_year', '按年保存'))
    ], this.ctrl.saveType, (key: string): void => {
      void this.ctrl.setSaveType(key);
    });
  }

  private showSaveTypeTip(): void {
    DialogUtil.showInfoDialog(L10n.tip,
      L10n.t('upload_center_save_type_tip', '按日期保存时，上传的文件会自动归档到对应年/月/日目录'));
  }

  build() {
    Column() {
      this.SettingsCard()
      this.BatchActionsRow()
      this.TaskList()
      this.BottomPickBar()
    }
    .width('100%')
    .height('100%')
    .padding({ left: 12, right: 12 })
  }

  @Builder
  SettingsCard() {
    Column() {
      // 目标文件夹
      Row({ space: 10 }) {
        SymbolGlyph($r('sys.symbol.folder'))
          .fontSize(20)
          .fontColor([this.palette().primary])
        Column({ space: 2 }) {
          Text(L10n.t('encrypted_space_export_target_path', '目标文件夹'))
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.palette().onSurface)
          Text(this.targetDirDisplay.length > 0 ? this.targetDirDisplay :
            L10n.t('quick_share_path_hint', '未选择路径'))
            .fontSize(12)
            .fontColor(this.palette().subText)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(16)
          .fontColor([this.palette().subText])
      }
      .width('100%')
      .padding({ top: 10, bottom: 10 })
      .onClick(() => {
        this.pickTargetDir();
      })

      Divider().color(this.palette().divider)

      // 同名文件策略
      Row({ space: 10 }) {
        SymbolGlyph($r('sys.symbol.list_checkmark'))
          .fontSize(20)
          .fontColor([this.palette().primary])
        Column({ space: 2 }) {
          Text(L10n.t('folder_name_strategy', '同名文件策略'))
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.palette().onSurface)
          Text(L10n.t(this.ctrl.nameStrategy, this.ctrl.nameStrategy))
            .fontSize(12)
            .fontColor(this.palette().subText)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(16)
          .fontColor([this.palette().subText])
      }
      .width('100%')
      .padding({ top: 10, bottom: 10 })
      .onClick(() => {
        this.showNameStrategySheet();
      })

      Divider().color(this.palette().divider)

      // 保存类型
      Row({ space: 10 }) {
        SymbolGlyph($r('sys.symbol.calendar'))
          .fontSize(20)
          .fontColor([this.palette().primary])
        Row() {
          Text(this.saveTypeLabel())
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.palette().onSurface)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)
        .padding({ left: 10, right: 10, top: 6, bottom: 6 })
        .borderRadius(10)
        .backgroundColor(this.palette().inputFill)
        .onClick(() => {
          this.showSaveTypeSheet();
        })
        BorderedIconButton({
          icon: $r('sys.symbol.questionmark_circle'),
          iconColor: this.palette().subText,
          btnSize: 28,
          iconSize: 16,
          onTap: (): void => {
            this.showSaveTypeTip();
          }
        })
      }
      .width('100%')
      .padding({ top: 10, bottom: 10 })
    }
    .width('100%')
    .padding({ left: 10, right: 10 })
    .borderRadius(16)
    .backgroundColor(this.palette().cardBg)
    .border({ width: 1, color: this.palette().divider })
    .margin({ top: 12 })
  }

  private saveTypeLabel(): string {
    switch (this.ctrl.saveType) {
      case 'day':
        return L10n.t('upload_center_save_type_day', '按年/月/日保存');
      case 'month':
        return L10n.t('upload_center_save_type_month', '按年/月保存');
      case 'year':
        return L10n.t('upload_center_save_type_year', '按年保存');
      default:
        return L10n.t('upload_center_save_type_root', '保存到根目录(默认)');
    }
  }

  @Builder
  BatchActionsRow() {
    if (this.uploadingItems.length > 0) {
      Row() {
        TextButton({
          label: L10n.t('task_pause_all', '全部暂停'),
          labelColor: this.palette().onSurface,
          isEnabled: true,
          onTap: (): void => {
            this.ctrl.pauseAll();
          }
        })
        TextButton({
          label: L10n.t('task_clear_all', '清除全部'),
          labelColor: this.palette().error,
          isEnabled: true,
          onTap: (): void => {
            const toDelete = this.uploadingItems;
            for (const t of toDelete) {
              this.ctrl.deleteTask(t);
            }
          }
        })
        Blank()
        TextButton({
          label: L10n.t('task_start_all', '全部开始'),
          labelColor: this.palette().primary,
          isEnabled: this.targetDirDisplay.length > 0,
          onTap: (): void => {
            this.ctrl.startAll();
          }
        })
      }
      .width('100%')
      .padding({ top: 6, bottom: 8 })
    }
  }

  @Builder
  TaskList() {
    if (this.uploadingItems.length === 0) {
      Column() {
        EmptyState({ message: L10n.t('upload_center_empty', '没有待上传文件，点击下方按钮添加') })
      }
      .width('100%')
      .layoutWeight(1)
      .justifyContent(FlexAlign.Center)
    } else {
      List({ space: 0 }) {
        ForEach(this.uploadingItems, (task: TransferTask): void => {
          ListItem() {
            UploadTaskCard({ task: task, ctrl: this.ctrl })
          }
          .margin({ bottom: 10 })
        }, (task: TransferTask): string => `${task.id}_${task.createdTime}`)
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .padding({ bottom: 8 })
    }
  }

  @Builder
  BottomPickBar() {
    Row() {
      Column() {
        SymbolGlyph($r('sys.symbol.picture'))
          .fontSize(20)
          .fontColor([this.palette().primary])
        Text(L10n.t('upload_center_pick_media', '上传照片视频'))
          .fontSize(13)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.palette().onSurface)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ left: 8 })
      }
      .justifyContent(FlexAlign.Center)
      .layoutWeight(1)
      .height('100%')
      .padding({ left: 12, right: 12 })
      .onClick(() => {
        void this.ctrl.pickMediaAndEnqueue();
      })

      Divider()
        .vertical(true)
        .strokeWidth(1)
        .color(this.palette().divider)

      Column() {
        SymbolGlyph($r('sys.symbol.upload'))
          .fontSize(20)
          .fontColor([this.palette().primary])
        Text(L10n.t('folder_upload_file', '上传文件'))
          .fontSize(13)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.palette().onSurface)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ left: 8 })
      }
      .justifyContent(FlexAlign.Center)
      .layoutWeight(1)
      .height('100%')
      .padding({ left: 12, right: 12 })
      .onClick(() => {
        void this.ctrl.pickFilesAndEnqueue();
      })
    }
    .width('100%')
    .height(56)
    .borderRadius(16)
    .border({ width: 1, color: this.palette().divider })
    .clip(true)
    .margin({ bottom: 10 })
  }
}

/** 文字按钮（对齐 Flutter TextButton：禁用置灰） */
@ComponentV2
struct TextButton {
  @Param label: string = '';
  @Param labelColor: string = '';
  @Param isEnabled: boolean = true;
  @Param onTap: () => void = (): void => {
  };

  build() {
    Text(this.label)
      .fontSize(14)
      .fontColor(this.isEnabled ? this.labelColor : AppTheme.current().hint)
      .opacity(this.isEnabled ? 1 : 0.5)
      .padding({ left: 8, right: 8, top: 6, bottom: 6 })
      .onClick(() => {
        if (this.isEnabled) {
          this.onTap();
        }
      })
  }
}
