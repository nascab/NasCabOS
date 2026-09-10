import { L10n } from '../../../../core/localization/L10n';
import { AppTheme, ThemePalette } from '../../../../core/theme/AppTheme';
import { PickOption, showOptionPickSheet } from '../../../../common/components/OptionPickSheet';

// ===== 模块内通用小组件（对齐 Flutter CustomButton / _KeyValueRow / CustomTextField 等模式） =====

/**
 * 文字+图标按钮（对齐 Flutter CustomButton）：
 * primary=true 为主色实底按钮，否则描边次要按钮；disabled 置灰；loading 显示转圈并禁点。
 */
@ComponentV2
export struct MediaToolTextButton {
  @Param label: string = '';
  @Param icon: Resource | undefined = undefined;
  @Param primary: boolean = false;
  @Param disabled: boolean = false;
  @Param loading: boolean = false;
  @Param onTap: () => void = (): void => {
  };

  private palette(): ThemePalette {
    return AppTheme.current();
  }

  private fg(): string {
    return this.primary ? '#FFFFFF' : this.palette().primary;
  }

  build() {
    Row({ space: 6 }) {
      if (this.loading) {
        LoadingProgress()
          .width(15)
          .height(15)
          .color(this.fg())
      } else if (this.icon !== undefined) {
        SymbolGlyph(this.icon)
          .fontSize(15)
          .fontColor([this.fg()])
      }
      Text(this.label)
        .fontSize(13)
        .fontWeight(this.primary ? FontWeight.Medium : FontWeight.Normal)
        .fontColor(this.fg())
        .maxLines(1)
    }
    .padding({ left: 12, right: 12, top: 8, bottom: 8 })
    .borderRadius(10)
    .backgroundColor(this.primary ? this.palette().primary : this.palette().surfaceBg)
    .border({
      width: 1,
      color: this.primary ? this.palette().primary : this.palette().divider
    })
    .opacity(this.disabled && !this.loading ? 0.45 : 1)
    .onClick(() => {
      if (!this.disabled && !this.loading) {
        this.onTap();
      }
    })
  }
}

/** 任务卡片启停按钮（对齐 Flutter 卡片内 CustomButton：运行中显示"停止"，否则"开始"） */
@ComponentV2
export struct MediaToolStartStopButton {
  /** true=运行中（点击为停止），false=已停止（点击为开始） */
  @Param running: boolean = false;
  @Param startLabel: string = L10n.t('file_backup_start', '开始');
  @Param stopLabel: string = L10n.t('file_backup_stop', '停止');
  @Param loading: boolean = false;
  @Param onTap: () => void = (): void => {
  };

  build() {
    MediaToolTextButton({
      label: this.running ? this.stopLabel : this.startLabel,
      icon: this.running ? $r('sys.symbol.stop_circle') : $r('sys.symbol.play_circle'),
      primary: true,
      disabled: this.loading,
      loading: this.loading,
      onTap: (): void => {
        this.onTap();
      }
    })
  }
}

/**
 * 键值行（对齐 Flutter _KeyValueRow）：label 固定 110 宽，value 支持错误色/点击查看详情。
 */
@ComponentV2
export struct MediaToolKeyValueRow {
  @Param label: string = '';
  @Param value: string = '';
  /** value 颜色：'normal' | 'error' */
  @Param valueTone: string = 'normal';
  @Param lineLimit: number = 99;
  @Param onTap: () => void = (): void => {
  };
  /** 是否可点击（决定 value 是否截断为单行，对齐 Flutter maxLines/overflow 传参） */
  @Param clickable: boolean = false;

  private palette(): ThemePalette {
    return AppTheme.current();
  }

  build() {
    Row() {
      Text(this.label)
        .fontSize(12)
        .fontColor(this.palette().subText)
        .width(110)
      Text(this.value.trim().length === 0 ? '-' : this.value)
        .fontSize(12)
        .fontColor(this.valueTone === 'error' ? this.palette().error : this.palette().onSurface)
        .fontWeight(this.valueTone === 'error' ? FontWeight.Medium : FontWeight.Normal)
        .maxLines(this.clickable ? 1 : this.lineLimit)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
        .onClick(() => {
          if (this.clickable) {
            this.onTap();
          }
        })
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
  }
}

/** 路径行（对齐 Flutter pathRow）：label + [查看] 链接 + 路径文本，点击 [查看] 回调 */
@ComponentV2
export struct MediaToolPathRow {
  @Param label: string = '';
  @Param path: string = '';
  @Param onView: () => void = (): void => {
  };

