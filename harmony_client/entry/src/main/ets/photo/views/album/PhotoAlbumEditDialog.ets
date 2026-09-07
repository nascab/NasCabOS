import { L10n } from '../../../core/localization/L10n';
import { AppTheme } from '../../../core/theme/AppTheme';
import { DialogUtil } from '../../../common/DialogUtil';
import { PhotoAlbumItem } from '../../models/PhotoAlbumModels';
import { PhotoAlbumApiService } from '../../service/PhotoAlbumApiService';

/**
 * 新建/编辑相册弹窗（对齐 Flutter photo_album_create_edit_dialog.dart 的
 * showPhotoAlbumCreateDialogWithSubmit / showPhotoAlbumEditDialogWithSubmit）：
 * 全屏遮罩 + 居中卡片（结构对齐 home/views/HomeUserInfoDialog.ets）。
 * album 为 undefined 时是创建模式；成功后回调 onSaved + onDismiss。
 */
@ComponentV2
export struct PhotoAlbumEditDialog {
  /** 编辑目标；undefined 表示创建模式 */
  @Param album: PhotoAlbumItem | undefined = undefined;
  @Param onDismiss: () => void = (): void => {
  };
  @Param onSaved: () => void = (): void => {
  };
  @Local name: string = '';
  @Local isPublic: boolean = false;
  @Local nameError: string = '';
  @Local saving: boolean = false;
  private albumApi: PhotoAlbumApiService = new PhotoAlbumApiService();

  aboutToAppear(): void {
    // 编辑模式预填（对齐 Flutter nameCtrl = TextEditingController(text: album.name)）
    if (this.album !== undefined) {
      this.name = this.album.name;
      this.isPublic = this.album.isPublic;
    }
  }

  private dialogTitle(): string {
    return this.album === undefined
      ? L10n.t('photo_album_create', '新建相册')
      : L10n.t('photo_album_edit', '编辑相册');
  }

  private confirmLabel(): string {
    return this.album === undefined ? L10n.t('create', '创建') : L10n.t('ok', '确定');
  }

  private async confirm(): Promise<void> {
    const trimmed = this.name.trim();
    if (trimmed.length === 0) {
      // 名称非空校验（Flutter 端为置灰按钮，这里给出提示）
      this.nameError = L10n.t('input_please', '请输入');
      return;
    }
    if (this.saving) {
      return;
    }
    this.saving = true;
    try {
      const res = this.album === undefined
        ? await this.albumApi.createAlbum(trimmed, this.isPublic)
        : await this.albumApi.updateAlbum(this.album.id, trimmed, this.isPublic);
      if (res.success) {
        this.onSaved();
        this.onDismiss();
        return;
      }
      if (res.message !== undefined && res.message.length > 0) {
        await DialogUtil.showInfoDialog(L10n.tip, res.message);
      }
    } finally {
      this.saving = false;
    }
  }

  build() {
    Stack() {
      // 遮罩（点击关闭，对齐 Flutter 点击 dialog 外区域 pop）
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#80000000')
        .onClick(() => {
          this.onDismiss();
        })

      Column() {
        Text(this.dialogTitle())
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppTheme.current().onSurface)

        // 名称输入（对齐 Flutter TextField labelText: photo_album_name）
        TextInput({ text: this.name, placeholder: L10n.t('photo_album_name', '相册名称') })
          .fontSize(14)
          .fontColor(AppTheme.current().onSurface)
          .placeholderColor(AppTheme.current().hint)
          .backgroundColor(AppTheme.current().inputFill)
          .borderRadius(8)
          .border({ width: 1, color: AppTheme.current().inputBorder })
          .height(42)
          .margin({ top: 16 })
          .width('100%')
          .onChange((v: string) => {
            this.name = v;
            if (v.trim().length > 0 && this.nameError.length > 0) {
              this.nameError = '';
            }
          })
        if (this.nameError.length > 0) {
          Text(this.nameError)
            .fontSize(12)
            .fontColor(AppTheme.current().error)
            .margin({ top: 6 })
            .width('100%')
        }

        // 公开开关（对齐 Flutter SwitchListTile + 帮助提示）
        Row({ space: 8 }) {
          Column() {
            Text(L10n.t('photo_album_public', '公开相册'))
              .fontSize(14)
              .fontColor(AppTheme.current().onSurface)
            Text(L10n.t('photo_album_public_help', '公开相册可以被系统内所有用户查看'))
              .fontSize(11)
              .fontColor(AppTheme.current().hint)
              .margin({ top: 2 })
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          Toggle({ type: ToggleType.Switch, isOn: this.isPublic })
            .selectedColor(AppTheme.current().primary)
            .onChange((on: boolean) => {
              this.isPublic = on;
            })
        }
        .width('100%')
        .alignItems(VerticalAlign.Top)
        .margin({ top: 16 })

        // 取消 + 确认
        Row({ space: 8 }) {
          Button(L10n.cancel)
            .fontSize(14)
            .fontColor(AppTheme.current().primary)
            .backgroundColor(Color.Transparent)
            .height(36)
            .onClick(() => {
              this.onDismiss();
            })
          Button(this.confirmLabel())
            .fontSize(14)
            .fontColor(AppTheme.current().buttonText)
            .backgroundColor(AppTheme.current().buttonBg)
            .height(36)
            .enabled(!this.saving)
            .opacity(this.saving ? 0.5 : 1)
            .onClick(() => {
              void this.confirm();
            })
        }
        .justifyContent(FlexAlign.End)
        .margin({ top: 20 })
        .width('100%')
      }
      .alignItems(HorizontalAlign.Start)
      .padding(20)
      .borderRadius(24)
      .backgroundColor(AppTheme.current().surfaceBg)
      .width('80%')
      .constraintSize({ minWidth: 280, maxWidth: 420 })
    }
    .width('100%')
    .height('100%')
    .alignContent(Alignment.Center)
  }
}
