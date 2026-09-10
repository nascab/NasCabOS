import { L10n } from '../../../core/localization/L10n';
import { AppTheme } from '../../../core/theme/AppTheme';
import { DialogUtil } from '../../../common/DialogUtil';
import { GlassCard } from '../../../common/components/GlassCard';
import { EmptyState } from '../../../common/components/EmptyState';
import { CircleCheckbox } from '../../../common/components/CircleCheckbox';
import { PickOption, showOptionPickSheet } from '../../../common/components/OptionPickSheet';
import { pickServerFileViaSheet } from '../../../files/views/FolderPickerSheet';
import { QuickShareItem } from '../models/ShareServerModels';
import { QuickShareController } from '../controllers/QuickShareController';
import { QrCodeView } from './parts/QrCodeView';

/**
 * 快速分享面板（对齐 Flutter QuickShareConfigView 移动端形态）：
 * 顶部操作卡（清理失效链接/创建分享）+ 分享卡片列表；
 * 创建分享弹窗（路径/密码/备注/时限/单位/无期限）、分享链接二维码弹窗。
 */
@ComponentV2
export struct QuickShareView {
  /** 创建分享预填路径（对齐 Flutter initialCreatePath / arguments['quickShareCreatePath']） */
  @Param initialCreatePath: string = '';
  /** 主题变化刷新计数（主页传入，驱动本面板重渲染换色） */
  @Param themeTick: number = 0;
  @Local ctrl: QuickShareController = new QuickShareController();
  @Local showCreate: boolean = false;
  @Local qrShow: boolean = false;

  aboutToAppear(): void {
    void this.ctrl.refreshList(false);
    const init = this.initialCreatePath.trim();
    if (init.length > 0) {
      this.cPath = init;
      this.showCreate = true;
    }
  }

  // ===== 创建分享弹窗状态（对齐 _QuickShareCreateDialogState） =====
  @Local cPath: string = '';
  @Local cPwd: string = '';
  @Local cRemark: string = '';
  @Local cDuration: string = '7';
  @Local cUnit: string = 'day';
  @Local cNoLimit: boolean = false;
  @Local cSubmitting: boolean = false;

  // ===== 二维码弹窗状态（对齐 _showQrCodeDialog） =====
  @Local qrUrl: string = '';
  @Local qrIsRemote: boolean = false;
  @Local qrInput: string = '';
  @Local qrText: string = '';

  private palette() {
    return AppTheme.current();
  }

  private unitLabel(): string {
    return this.cUnit === 'hour'
      ? L10n.t('quick_share_unit_hour', '小时')
      : L10n.t('quick_share_unit_day', '天');
  }

  private openCreate(): void {
    this.cPath = '';
    this.cPwd = '';
    this.cRemark = '';
    this.cDuration = '7';
    this.cUnit = 'day';
    this.cNoLimit = false;
    this.showCreate = true;
  }

  private pickCreatePath(): void {
    // 对齐 Flutter showFolderPickerBottomSheet(allowFileSelect: true)
    pickServerFileViaSheet('', (paths: string[]): void => {
      if (paths.length === 0) {
        return;
      }
      this.cPath = paths[0].trim();
    });
  }

  private async submitCreate(): Promise<void> {
    if (this.cSubmitting) {
      return;
    }
    const path = this.cPath.trim();
    if (path.length === 0) {
      DialogUtil.showErrorDialog(L10n.t('quick_share_path_required', '请选择路径'));
      return;
    }
    const pwd = this.cPwd.trim();
    if (pwd.length === 0) {
      DialogUtil.showErrorDialog(L10n.t('quick_share_password_required', '请输入访问密码'));
      return;
    }
    const durationValue = parseInt(this.cDuration.trim());
    const remark = this.cRemark.trim();
    this.cSubmitting = true;
    try {
      const ok = await this.ctrl.createShare(path, pwd,
        remark.length > 0 ? remark : undefined,
        this.cNoLimit ? undefined : (Number.isFinite(durationValue) ? durationValue : undefined),
        this.cUnit, this.cNoLimit);
      if (ok) {
        this.showCreate = false;
      }
    } finally {
      this.cSubmitting = false;
    }
  }

