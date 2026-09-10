import { picker } from '@kit.CoreFileKit';
import { L10n } from '../../../core/localization/L10n';
import { AppTheme, ThemePalette } from '../../../core/theme/AppTheme';
import { DialogUtil } from '../../../common/DialogUtil';
import { ToastUtil } from '../../../common/ToastUtil';
import { SheetHandle, SheetParamsBase, SheetUtil } from '../../../common/SheetUtil';
import { pickTargetFolderViaSheet, pickServerFileViaSheet } from '../../../files/views/FolderPickerSheet';
import { MediaPickerUtil } from '../../../transfer/utils/MediaPickerUtil';
import { TransmissionController } from '../controllers/TransmissionController';

/**
 * 添加任务弹层（对齐 Flutter _AddTorrentDialog）：
 * 磁力/链接 与 种子文件 两种模式，服务器选择 .torrent 或本地上传，保存目录必选且需可写。
 */
export class AddTorrentSheetParams extends SheetParamsBase {
  ctrl: TransmissionController | undefined = undefined;
}

@Builder
function AddTorrentSheetContent(p: AddTorrentSheetParams) {
  AddTorrentSheetInner({ p: p })
}

@ComponentV2
struct AddTorrentSheetInner {
  @Param p: AddTorrentSheetParams = new AddTorrentSheetParams();
  /** 0 磁力/链接 1 种子文件（对齐 Flutter _mode） */
  @Local mode: number = 0;
  @Local magnetText: string = '';
  @Local downloadDir: string = '';
  @Local serverTorrentPath: string = '';
  @Local localTorrentUri: string = '';
  @Local localTorrentName: string = '';
  @Local submitting: boolean = false;

  aboutToAppear(): void {
    void this.initLastDir();
  }

  private async initLastDir(): Promise<void> {
    const ctrl = this.p.ctrl;
    if (ctrl === undefined) {
      return;
    }
    const dir = await ctrl.loadLastDownloadDir();
    if (dir.length > 0) {
      this.downloadDir = dir;
    }
  }

  private palette(): ThemePalette {
    return AppTheme.current();
  }

  // ===== 目录选择（对齐 _pickFolder） =====

  private pickFolder(): void {
    pickTargetFolderViaSheet(this.downloadDir.trim(), (paths: string[]): void => {
      if (paths.length === 0) {
        return;
      }
      const picked = paths[0].trim();
      if (picked.length === 0) {
        return;
      }
      void this.applyPickedFolder(picked);
    });
  }

  private async applyPickedFolder(picked: string): Promise<void> {
    const ctrl = this.p.ctrl;
    if (ctrl === undefined) {
      return;
    }
    const ok = await ctrl.validateAndSaveLastDownloadDir(picked);
    if (!ok) {
      // 目录不可写：提示后重新打开选择器（对齐 Flutter showInfoDialog onPressed: _pickFolder）
      DialogUtil.showInfoDialog(L10n.t('tip', '提示'),
        L10n.t('upload_center_target_cannot_upload', '此目录无法上传，请重新选择'),
        L10n.t('ok', '确定'), (): void => {
          this.pickFolder();
        });
      return;
    }
    this.downloadDir = picked;
  }

  // ===== 种子文件选择（对齐 _pickTorrentFileFromServer / _pickTorrentFileLocal） =====

  private pickTorrentFileFromServer(): void {
    pickServerFileViaSheet(this.serverTorrentPath.trim(), (paths: string[]): void => {
      if (paths.length === 0) {
        return;
      }
      const picked = paths[0].trim();
      if (picked.length === 0) {
        return;
      }
      this.serverTorrentPath = picked;
      this.localTorrentUri = '';
      this.localTorrentName = '';
    });
  }

