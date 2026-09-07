import { L10n } from '../../../core/localization/L10n';
import { AppTheme } from '../../../core/theme/AppTheme';
import { DialogUtil } from '../../../common/DialogUtil';
import { pickTargetFolderViaSheet } from '../../../files/views/FolderPickerSheet';
import { PhotoCollectionItem } from '../../models/PhotoAlbumModels';

/**
 * 新建/编辑照片合集弹窗（对齐 Flutter photo_collection_create_edit_dialog.dart）：
 * 全屏遮罩 + 居中卡片。collection 为 undefined 时是创建模式；
 * 提交回调由列表页注入（走控制器 createCollection/updateCollection），
 * 成功后回调 onDismiss 关闭弹窗。
 */
@ComponentV2
export struct PhotoCollectionEditDialog {
  /** 编辑目标；undefined 表示创建模式 */
  @Param collection: PhotoCollectionItem | undefined = undefined;
  /** 提交回调：返回 true 表示成功（列表页注入控制器 create/update 包装） */
  @Param onSubmit: (name: string, pathList: string[]) => Promise<boolean> =
    (_name: string, _pathList: string[]): Promise<boolean> => Promise.resolve(false);
  @Param onDismiss: () => void = (): void => {
  };
  @Local name: string = '';
  @Local pathList: string[] = [];
  @Local saving: boolean = false;

  aboutToAppear(): void {
    // 编辑模式预填（对齐 Flutter nameCtrl = TextEditingController(text: collection.name)）
    if (this.collection !== undefined) {
      this.name = this.collection.name;
      this.pathList = this.collection.pathList.slice();
    }
  }

  /** 校验：名称非空且路径非空（对齐 Flutter canSubmit） */
  private canSubmit(): boolean {
    return this.name.trim().length > 0 && this.pathList.length > 0;
  }

  private dialogTitle(): string {
    return this.collection === undefined
      ? L10n.t('photo_create_collection', '创建合集')
      : L10n.t('edit', '编辑');
  }

  private confirmLabel(): string {
    return this.collection === undefined ? L10n.t('create', '创建') : L10n.t('ok', '确定');
  }

  /** 选择路径：弹文件夹选择层，确认后追加不重复的路径（对齐 Flutter showFolderPickerBottomSheet） */
  private choosePath(): void {
    pickTargetFolderViaSheet('', (paths: string[]): void => {
      if (paths.length === 0) {
        return;
      }
      const next = this.pathList.slice();
      for (const p of paths) {
        const t = p.trim();
        if (t.length === 0) {
          continue;
        }
        if (next.indexOf(t) < 0) {
          next.push(t);
        }
      }
      this.pathList = next;
    });
  }

  /** 移除一行路径（对齐 Flutter pathList.removeAt） */
  private removePath(index: number): void {
    const next: string[] = [];
    for (let i = 0; i < this.pathList.length; i++) {
      if (i !== index) {
        next.push(this.pathList[i]);
      }
    }
    this.pathList = next;
  }

  private async confirm(): Promise<void> {
    if (!this.canSubmit() || this.saving) {
      return;
    }
    this.saving = true;
    try {
      const ok = await this.onSubmit(this.name.trim(), this.pathList.slice());
      if (ok) {
        this.onDismiss();
      }
    } finally {
      this.saving = false;
    }
  }

  build() {
    Stack() {
      // 遮罩（点击关闭）
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

        Scroll() {
          Column() {
            // 校验提示（对齐 Flutter 标题旁 info 图标的 photo_create_collection_alert 文案）
            if (!this.canSubmit()) {
              Text(L10n.t('photo_create_collection_alert', '集合多个来源目录或来源目录的子目录,一起显示到合集中'))
                .fontSize(12)
                .fontColor(AppTheme.current().hint)
                .margin({ top: 10 })
                .width('100%')
            }

            // 名称输入（对齐 Flutter TextField labelText: photo_collection_name）
            TextInput({ text: this.name, placeholder: L10n.t('photo_collection_name', '合集名称') })
              .fontSize(14)
              .fontColor(AppTheme.current().onSurface)
              .placeholderColor(AppTheme.current().hint)
              .backgroundColor(AppTheme.current().inputFill)
              .borderRadius(8)
              .border({ width: 1, color: AppTheme.current().inputBorder })
              .height(42)
              .margin({ top: 12 })
              .width('100%')
              .onChange((v: string) => {
                this.name = v;
              })

            // 选择路径按钮（对齐 Flutter ElevatedButton.icon choose_path）
            Button() {
              Row({ space: 6 }) {
                SymbolGlyph($r('sys.symbol.folder'))
                  .fontSize(16)
                  .fontColor([AppTheme.current().buttonText])
                Text(L10n.t('choose_path', '选择路径'))
                  .fontSize(14)
                  .fontColor(AppTheme.current().buttonText)
              }
            }
            .height(40)
            .borderRadius(8)
            .backgroundColor(AppTheme.current().buttonBg)
            .width('100%')
            .margin({ top: 12 })
            .onClick(() => {
              this.choosePath();
            })

            // 路径列表（对齐 Flutter maxHeight 220 的 SingleChildScrollView）
            if (this.pathList.length > 0) {
              Scroll() {
                Column({ space: 6 }) {
                  ForEach(this.pathList, (p: string, idx: number) => {
                    Row({ space: 8 }) {
                      Text(p)
                        .fontSize(13)
                        .fontColor(AppTheme.current().onSurface)
                        .maxLines(2)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                        .layoutWeight(1)
                      SymbolGlyph($r('sys.symbol.xmark'))
                        .fontSize(15)
                        .fontColor([AppTheme.current().hint])
                        .onClick(() => {
                          this.removePath(idx);
                        })
                    }
                    .alignItems(VerticalAlign.Center)
                    .width('100%')
                    .padding({ left: 10, right: 10, top: 6, bottom: 6 })
                    .borderRadius(8)
                    .border({ width: 1, color: AppTheme.current().divider })
                  }, (p: string, idx: number) => `path_${idx}_${p}`)
                }
                .width('100%')
              }
              .constraintSize({ maxHeight: 220 })
              .scrollBar(BarState.Auto)
              .width('100%')
              .margin({ top: 12 })
            }
          }
          .width('100%')
        }
        .scrollBar(BarState.Off)
        .width('100%')
        .align(Alignment.Top)
        .margin({ top: 14 })
        .constraintSize({ maxHeight: 420 })

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
            .enabled(this.canSubmit() && !this.saving)
            .opacity(this.canSubmit() && !this.saving ? 1 : 0.45)
            .onClick(() => {
              void this.confirm();
            })
        }
        .justifyContent(FlexAlign.End)
        .margin({ top: 16 })
        .width('100%')
      }
      .alignItems(HorizontalAlign.Start)
      .padding(20)
      .borderRadius(24)
      .backgroundColor(AppTheme.current().surfaceBg)
      .width('84%')
      .constraintSize({ minWidth: 300, maxWidth: 520 })
    }
    .width('100%')
    .height('100%')
    .alignContent(Alignment.Center)
  }
}