  private showQr(url: string, isRemote: boolean): void {
    this.qrUrl = url;
    this.qrIsRemote = isRemote;
    this.qrInput = url;
    this.qrText = url;
    this.qrShow = true;
  }

  private regenerateQr(): void {
    const v = this.qrInput.trim();
    if (v.length > 0) {
      this.qrText = v;
    }
  }

  /** 远程访问引导（对齐 Flutter _goToRemoteAccess；service 模块未迁移，暂以提示弹窗呈现） */
  private goRemoteGuide(): void {
    DialogUtil.showInfoDialog(L10n.tip,
      L10n.t('quick_share_remote_link_guide', '去开启远程访问，获得远程访问分享地址'));
  }

  private confirmDelete(item: QuickShareItem): void {
    DialogUtil.showConfirmDialog(L10n.delete,
      L10n.t('quick_share_delete_confirm', '确定删除该分享吗？'),
      (): void => {
        void this.ctrl.deleteShare(item.id);
      });
  }

  build() {
    Stack() {
      Column() {
        // 顶部操作卡（对齐 Flutter CustomGlassCard 操作行）
        GlassCard({
          padValue: { left: 12, right: 12, top: 10, bottom: 10 }
        }) {
          Row() {
            Blank()
            this.HeaderAction($r('sys.symbol.arrow_clockwise'),
              L10n.t('quick_share_clean_expired', '清理失效链接'), (): void => {
                void this.ctrl.cleanExpired();
              }, 0)
            this.HeaderAction($r('sys.symbol.plus'),
              L10n.t('quick_share_create', '创建分享'), (): void => {
                this.openCreate();
              }, 16)
          }
          .width('100%')
        }

        // 分享列表
        if (this.ctrl.items.length === 0) {
          Column() {
            EmptyState({ message: L10n.t('no_data', '暂无数据') })
          }
          .width('100%')
          .layoutWeight(1)
        } else {
          List({ space: 14 }) {
            ForEach(this.ctrl.items, (item: QuickShareItem) => {
              ListItem() {
                this.ShareItemCard(item)
              }
            }, (item: QuickShareItem) => `${item.id}_${item.token}_${item.path}`)
          }
          .width('100%')
          .layoutWeight(1)
          .scrollBar(BarState.Auto)
        }
      }
      .padding({ left: 12, right: 12, top: 12, bottom: 12 })
      .width('100%')
      .height('100%')

      if (this.showCreate) {
        this.CreateDialogOverlay()
      }
      if (this.qrShow) {
        this.QrDialogOverlay()
      }
    }
    .width('100%')
    .height('100%')
    .alignContent(Alignment.Center)
    .opacity(this.themeTick >= 0 ? 1 : 1)
  }

  /** 顶部文字按钮（对齐 Flutter CustomButton text+icon；leftMargin 为左侧间距） */
  @Builder
  HeaderAction(icon: Resource, label: string, onTap: () => void, leftMargin: number) {
    Row({ space: 6 }) {
      SymbolGlyph(icon)
        .fontSize(16)
        .fontColor([this.palette().primary])
      Text(label)
        .fontSize(14)
        .fontColor(this.palette().primary)
        .maxLines(1)
    }
    .margin({ left: leftMargin })
    .padding({ left: 10, right: 10, top: 7, bottom: 7 })
    .borderRadius(10)
    .border({ width: 1, color: this.palette().divider })
    .onClick(() => {
      onTap();
    })
  }

