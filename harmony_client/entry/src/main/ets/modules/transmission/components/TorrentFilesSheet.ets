import { L10n } from '../../../core/localization/L10n';
import { AppTheme, ThemePalette } from '../../../core/theme/AppTheme';
import { ToastUtil } from '../../../common/ToastUtil';
import { SheetHandle, SheetParamsBase, SheetUtil } from '../../../common/SheetUtil';
import { CircleCheckbox } from '../../../common/components/CircleCheckbox';
import { TransmissionController } from '../controllers/TransmissionController';
import { TorrentFileEntry } from '../models/TransmissionModels';

/**
 * 任务文件选择弹层（对齐 Flutter _TorrentFilesDialog）：
 * 加载任务文件列表，勾选 wanted 文件（全选/全不选），保存 files_wanted/files_unwanted。
 */
export class TorrentFilesSheetParams extends SheetParamsBase {
  ctrl: TransmissionController | undefined = undefined;
  torrentId: number = 0;
  torrentName: string = '';
}

@Builder
function TorrentFilesSheetContent(p: TorrentFilesSheetParams) {
  TorrentFilesSheetInner({ p: p })
}

@ComponentV2
struct TorrentFilesSheetInner {
  @Param p: TorrentFilesSheetParams = new TorrentFilesSheetParams();
  @Local loading: boolean = true;
  @Local saving: boolean = false;
  @Local errorText: string = '';
  @Local files: TorrentFileEntry[] = [];
  /** 勾选状态（index → wanted），整体替换触发刷新（对齐 _wantedByIndex） */
  @Local wantedByIndex: Map<number, boolean> = new Map<number, boolean>();
  /** 打开时的初始勾选快照，用于脏检查（对齐 _initialWantedByIndex） */
  private initialWantedByIndex: Map<number, boolean> = new Map<number, boolean>();

  aboutToAppear(): void {
    void this.loadFiles();
  }

  /** 加载文件列表（对齐 _loadFiles，失败展示错误文案） */
  private async loadFiles(): Promise<void> {
    const ctrl = this.p.ctrl;
    if (ctrl === undefined) {
      return;
    }
    this.loading = true;
    this.errorText = '';
    try {
      const list = await ctrl.loadTorrentFiles(this.p.torrentId);
      const wanted = new Map<number, boolean>();
      list.forEach((f: TorrentFileEntry): void => {
        wanted.set(f.index, f.wanted);
      });
      this.files = list;
      this.wantedByIndex = wanted;
      this.initialWantedByIndex = new Map<number, boolean>(wanted);
    } catch (e) {
      this.errorText = e instanceof Error ? e.message : `${e}`;
    } finally {
      this.loading = false;
    }
  }

  private isWanted(index: number): boolean {
    return this.wantedByIndex.get(index) !== false;
  }

  /** 是否有未保存修改（对齐 _dirty） */
  private isDirty(): boolean {
    if (this.wantedByIndex.size !== this.initialWantedByIndex.size) {
      return true;
    }
    let dirty = false;
    this.wantedByIndex.forEach((wanted: boolean, index: number): void => {
      if (this.initialWantedByIndex.get(index) !== wanted) {
        dirty = true;
      }
    });
    return dirty;
  }

  private setLocalWanted(index: number, wanted: boolean): void {
    const next = new Map<number, boolean>(this.wantedByIndex);
    next.set(index, wanted);
    this.wantedByIndex = next;
  }

  private setAllLocal(wanted: boolean): void {
    if (this.files.length === 0) {
      return;
    }
    const next = new Map<number, boolean>(this.wantedByIndex);
    this.files.forEach((f: TorrentFileEntry): void => {
      next.set(f.index, wanted);
    });
    this.wantedByIndex = next;
  }

  /** 保存勾选（对齐 _save：成功提示并关闭，失败提示可重试） */
  private async save(): Promise<void> {
    const ctrl = this.p.ctrl;
    if (ctrl === undefined || this.saving || !this.isDirty()) {
      return;
    }
    this.saving = true;
    try {
      await ctrl.saveTorrentFilesSelection(this.p.torrentId, new Map<number, boolean>(this.wantedByIndex));
      ToastUtil.show(L10n.t('transmission_files_saved', '文件选择已保存'));
      this.saving = false;
      this.p.close();
    } catch (_e) {
      ToastUtil.show(L10n.operationFailed);
      this.saving = false;
    }
  }

  private palette(): ThemePalette {
    return AppTheme.current();
  }

  private formatSize(bytes: number): string {
    const ctrl = this.p.ctrl;
    if (ctrl !== undefined) {
      return ctrl.formatBytes(bytes);
    }
    return `${bytes} B`;
  }

