import { L10n } from '../../../core/localization/L10n';
import { AppTheme, ThemePalette } from '../../../core/theme/AppTheme';
import { AppEventBus } from '../../../common/AppEventBus';
import { LanguageService } from '../../../core/localization/LanguageService';
import { PageScaffold } from '../../../common/PageScaffold';
import { NavUtil } from '../../../common/NavUtil';
import { ToastUtil } from '../../../common/ToastUtil';
import { PickOption, showOptionPickSheet } from '../../../common/components/OptionPickSheet';
import { pickTargetFolderViaSheet } from '../../../files/views/FolderPickerSheet';
import { PhotoAlbumService } from '../services/PhotoAlbumService';
import { PhotoBackupController } from '../controllers/PhotoBackupController';
import { PhotoBackupSourceType, PhotoBackupTask } from '../models/PhotoBackupModels';
import {
  PhotoBackupRoutes, PhotoBackupTaskFormPageParam, PhotoBackupAlbumPickerPageParam
} from '../router/PhotoBackupRoutes';

/**
 * 备份任务 新增/编辑页（对齐 Flutter _PhotoBackupTaskFormView）：
 * 来源行卡（点击选相册）+ 目标目录行卡（选文件夹）+ 同名文件策略 chips（skip/overwrite/rename）
 * + 保存类型（根目录/按日/按月/按年）+ 实况视频开关 + 自动备份开关 + 底部保存按钮。
 */
@ComponentV2
export struct PhotoBackupTaskFormPage {
  @Param param: PhotoBackupTaskFormPageParam = new PhotoBackupTaskFormPageParam();
  @Param popPage: () => void = (): void => {
  };
  /** 控制器为模块级单例（与主页共用） */
  private ctrl: PhotoBackupController = PhotoBackupController.getInstance();

  @Local sourceType: PhotoBackupSourceType = PhotoBackupSourceType.FOLDER;
  /** 是否已选择来源（对齐 Flutter _sourceType 可空语义） */
  @Local hasSource: boolean = false;
  @Local sourceId: string = '';
  @Local sourceName: string = '';
  @Local targetText: string = '';
  @Local nameStrategy: string = 'skip';
  @Local saveType: string = '';
  @Local uploadLivePhotoVideo: boolean = false;
  @Local autoStartOnLaunch: boolean = false;
  @Local saving: boolean = false;
  /** 依赖 localeBump：切换语言后触发整页刷新 */
  @Local localeBump: number = 0;
  private localeListener: (data: string) => void = (_data: string): void => {
    this.localeBump++;
  };

  private get isEdit(): boolean {
    return this.param.initial !== undefined;
  }

  private palette(): ThemePalette {
    return AppTheme.current();
  }

  aboutToAppear(): void {
    AppEventBus.on(LanguageService.EVENT_LOCALE_CHANGED, this.localeListener);
    const init = this.param.initial;
    if (init === undefined) {
      return;
    }
    this.sourceType = init.sourceType;
    this.hasSource = true;
    this.sourceId = init.sourceId;
    this.sourceName = init.sourceName;
    this.targetText = init.targetDir;
    this.nameStrategy = init.nameStrategy.length > 0 ? init.nameStrategy : 'skip';
    this.saveType = init.saveType;
    this.uploadLivePhotoVideo = init.uploadLivePhotoVideo;
    this.autoStartOnLaunch = init.autoStartOnLaunch;
  }

  aboutToDisappear(): void {
    AppEventBus.off(LanguageService.EVENT_LOCALE_CHANGED, this.localeListener);
  }

  // ===== 交互（对齐 Flutter _pickSource/_pickTargetDir/_save） =====

  /** 选相册：先请求权限，再进相册选择页选回填（对齐 Flutter _pickSource） */
  private async pickSource(): Promise<void> {
    const granted = await PhotoAlbumService.ensurePermission();
    if (!granted) {
      return;
    }
    const p = new PhotoBackupAlbumPickerPageParam();
    p.onPicked = (album): void => {
      this.sourceType = PhotoBackupSourceType.ALBUM;
      this.hasSource = true;
      this.sourceId = album.id;
      this.sourceName = album.name.trim().length === 0 ? 'album' : album.name.trim();
    };
    NavUtil.push(PhotoBackupRoutes.PAGE_ALBUM_PICKER, p);
  }

  /** 选目标目录（对齐 Flutter _pickTargetDir：showFolderPickerBottomSheet 单选） */
  private pickTarget(): void {
    pickTargetFolderViaSheet(this.targetText.trim(), (paths: string[]): void => {
      if (paths.length === 0) {
        return;
      }
      this.targetText = paths[0].trim();
    });
  }