  /** 分享卡片（对齐 _ShareItemCard） */
  @Builder
  ShareItemCard(item: QuickShareItem) {
    GlassCard({
      padValue: 12
    }) {
      Column() {
        // 路径 + 删除
        Row({ space: 8 }) {
          SymbolGlyph($r('sys.symbol.folder'))
            .fontSize(18)
            .fontColor([this.palette().subText])
          Text(item.path)
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.palette().onSurface)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
          SymbolGlyph($r('sys.symbol.trash'))
            .fontSize(18)
            .fontColor([this.palette().subText])
            .opacity(item.id > 0 ? 1 : 0.4)
            .onClick(() => {
              if (item.id > 0) {
                this.confirmDelete(item);
              }
            })
        }
        .width('100%')
        .alignItems(VerticalAlign.Top)

        // 本地链接
        Row({ space: 6 }) {
          SymbolGlyph($r('sys.symbol.doc_text'))
            .fontSize(15)
            .fontColor([this.palette().subText])
          this.LinkText(`${L10n.t('quick_share_local_link', '本地链接')}: ${this.ctrl.buildLocalShareUrl(item.token)}`,
            (): void => {
              this.showQr(this.ctrl.buildLocalShareUrl(item.token), false);
            })
          this.TextAction(L10n.t('quick_share_copy_link', '复制链接'), (): void => {
            this.ctrl.copyText(this.ctrl.buildLocalShareUrl(item.token));
          })
        }
        .width('100%')
        .margin({ top: 8 })
        .alignItems(VerticalAlign.Center)

        // 远程链接 / 引导
        if (this.remoteUrlOf(item).length > 0) {
          Row({ space: 6 }) {
            SymbolGlyph($r('sys.symbol.cloud'))
              .fontSize(15)
              .fontColor([this.palette().subText])
            this.LinkText(`${L10n.t('quick_share_remote_link', '远程链接')}: ${this.remoteUrlOf(item)}`,
              (): void => {
                this.showQr(this.remoteUrlOf(item), true);
              })
            this.TextAction(L10n.t('quick_share_copy_link', '复制链接'), (): void => {
              this.ctrl.copyText(this.remoteUrlOf(item));
            })
          }
          .width('100%')
          .margin({ top: 6 })
          .alignItems(VerticalAlign.Center)
        } else {
          Row({ space: 6 }) {
            SymbolGlyph($r('sys.symbol.cloud'))
              .fontSize(15)
              .fontColor([this.palette().subText])
            Text() {
              Span(`${L10n.t('quick_share_remote_link', '远程链接')}: `)
                .fontColor(this.palette().onSurface)
                .fontSize(13)
              Span(L10n.t('quick_share_remote_link_guide', '去开启远程访问，获得远程访问分享地址'))
                .fontColor(this.palette().primary)
                .fontSize(13)
                .decoration({ type: TextDecorationType.Underline, color: this.palette().primary })
            }
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
            .onClick(() => {
              this.goRemoteGuide();
            })
            this.TextAction(L10n.t('go_to', '前往'), (): void => {
              this.goRemoteGuide();
            })
          }
          .width('100%')
          .margin({ top: 6 })
          .alignItems(VerticalAlign.Center)
        }

        // 访问密码
        Row({ space: 6 }) {
          SymbolGlyph($r('sys.symbol.lock'))
            .fontSize(15)
            .fontColor([this.palette().subText])
          Text(this.pwdDisplay(item))
            .fontSize(13)
            .fontColor(this.palette().onSurface)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
          if (item.hasPwd && item.id > 0) {
            this.TextAction(this.ctrl.isPwdRevealed(item.id)
              ? L10n.t('quick_share_hide', '隐藏')
              : L10n.t('quick_share_show', '显示'), (): void => {
              this.ctrl.togglePwdReveal(item.id);
            })
          }
        }
        .width('100%')
        .margin({ top: 8 })
        .alignItems(VerticalAlign.Center)

        // 截止时间
        Row({ space: 6 }) {
          SymbolGlyph($r('sys.symbol.clock'))
            .fontSize(15)
            .fontColor([this.palette().subText])
          Text(this.endLabel(item))
            .fontSize(12)
            .fontColor(this.palette().subText)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
        }
        .width('100%')
        .margin({ top: 6 })
        .alignItems(VerticalAlign.Center)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
  }

  private remoteUrlOf(item: QuickShareItem): string {
    const v = this.ctrl.remoteUrlByToken.get(item.token);
    return v === undefined ? '' : v;
  }

  private pwdDisplay(item: QuickShareItem): string {
    const label = L10n.t('quick_share_password', '访问密码');
    if (!item.hasPwd || item.id <= 0) {
      return item.hasPwd ? `${label}: ••••` : L10n.t('quick_share_no_password', '无访问密码');
    }
    const show = this.ctrl.isPwdRevealed(item.id);
    const display = show && item.pwd.length > 0 ? item.pwd : '••••';
    return `${label}: ${display}`;
  }

  /** 截止时间（对齐 Flutter end.toLocal().toString().substring(0, 16)） */
  private endLabel(item: QuickShareItem): string {
    if (item.endTimeMs < 0) {
      return L10n.t('quick_share_end_time_none', '截止：无期限');
    }
    const d = new Date(item.endTimeMs);
    const p = (v: number): string => v < 10 ? `0${v}` : `${v}`;
    const label = L10n.t('quick_share_end_time', '截止');
    return `${label}: ${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())} ${p(d.getHours())}:${p(d.getMinutes())}`;
  }

  /** 链接文本（主色下划线，点击打开二维码弹窗） */
  @Builder
  LinkText(text: string, onTap: () => void) {
    Text(text)
      .fontSize(13)
      .fontColor(this.palette().primary)
      .decoration({ type: TextDecorationType.Underline, color: this.palette().primary })
      .maxLines(1)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
      .layoutWeight(1)
      .onClick(() => {
        onTap();
      })
  }

  /** 小号文字按钮（对齐 Flutter TextButton shrinkWrap） */
  @Builder
  TextAction(label: string, onTap: () => void) {
    Text(label)
      .fontSize(13)
      .fontColor(this.palette().primary)
      .padding({ left: 8, right: 8, top: 6, bottom: 6 })
      .onClick(() => {
        onTap();
      })
  }

  // ===== 创建分享弹窗（对齐 _QuickShareCreateDialog） =====

  @Builder
  CreateDialogOverlay() {
    Stack() {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#80000000')
        .onClick(() => {
          if (!this.cSubmitting) {
            this.showCreate = false;
          }
        })

      Column() {
        Text(L10n.t('quick_share_create', '创建分享'))
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.palette().onSurface)

        Scroll() {
          Column() {
            // 路径（只读，点击选择，对齐 CustomTextField readOnly + suffix folder icon）
            Column({ space: 4 }) {
              Text(L10n.t('path', '路径'))
                .fontSize(12)
                .fontColor(this.palette().subText)
              Row({ space: 8 }) {
                Text(this.cPath.length > 0 ? this.cPath
                  : L10n.t('quick_share_path_hint', '未选择路径'))
                  .fontSize(14)
                  .fontColor(this.cPath.length > 0 ? this.palette().onSurface : this.palette().hint)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .layoutWeight(1)
                SymbolGlyph($r('sys.symbol.folder'))
                  .fontSize(18)
                  .fontColor([this.palette().onSurface])
              }
              .width('100%')
              .padding({ left: 12, right: 12, top: 10, bottom: 10 })
              .borderRadius(8)
              .backgroundColor(this.palette().inputFill)
              .border({ width: 1, color: this.palette().inputBorder })
              .onClick(() => {
                if (!this.cSubmitting) {
                  this.pickCreatePath();
                }
              })
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)

            this.FieldLabel(L10n.t('quick_share_password', '访问密码'), 12)
            TextInput({ placeholder: L10n.t('quick_share_password_hint', '必填') })
              .type(InputType.Password)
              .fontSize(14)
              .fontColor(this.palette().onSurface)
              .placeholderColor(this.palette().hint)
              .backgroundColor(this.palette().inputFill)
              .borderRadius(8)
              .border({ width: 1, color: this.palette().inputBorder })
              .height(42)
              .width('100%')
              .enabled(!this.cSubmitting)
              .onChange((v: string) => {
                this.cPwd = v;
              })

            this.FieldLabel(L10n.t('quick_share_remark', '备注'), 12)
            TextInput({ placeholder: L10n.t('quick_share_remark_hint', '可选') })
              .fontSize(14)
              .fontColor(this.palette().onSurface)
              .placeholderColor(this.palette().hint)
              .backgroundColor(this.palette().inputFill)
              .borderRadius(8)
              .border({ width: 1, color: this.palette().inputBorder })
              .height(42)
              .width('100%')
              .enabled(!this.cSubmitting)
              .onChange((v: string) => {
                this.cRemark = v;
              })

            Row({ space: 10 }) {
              Column({ space: 4 }) {
                this.FieldLabel(L10n.t('quick_share_duration', '分享时限'), 0)
                TextInput({ placeholder: L10n.t('quick_share_duration_hint', '输入数字'),
                  text: this.cDuration })
                  .type(InputType.Number)
                  .fontSize(14)
                  .fontColor(this.palette().onSurface)
                  .placeholderColor(this.palette().hint)
                  .backgroundColor(this.palette().inputFill)
                  .borderRadius(8)
                  .border({ width: 1, color: this.palette().inputBorder })
                  .height(42)
                  .width('100%')
                  .enabled(!this.cSubmitting && !this.cNoLimit)
                  .opacity(this.cNoLimit ? 0.5 : 1)
                  .onChange((v: string) => {
                    this.cDuration = v;
                  })
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Start)

              // 单位下拉（对齐 Flutter DropdownButton）
              Column({ space: 4 }) {
                Text(' ')
                  .fontSize(12)
                Row({ space: 6 }) {
                  Text(this.unitLabel())
                    .fontSize(14)
                    .fontColor(this.palette().onSurface)
                  SymbolGlyph($r('sys.symbol.chevron_down'))
                    .fontSize(14)
                    .fontColor([this.palette().hint])
                }
                .padding({ left: 12, right: 10, top: 10, bottom: 10 })
                .borderRadius(8)
                .backgroundColor(this.palette().inputFill)
                .border({ width: 1, color: this.palette().inputBorder })
                .opacity(this.cNoLimit ? 0.5 : 1)
                .onClick(() => {
                  if (this.cSubmitting || this.cNoLimit) {
                    return;
                  }
                  const options: PickOption[] = [
                    new PickOption('day', L10n.t('quick_share_unit_day', '天')),
                    new PickOption('hour', L10n.t('quick_share_unit_hour', '小时'))
                  ];
                  showOptionPickSheet('', options, this.cUnit, (key: string): void => {
                    this.cUnit = key;
                  });
                })
              }
            }
            .width('100%')
            .margin({ top: 12 })
            .alignItems(VerticalAlign.Bottom)

            // 无期限
            Row({ space: 10 }) {
              CircleCheckbox({
                value: this.cNoLimit,
                onChanged: (checked: boolean): void => {
                  if (!this.cSubmitting) {
                    this.cNoLimit = checked;
                  }
                }
              })
              Text(L10n.t('quick_share_no_limit', '无期限'))
                .fontSize(14)
                .fontColor(this.palette().onSurface)
            }
            .width('100%')
            .margin({ top: 10 })
          }
          .width('100%')
        }
        .scrollBar(BarState.Auto)
        .width('100%')
        .align(Alignment.Top)
        .margin({ top: 14 })
        .layoutWeight(1)

        Row({ space: 8 }) {
          Button(L10n.cancel)
            .fontSize(14)
            .fontColor(this.palette().primary)
            .backgroundColor(Color.Transparent)
            .height(36)
            .enabled(!this.cSubmitting)
            .onClick(() => {
              this.showCreate = false;
            })
          Button(L10n.ok)
            .fontSize(14)
            .fontColor(this.palette().buttonText)
            .backgroundColor(this.palette().buttonBg)
            .height(36)
            .enabled(!this.cSubmitting)
            .opacity(this.cSubmitting ? 0.45 : 1)
            .onClick(() => {
              void this.submitCreate();
            })
        }
        .justifyContent(FlexAlign.End)
        .margin({ top: 12 })
        .width('100%')
      }
      .alignItems(HorizontalAlign.Start)
      .padding(20)
      .borderRadius(24)
      .backgroundColor(this.palette().surfaceBg)
      .width('86%')
      .height('70%')
      .constraintSize({ minWidth: 300, maxWidth: 560 })
    }
    .width('100%')
    .height('100%')
    .alignContent(Alignment.Center)
  }