  private async pickTorrentFileLocal(): Promise<void> {
    try {
      const docPicker = new picker.DocumentViewPicker();
      const opts = new picker.DocumentSelectOptions();
      opts.maxSelectNumber = 1;
      opts.fileSuffixFilters = ['.torrent'];
      const uris: string[] = await docPicker.select(opts);
      if (uris === undefined || uris.length === 0) {
        return;
      }
      this.localTorrentUri = uris[0];
      this.localTorrentName = MediaPickerUtil.uriDisplayName(this.localTorrentUri);
      this.serverTorrentPath = '';
    } catch (_e) {
      // 用户取消选择
    }
  }

  // ===== 提交（对齐 _submit） =====

  private async submit(): Promise<void> {
    if (this.submitting) {
      return;
    }
    const ctrl = this.p.ctrl;
    if (ctrl === undefined) {
      return;
    }
    const dir = this.downloadDir.trim();
    if (dir.length === 0) {
      ToastUtil.show(L10n.t('transmission_task_download_dir_required', '请选择保存目录'));
      return;
    }
    const ok = await ctrl.validateAndSaveLastDownloadDir(dir);
    if (!ok) {
      ToastUtil.show(L10n.t('upload_center_target_cannot_upload', '此目录无法上传，请重新选择'));
      return;
    }
    if (this.mode === 0) {
      const url = this.magnetText.trim();
      if (url.length === 0) {
        return;
      }
      this.submitting = true;
      await ctrl.addTorrent(url, '', '', dir);
    } else {
      const serverPath = this.serverTorrentPath.trim();
      if (this.localTorrentUri.length === 0 && serverPath.length === 0) {
        return;
      }
      this.submitting = true;
      if (serverPath.length > 0) {
        await ctrl.addTorrent('', '', serverPath, dir);
      } else {
        await ctrl.addTorrent('', this.localTorrentUri, '', dir);
      }
    }
    this.submitting = false;
    this.p.close();
  }