  private palette(): ThemePalette {
    return AppTheme.current();
  }

  build() {
    Row() {
      Text(this.label)
        .fontSize(12)
        .fontColor(this.palette().subText)
        .width(110)
      if (this.path.trim().length > 0) {
        Text(`[${L10n.t('perm_view', '查看')}]`)
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.palette().primary)
          .onClick(() => {
            this.onView();
          })
      }
      Text(this.path.trim().length === 0 ? '-' : this.path.trim())
        .fontSize(12)
        .fontColor(this.palette().onSurface)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
        .margin({ left: this.path.trim().length > 0 ? 8 : 0 })
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
  }
}

/** 表单字段标题（对齐 CustomTextField labelText / Dialog 内 Text label） */
@ComponentV2
export struct MediaToolFieldLabel {
  @Param label: string = '';
  @Param tone: string = 'normal';

  private palette(): ThemePalette {
    return AppTheme.current();
  }

  build() {
    Text(this.label)
      .fontSize(13)
      .fontColor(this.tone === 'sub' ? this.palette().subText : this.palette().onSurface)
      .width('100%')
  }
}

/**
 * 路径选择字段（对齐 Flutter readOnly CustomTextField + suffixIcon + onTap）：
 * 只读行，点击触发选择回调；disabled 时置灰不可点。
 */
@ComponentV2
export struct MediaToolPickField {
  @Param label: string = '';
  @Param value: string = '';
  @Param hint: string = '';
  @Param icon: Resource = $r('sys.symbol.folder');
  @Param disabled: boolean = false;
  @Param onTap: () => void = (): void => {
  };

  private palette(): ThemePalette {
    return AppTheme.current();
  }

  build() {
    Column({ space: 6 }) {
      MediaToolFieldLabel({ label: this.label })
      Row({ space: 8 }) {
        Text(this.value.trim().length > 0 ? this.value : this.hint)
          .fontSize(13)
          .fontColor(this.value.trim().length > 0 ? this.palette().onSurface : this.palette().hint)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        SymbolGlyph(this.icon)
          .fontSize(16)
          .fontColor([this.palette().hint])
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 11, bottom: 11 })
      .borderRadius(10)
      .border({ width: 1, color: this.palette().divider })
      .opacity(this.disabled ? 0.5 : 1)
      .onClick(() => {
        if (!this.disabled) {
          this.onTap();
        }
      })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}

/**
 * 下拉选择字段（对齐 Flutter CustomDropdownField）：点击弹出底部选项列表。
 * options 为 key/label 列表；disabled 置灰不可点。
 */
@ComponentV2
export struct MediaToolSelectField {
  @Param label: string = '';
  @Param options: PickOption[] = [];
  @Param value: string = '';
  @Param disabled: boolean = false;
  /** 选中变化回调（key） */
  @Param onChanged: (key: string) => void = (_k: string): void => {
  };

  private palette(): ThemePalette {
    return AppTheme.current();
  }

  private currentLabel(): string {
    for (const opt of this.options) {
      if (opt.key === this.value) {
        return opt.label;
      }
    }
    return this.value;
  }

  build() {
    Column({ space: 6 }) {
      MediaToolFieldLabel({ label: this.label })
      Row({ space: 8 }) {
        Text(this.currentLabel())
          .fontSize(13)
          .fontColor(this.palette().onSurface)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        SymbolGlyph($r('sys.symbol.chevron_down'))
          .fontSize(14)
          .fontColor([this.palette().hint])
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 11, bottom: 11 })
      .borderRadius(10)
      .border({ width: 1, color: this.palette().divider })
      .opacity(this.disabled ? 0.5 : 1)
      .onClick(() => {
        if (this.disabled || this.options.length === 0) {
          return;
        }
        showOptionPickSheet(this.label, this.options, this.value, (key: string): void => {
          this.onChanged(key);
        });
      })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}

/** 数字输入字段（对齐 Flutter CustomTextField keyboardType: number） */
@ComponentV2
export struct MediaToolNumberField {
  @Param label: string = '';
  @Param hint: string = '';
  @Param value: string = '';
  @Param disabled: boolean = false;
  @Param onChanged: (text: string) => void = (_t: string): void => {
  };