  /** 选保存类型（对齐 Flutter DropdownButtonFormField 四项） */
  private pickSaveType(): void {
    const options: PickOption[] = [
      new PickOption('', L10n.t('upload_center_save_type_root', '保存到根目录(默认)')),
      new PickOption('day', L10n.t('upload_center_save_type_day', '按年/月/日保存')),
      new PickOption('month', L10n.t('upload_center_save_type_month', '按年/月保存')),
      new PickOption('year', L10n.t('upload_center_save_type_year', '按年保存'))
    ];
    showOptionPickSheet(L10n.t('upload_center_save_type', '保存类型'), options, this.saveType,
      (key: string): void => {
        this.saveType = key;
      });
  }

  /** 保存（对齐 Flutter _save：校验 → saving → saveTask → 返回） */
  private async save(): Promise<void> {
    if (this.saving) {
      return;
    }
    if (!this.hasSource || this.sourceId.trim().length === 0
      || this.targetText.trim().length === 0) {
      ToastUtil.show(L10n.t('photo_backup_required', '请先完善必填项'));
      return;
    }
    this.saving = true;
    try {
      const ok = await this.ctrl.saveTask(
        this.isEdit && this.param.initial !== undefined ? this.param.initial.id : 0,
        this.sourceType,
        this.sourceId.trim(),
        this.sourceName.trim(),
        this.targetText.trim(),
        this.nameStrategy,
        this.saveType,
        this.uploadLivePhotoVideo,
        this.autoStartOnLaunch);
      if (!ok) {
        return;
      }
      this.popPage();
    } finally {
      this.saving = false;
    }
  }

  build() {
    PageScaffold({
      title: this.isEdit
        ? L10n.t('photo_backup_edit', '编辑备份任务')
        : L10n.t('photo_backup_create', '创建备份任务'),
      showBack: true,
      // 保存中阻止返回（对齐 Flutter 保存按钮禁用语义）
      customBack: (): boolean => {
        return this.saving;
      },
      onBack: (): void => {
        this.popPage();
      },
      content: (): void => {
        this.FormBody()
      }
    })
  }