  @Builder
  FieldLabel(label: string, topMargin: number) {
    Text(label)
      .fontSize(12)
      .fontColor(this.palette().subText)
      .margin({ top: topMargin })
  }

  // ===== 二维码弹窗（对齐 _showQrCodeDialog） =====

  @Builder
  QrDialogOverlay() {
    Stack() {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#80000000')
        .onClick(() => {
          this.qrShow = false;
        })

      Column() {
        Text(L10n.t('quick_share_qr_title', '分享链接二维码'))
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.palette().onSurface)

        Column({ space: 4 }) {
          Text(L10n.t('quick_share_link', '分享链接'))
            .fontSize(12)
            .fontColor(this.palette().subText)
          Row({ space: 8 }) {
            TextInput({ text: this.qrInput })
              .fontSize(13)
              .fontColor(this.palette().onSurface)
              .backgroundColor(this.palette().inputFill)
              .borderRadius(8)
              .border({ width: 1, color: this.palette().inputBorder })
              .height(56)
              .layoutWeight(1)
              .enabled(!this.qrIsRemote)
              .onChange((v: string) => {
                this.qrInput = v;
              })
            if (!this.qrIsRemote) {
              Text(L10n.t('quick_share_qr_generate', '生成二维码'))
                .fontSize(13)
                .fontColor(this.palette().primary)
                .padding({ left: 6, right: 6, top: 6, bottom: 6 })
                .onClick(() => {
                  this.regenerateQr();
                })
            }
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .margin({ top: 14 })

        Column() {
          QrCodeView({ text: this.qrText, viewSize: 200 })
        }
        .padding(16)
        .borderRadius(12)
        .backgroundColor('#FFFFFF')
        .margin({ top: 14 })

        Row({ space: 8 }) {
          Button(L10n.t('quick_share_copy_link', '复制链接'))
            .fontSize(14)
            .fontColor(this.palette().primary)
            .backgroundColor(Color.Transparent)
            .height(36)
            .onClick(() => {
              this.ctrl.copyText(this.qrText);
            })
          Button(L10n.ok)
            .fontSize(14)
            .fontColor(this.palette().primary)
            .backgroundColor(Color.Transparent)
            .height(36)
            .onClick(() => {
              this.qrShow = false;
            })
        }
        .justifyContent(FlexAlign.End)
        .margin({ top: 12 })
        .width('100%')
      }
      .alignItems(HorizontalAlign.Start)
      .padding(20)
      .borderRadius(24)
      .backgroundColor(this.palette().surfaceBg)
      .width('80%')
      .constraintSize({ minWidth: 300, maxWidth: 460 })
    }
    .width('100%')
    .height('100%')
    .alignContent(Alignment.Center)
  }
}