  build() {
    Column() {
      SheetHandle()
      Text(L10n.t('transmission_add_torrent', '添加任务'))
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.palette().onSurface)
        .margin({ top: 4, bottom: 12 })

      Column({ space: 12 }) {
        // 模式分段（对齐 SegmentedButton）
        Row({ space: 8 }) {
          this.SegmentButton(L10n.t('transmission_add_by_magnet', '磁力/链接'), 0)
          this.SegmentButton(L10n.t('transmission_add_by_file', '种子文件'), 1)
        }
        .width('100%')

        if (this.mode === 0) {
          TextArea({ text: this.magnetText, placeholder: L10n.t('transmission_magnet_hint', '请输入 Magnet 链接或种子 URL') })
            .fontSize(14)
            .fontColor(this.palette().onSurface)
            .placeholderColor(this.palette().hint)
            .backgroundColor(this.palette().inputFill)
            .borderRadius(8)
            .border({ width: 1, color: this.palette().inputBorder })
            .height(76)
            .width('100%')
            .onChange((v: string) => {
              this.magnetText = v;
            })
        } else {
          this.OutlineButton(L10n.t('transmission_select_server_torrent_file', '从服务器选择'),
            $r('sys.symbol.folder'), (): void => {
              this.pickTorrentFileFromServer();
            })
          this.OutlineButton(L10n.t('transmission_upload_local_torrent_file', '本地上传'),
            $r('sys.symbol.upload'), (): void => {
              void this.pickTorrentFileLocal();
            })
          if (this.serverTorrentPath.length > 0) {
            Text(this.baseName(this.serverTorrentPath))
              .fontSize(12)
              .fontColor(this.palette().subText)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
          } else if (this.localTorrentName.length > 0) {
            Text(this.localTorrentName)
              .fontSize(12)
              .fontColor(this.palette().subText)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
          }
        }

        // 保存目录（对齐 readOnly TextField + suffix folder 按钮）
        Column({ space: 6 }) {
          Text(L10n.t('transmission_task_download_dir', '保存目录'))
            .fontSize(12)
            .fontColor(this.palette().subText)
          Row({ space: 8 }) {
            Text(this.downloadDir.trim().length > 0
              ? this.downloadDir
              : L10n.t('transmission_task_download_dir_required', '请选择保存目录'))
              .fontSize(14)
              .fontColor(this.downloadDir.trim().length > 0
                ? this.palette().onSurface : this.palette().hint)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
            SymbolGlyph($r('sys.symbol.folder'))
              .fontSize(18)
              .fontColor([this.palette().primary])
          }
          .width('100%')
          .height(44)
          .padding({ left: 12, right: 12 })
          .borderRadius(8)
          .backgroundColor(this.palette().inputFill)
          .border({ width: 1, color: this.palette().inputBorder })
          .onClick((): void => {
            this.pickFolder();
          })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)

        // 底部动作
        Row({ space: 12 }) {
          Button(L10n.t('cancel', '取消'))
            .fontSize(14)
            .fontColor(this.palette().primary)
            .backgroundColor(Color.Transparent)
            .height(38)
            .enabled(!this.submitting)
            .opacity(this.submitting ? 0.5 : 1)
            .onClick((): void => {
              this.p.close();
            })
          if (this.submitting) {
            LoadingProgress()
              .width(20)
              .height(20)
              .color(this.palette().primary)
          } else {
            Button(L10n.t('confirm', '确认'))
              .fontSize(14)
              .fontColor(this.palette().buttonText)
              .backgroundColor(this.palette().buttonBg)
              .height(38)
              .onClick((): void => {
                void this.submit();
              })
          }
        }
        .justifyContent(FlexAlign.End)
        .width('100%')
      }
      .width('100%')
    }
    .width('100%')
    .padding({ left: 16, right: 16, bottom: 20 })
    .borderRadius({ topLeft: 20, topRight: 20 })
    .backgroundColor(AppTheme.current().surfaceBg)
    .constraintSize({ maxHeight: '88%' })
  }

  /** 模式分段按钮（对齐 SegmentedButton segment） */
  @Builder
  SegmentButton(label: string, value: number) {
    Text(label)
      .fontSize(13)
      .fontWeight(this.mode === value ? FontWeight.Medium : FontWeight.Normal)
      .fontColor(this.mode === value ? this.palette().primary : this.palette().onSurface)
      .textAlign(TextAlign.Center)
      .maxLines(1)
      .padding({ top: 8, bottom: 8 })
      .layoutWeight(1)
      .borderRadius(8)
      .backgroundColor(this.mode === value
        ? AppTheme.withAlpha(this.palette().primary, 0.12)
        : AppTheme.withAlpha(this.palette().onSurface, 0.05))
      .onClick((): void => {
        this.mode = value;
      })
  }

  /** 描边按钮（对齐 OutlinedButton.icon） */
  @Builder
  OutlineButton(label: string, icon: Resource, onTap: () => void) {
    Row({ space: 8 }) {
      SymbolGlyph(icon)
        .fontSize(16)
        .fontColor([this.palette().onSurface])
      Text(label)
        .fontSize(14)
        .fontColor(this.palette().onSurface)
        .maxLines(1)
    }
    .justifyContent(FlexAlign.Center)
    .width('100%')
    .height(42)
    .borderRadius(8)
    .border({ width: 1, color: this.palette().divider })
    .onClick((): void => {
      onTap();
    })
  }

  /** 路径末段文件名（对齐 p.basename） */
  private baseName(path: string): string {
    const clean = path.trim().replace(/\/+$/, '');
    const idx = clean.lastIndexOf('/');
    return idx >= 0 && idx < clean.length - 1 ? clean.substring(idx + 1) : clean;
  }
}

/** 打开添加任务弹层 */
export function showAddTorrentSheet(ctrl: TransmissionController): void {
  const p = new AddTorrentSheetParams();
  p.ctrl = ctrl;
  SheetUtil.present(p, wrapBuilder(AddTorrentSheetContent));
}