  @Builder
  FormBody() {
    Column() {
      Scroll() {
        Column() {
          // 来源行卡（对齐 Flutter _lineCard source）
          this.LineCard($r('sys.symbol.picture'),
            L10n.t('photo_backup_source', '要备份的相册'),
            !this.hasSource
              ? L10n.t('photo_backup_source_empty', '请选择要备份的相册')
              : `${this.sourceType === PhotoBackupSourceType.ALBUM
                ? L10n.t('photo_backup_source_album', '相册')
                : L10n.t('photo_backup_source_folder', '文件夹')} · ${this.sourceName}`,
            (): void => {
              void this.pickSource();
            })
          // 目标目录行卡（对齐 Flutter _lineCard target）
          Column() {
            this.LineCard($r('sys.symbol.folder'),
              L10n.t('photo_backup_target', '目标文件夹'),
              this.targetText.trim().length === 0
                ? L10n.t('quick_share_path_hint', '未选择路径')
                : this.targetText.trim(),
              (): void => {
                this.pickTarget();
              })
          }
          .width('100%')
          .margin({ top: 10 })

          // 同名文件策略 chips（对齐 Flutter ChoiceChip skip/overwrite/rename）
          Text(L10n.t('folder_name_strategy', '同名文件策略'))
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.palette().onSurface)
            .width('100%')
            .margin({ top: 16 })
          Flex({ wrap: FlexWrap.Wrap }) {
            ForEach(['skip', 'overwrite', 'rename'], (v: string) => {
              Text(L10n.t(v, v))
                .fontSize(13)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.nameStrategy === v ? this.palette().buttonText : this.palette().onSurface)
                .padding({ left: 14, right: 14, top: 7, bottom: 7 })
                .borderRadius(18)
                .backgroundColor(this.nameStrategy === v ? this.palette().buttonBg : this.palette().inputFill)
                .border({
                  width: 1,
                  color: this.nameStrategy === v ? this.palette().buttonBg : this.palette().divider
                })
                .margin({ right: 8, top: 4 })
                .onClick((): void => {
                  this.nameStrategy = v;
                })
            }, (v: string): string => `${v}_${this.nameStrategy === v}_${this.localeBump}`)
          }
          .width('100%')
          .margin({ top: 8 })

          // 保存类型下拉（对齐 Flutter DropdownButtonFormField）
          Text(L10n.t('upload_center_save_type', '保存类型'))
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.palette().onSurface)
            .width('100%')
            .margin({ top: 16 })
          Row({ space: 8 }) {
            Text(this.saveTypeDisplay())
              .fontSize(14)
              .fontColor(this.palette().onSurface)
              .maxLines(1)
              .layoutWeight(1)
            SymbolGlyph($r('sys.symbol.chevron_down'))
              .fontSize(14)
              .fontColor([this.palette().hint])
          }
          .width('100%')
          .height(44)
          .padding({ left: 12, right: 12 })
          .borderRadius(8)
          .backgroundColor(this.palette().inputFill)
          .border({ width: 1, color: this.palette().inputBorder })
          .margin({ top: 8 })
          .onClick((): void => {
            this.pickSaveType();
          })

          // 上传 Live Photo 视频 开关（对齐 Flutter SwitchListTile + subtitle）
          Row() {
            Column({ space: 2 }) {
              Text(L10n.t('photo_backup_upload_livephoto_video', '上传 Live Photo 中的视频'))
                .fontSize(14)
                .fontColor(this.palette().onSurface)
              Text(L10n.t('photo_backup_upload_livephoto_video_hint',
                '开启后会尝试同时上传 Live Photo 关联的视频文件'))
                .fontSize(12)
                .fontColor(this.palette().subText)
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
            Toggle({ type: ToggleType.Switch, isOn: this.uploadLivePhotoVideo })
              .selectedColor(this.palette().primary)
              .onChange((isOn: boolean): void => {
                this.uploadLivePhotoVideo = isOn;
              })
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
          .margin({ top: 16 })

          // App 打开时自动开始备份 开关（对齐 Flutter SwitchListTile）
          Row() {
            Text(L10n.t('photo_backup_auto_start', 'App 打开时自动开始备份'))
              .fontSize(14)
              .fontColor(this.palette().onSurface)
              .layoutWeight(1)
            Toggle({ type: ToggleType.Switch, isOn: this.autoStartOnLaunch })
              .selectedColor(this.palette().primary)
              .onChange((isOn: boolean): void => {
                this.autoStartOnLaunch = isOn;
              })
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
          .margin({ top: 12 })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding({ left: 12, right: 12, top: 12, bottom: 24 })
      }
      .width('100%')
      .layoutWeight(1)
      .align(Alignment.Top)
      .scrollBar(BarState.Auto)
      .opacity(this.localeBump >= 0 ? 1 : 1)

      // 底部保存按钮（对齐 Flutter bottomNavigationBar FilledButton）
      Button(this.saving ? L10n.t('loading', '加载中...') : L10n.t('save', '保存'))
        .fontSize(15)
        .fontColor(this.palette().buttonText)
        .backgroundColor(this.palette().buttonBg)
        .borderRadius(22)
        .height(44)
        .width('100%')
        .enabled(!this.saving)
        .opacity(this.saving ? 0.6 : 1)
        .margin({ left: 12, right: 12, bottom: 16 })
        .onClick((): void => {
          void this.save();
        })
    }
    .width('100%')
    .height('100%')
  }

  private saveTypeDisplay(): string {
    const v = this.saveType.trim().toLowerCase();
    if (v === 'day') {
      return L10n.t('upload_center_save_type_day', '按年/月/日保存');
    }
    if (v === 'month') {
      return L10n.t('upload_center_save_type_month', '按年/月保存');
    }
    if (v === 'year') {
      return L10n.t('upload_center_save_type_year', '按年保存');
    }
    return L10n.t('upload_center_save_type_root', '保存到根目录(默认)');
  }

  /** 行卡（对齐 Flutter _lineCard：图标 + 标题/副标题 + 右箭头） */
  @Builder
  LineCard(icon: Resource, title: string, subtitle: string, onTap: () => void) {
    Row({ space: 10 }) {
      SymbolGlyph(icon)
        .fontSize(22)
        .fontColor([this.palette().primary])
      Column({ space: 2 }) {
        Text(title)
          .fontSize(14)
          .fontColor(this.palette().onSurface)
        Text(subtitle)
          .fontSize(12)
          .fontColor(this.palette().subText)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(16)
        .fontColor([this.palette().hint])
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .padding({ left: 12, right: 12, top: 10, bottom: 10 })
    .borderRadius(12)
    .backgroundColor(this.palette().surfaceBg)
    .border({ width: 1, color: this.palette().divider })
    .onClick((): void => {
      onTap();
    })
  }
}