  build() {
    Column() {
      SheetHandle()
      Text(L10n.t('transmission_torrent_files', '任务文件'))
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.palette().onSurface)
        .margin({ top: 4, bottom: 4 })

      Text(this.p.torrentName)
        .fontSize(13)
        .fontColor(this.palette().subText)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
        .padding({ left: 20, right: 20 })

      // 全选/全不选（对齐 _files.length > 1 才展示）+ 保存中指示
      if (!this.loading && this.files.length > 1) {
        Row({ space: 12 }) {
          Text(L10n.t('transmission_select_all_files', '全选'))
            .fontSize(13)
            .fontColor(this.palette().primary)
            .padding({ top: 6, bottom: 6 })
            .enabled(!this.saving)
            .onClick((): void => {
              if (!this.saving) {
                this.setAllLocal(true);
              }
            })
          Text(L10n.t('transmission_deselect_all_files', '取消全选'))
            .fontSize(13)
            .fontColor(this.palette().primary)
            .padding({ top: 6, bottom: 6 })
            .enabled(!this.saving)
            .onClick((): void => {
              if (!this.saving) {
                this.setAllLocal(false);
              }
            })
          Blank()
          if (this.saving) {
            LoadingProgress()
              .width(16)
              .height(16)
              .color(this.palette().primary)
          }
        }
        .width('100%')
        .padding({ left: 20, right: 20, top: 4 })
      }

      // 文件列表 / 加载中 / 错误 / 空态
      if (this.loading) {
        Column() {
          LoadingProgress()
            .width(28)
            .height(28)
            .color(this.palette().primary)
        }
        .width('100%')
        .height(160)
        .justifyContent(FlexAlign.Center)
      } else if (this.errorText.length > 0) {
        Column() {
          Text(this.errorText)
            .fontSize(13)
            .fontColor(this.palette().error)
            .textAlign(TextAlign.Center)
        }
        .width('100%')
        .height(160)
        .justifyContent(FlexAlign.Center)
        .padding({ left: 20, right: 20 })
      } else if (this.files.length === 0) {
        Column() {
          Text(L10n.t('transmission_no_files', '暂无文件'))
            .fontSize(13)
            .fontColor(this.palette().subText)
        }
        .width('100%')
        .height(160)
        .justifyContent(FlexAlign.Center)
      } else {
        List({ space: 0 }) {
          ForEach(this.files, (f: TorrentFileEntry) => {
            ListItem() {
              this.FileRow(f)
            }
          }, (f: TorrentFileEntry): string =>
            `${f.index}_${f.name}_${this.isWanted(f.index) ? '1' : '0'}`)
        }
        .width('100%')
        .constraintSize({ maxHeight: 380 })
        .scrollBar(BarState.Auto)
        .padding({ top: 4, bottom: 8 })
      }

      // 底部动作（对齐 取消 + 保存）
      Row({ space: 12 }) {
        Button(L10n.t('cancel', '取消'))
          .fontSize(14)
          .fontColor(this.palette().primary)
          .backgroundColor(Color.Transparent)
          .height(38)
          .enabled(!this.saving)
          .opacity(this.saving ? 0.5 : 1)
          .onClick((): void => {
            this.p.close();
          })
        Button(L10n.t('save', '保存'))
          .fontSize(14)
          .fontColor(this.palette().buttonText)
          .backgroundColor(this.palette().buttonBg)
          .height(38)
          .enabled(!this.saving && this.isDirty())
          .opacity(this.saving || !this.isDirty() ? 0.5 : 1)
          .onClick((): void => {
            void this.save();
          })
      }
      .justifyContent(FlexAlign.End)
      .width('100%')
      .padding({ left: 20, right: 20, top: 6, bottom: 20 })
    }
    .width('100%')
    .borderRadius({ topLeft: 20, topRight: 20 })
    .backgroundColor(AppTheme.current().surfaceBg)
    .constraintSize({ maxHeight: '88%' })
  }

  /** 文件行（对齐 CheckboxListTile：前置勾选框 + 文件名 + 大小） */
  @Builder
  FileRow(f: TorrentFileEntry) {
    Row({ space: 10 }) {
      CircleCheckbox({
        value: this.isWanted(f.index),
        onChanged: (checked: boolean): void => {
          if (!this.saving) {
            this.setLocalWanted(f.index, checked);
          }
        }
      })
      Column({ space: 2 }) {
        Text(f.name.length > 0 ? f.name : '-')
          .fontSize(12.5)
          .fontColor(this.palette().onSurface)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.formatSize(f.length))
          .fontSize(11)
          .fontColor(this.palette().subText)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .width('100%')
    .padding({ left: 20, right: 16, top: 8, bottom: 8 })
    .onClick((): void => {
      if (!this.saving) {
        this.setLocalWanted(f.index, !this.isWanted(f.index));
      }
    })
  }
}

/** 打开任务文件选择弹层 */
export function showTorrentFilesSheet(ctrl: TransmissionController, torrentId: number,
  torrentName: string): void {
  const p = new TorrentFilesSheetParams();
  p.ctrl = ctrl;
  p.torrentId = torrentId;
  p.torrentName = torrentName;
  SheetUtil.present(p, wrapBuilder(TorrentFilesSheetContent));
}