  private palette(): ThemePalette {
    return AppTheme.current();
  }

  build() {
    Column({ space: 6 }) {
      if (this.label.length > 0) {
        MediaToolFieldLabel({ label: this.label })
      }
      TextInput({ text: this.value, placeholder: this.hint })
        .type(InputType.Number)
        .fontSize(13)
        .fontColor(this.palette().onSurface)
        .placeholderColor(this.palette().hint)
        .placeholderFont({ size: 13 })
        .backgroundColor(Color.Transparent)
        .border({ width: 1, color: this.palette().divider })
        .borderRadius(10)
        .padding({ left: 12, right: 12, top: 8, bottom: 8 })
        .width('100%')
        .height(42)
        .enabled(!this.disabled)
        .onChange((text: string) => {
          this.onChanged(text);
        })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}

/** 开关行（对齐 Flutter Row + CustomSwitch） */
@ComponentV2
export struct MediaToolSwitchRow {
  @Param label: string = '';
  @Param value: boolean = false;
  @Param disabled: boolean = false;
  @Param onChanged: (v: boolean) => void = (_v: boolean): void => {
  };

  private palette(): ThemePalette {
    return AppTheme.current();
  }

  build() {
    Row() {
      Text(this.label)
        .fontSize(13)
        .fontColor(this.palette().onSurface)
        .layoutWeight(1)
      Toggle({ type: ToggleType.Switch, isOn: this.value })
        .selectedColor(this.palette().primary)
        .enabled(!this.disabled)
        .onChange((on: boolean) => {
          this.onChanged(on);
        })
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }
}

/**
 * 模块内通用编辑弹窗外壳（对齐 Flutter DialogUtil.createAlertDialog + actions）：
 * 全屏遮罩 + 居中卡片 + 标题 + 可滚动内容 + 取消/确认按钮。
 * onConfirm 返回 true 时自动关闭（成功），false 保持打开。
 */
@ComponentV2
export struct MediaToolDialogShell {
  @Param title: string = '';
  @Param saving: boolean = false;
  @Param confirmText: string = L10n.confirm;
  @Param onConfirm: () => Promise<boolean> = (): Promise<boolean> => Promise.resolve(false);
  @Param onDismiss: () => void = (): void => {
  };
  @BuilderParam content: () => void;

  private palette(): ThemePalette {
    return AppTheme.current();
  }

  private async handleConfirm(): Promise<void> {
    if (this.saving) {
      return;
    }
    const ok = await this.onConfirm();
    if (ok) {
      this.onDismiss();
    }
  }

  build() {
    Stack() {
      // 遮罩（提交中禁止关闭，对齐 Flutter WillPopScope）
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#80000000')
        .onClick(() => {
          if (!this.saving) {
            this.onDismiss();
          }
        })

      Column() {
        Text(this.title)
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.palette().onSurface)
          .width('100%')

        Scroll() {
          Column() {
            this.content()
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
            .layoutWeight(1)
            .enabled(!this.saving)
            .onClick(() => {
              if (!this.saving) {
                this.onDismiss();
              }
            })
          Button(this.confirmText)
            .fontSize(14)
            .fontColor('#FFFFFF')
            .backgroundColor(this.palette().primary)
            .height(36)
            .layoutWeight(1)
            .opacity(this.saving ? 0.5 : 1)
            .onClick(() => {
              void this.handleConfirm();
            })
        }
        .width('100%')
        .margin({ top: 16 })
      }
      .width('92%')
      .constraintSize({ maxHeight: '85%' })
      .padding(16)
      .borderRadius(16)
      .backgroundColor(this.palette().surfaceBg)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height('100%')
    .alignContent(Alignment.Center)
  }
}

/** 弹窗内分隔间距（对齐 Flutter SizedBox(height: 12)） */
@ComponentV2
export struct MediaToolGap {
  @Param gapHeight: number = 12;

  build() {
    Column()
      .width('100%')
      .height(this.gapHeight)
  }
}
