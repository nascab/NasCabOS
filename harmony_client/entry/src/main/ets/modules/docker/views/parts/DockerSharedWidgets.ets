import pasteboard from '@ohos.pasteboard';
import { L10n } from '../../../../core/localization/L10n';
import { AppTheme } from '../../../../core/theme/AppTheme';
import { ToastUtil } from '../../../../common/ToastUtil';
import { DockerController } from '../../controllers/DockerController';
import { DockerTaskLog, translateTaskStatus } from '../../models/DockerModels';

@Builder
function DockerSectionActionsEmpty() {
}

/**
 * Docker 模块共享小部件（对齐 Flutter docker_shared_widgets.dart）：
 * 按钮键值行/信息标签/状态徽标/区块标题/错误横幅，以及任务日志面板（桌面右栏与移动端弹层共用）。
 */

/** 区块标题（对齐 Flutter _SectionHeader 移动端紧凑形态） */
@ComponentV2
export struct DockerSectionHeader {
  @Param title: string = '';
  @Param subtitle: string = '';
  @BuilderParam actions: () => void = DockerSectionActionsEmpty;

  build() {
    Column() {
      Text(this.title)
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppTheme.current().onSurface)
        .width('100%')
      if (this.subtitle.length > 0) {
        Text(this.subtitle)
          .fontSize(13)
          .fontColor(AppTheme.current().subText)
          .margin({ top: 4 })
          .width('100%')
      }
      Flex({ wrap: FlexWrap.Wrap, alignItems: ItemAlign.Center }) {
        this.actions()
      }
      .margin({ top: 12 })
      .width('100%')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}

/** 文字操作按钮（对齐 Flutter CustomButton：primary/普通/危险三种形态） */
@ComponentV2
export struct DockerActionButton {
  @Param label: string = '';
  @Param icon: Resource | undefined = undefined;
  /** primary | normal | danger */
  @Param kind: string = 'normal';
  @Param isEnabled: boolean = true;
  @Param onTap: () => void = (): void => {
  };

  private bg(): string {
    if (this.kind === 'primary') {
      return AppTheme.current().buttonBg;
    }
    if (this.kind === 'danger') {
      return AppTheme.current().error;
    }
    return '#00000000';
  }

  private fg(): string {
    if (this.kind === 'primary') {
      return AppTheme.current().buttonText;
    }
    if (this.kind === 'danger') {
      return '#FFFFFF';
    }
    return AppTheme.current().onSurface;
  }

  build() {
    Row({ space: 6 }) {
      if (this.icon !== undefined) {
        SymbolGlyph(this.icon!)
          .fontSize(16)
          .fontColor([this.fg()])
      }
      Text(this.label)
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.fg())
        .maxLines(1)
    }
    .height(36)
    .padding({ left: 14, right: 14 })
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
    .backgroundColor(this.bg())
    .borderRadius(10)
    .border({ width: this.kind === 'normal' ? 1 : 0, color: AppTheme.current().divider })
    .opacity(this.isEnabled ? 1 : 0.45)
    .onClick((): void => {
      if (this.isEnabled) {
        this.onTap();
      }
    })
  }
}

/** 键值行（对齐 Flutter _KvRow） */
@ComponentV2
export struct DockerKvRow {
  @Param label: string = '';
  @Param value: string = '';

  build() {
    Row() {
      Text(this.label)
        .fontSize(13)
        .fontColor(AppTheme.current().subText)
        .width(110)
      Text(this.value)
        .fontSize(13)
        .fontColor(AppTheme.current().onSurface)
        .copyOption(CopyOptions.InApp)
        .layoutWeight(1)
    }
    .alignItems(VerticalAlign.Top)
    .width('100%')
    .margin({ bottom: 8 })
  }
}

/** 元信息行（对齐 Flutter _MetaLine） */
@ComponentV2
export struct DockerMetaLine {
  @Param label: string = '';
  @Param value: string = '';

  build() {
    Row() {
      Text(`${this.label}: `)
        .fontSize(12)
        .fontColor(AppTheme.current().subText)
      Text(this.value)
        .fontSize(12)
        .fontColor(AppTheme.current().onSurface)
        .layoutWeight(1)
    }
    .alignItems(VerticalAlign.Top)
    .width('100%')
    .margin({ bottom: 6 })
  }
}

/** 信息标签（对齐 Flutter _ContainerInfoTag 圆角胶囊） */
@ComponentV2
export struct DockerInfoTag {
  @Param text: string = '';

  build() {
    Text(this.text)
      .fontSize(11)
      .fontWeight(FontWeight.Medium)
      .fontColor(AppTheme.current().onSurface)
      .padding({ left: 10, right: 10, top: 6, bottom: 6 })
      .backgroundColor(AppTheme.current().inputFill)
      .borderRadius(999)
      .border({
        width: 1,
        color: AppTheme.withAlpha(AppTheme.current().onSurface, 0.2)
      })
      .margin({ right: 8, bottom: 8 })
  }
}

/** 任务状态徽标（对齐 Flutter _StatusBadge） */
@ComponentV2
export struct DockerStatusBadge {
  @Param status: string = '';

  private isPositive(): boolean {
    const normalized = this.status.trim().toLowerCase();
    return normalized === 'running' || normalized === 'success';
  }

  build() {
    Text(translateTaskStatus(this.status))
      .fontSize(12)
      .fontWeight(FontWeight.Bold)
      .fontColor(this.isPositive() ? '#388E3C' : AppTheme.current().onSurface)
      .padding({ left: 10, right: 10, top: 6, bottom: 6 })
      .backgroundColor(this.isPositive() ? '#1A4CAF50' : AppTheme.current().inputFill)
      .borderRadius(999)
  }
}

/** 容器状态徽标（对齐 Flutter _ContainerCard statusBadge） */
@ComponentV2
export struct DockerContainerBadge {
  @Param text: string = '';
  @Param isRunning: boolean = false;

  build() {
    Text(this.text)
      .fontSize(12)
      .fontWeight(FontWeight.Bold)
      .fontColor(this.isRunning ? '#388E3C' : AppTheme.current().onSurface)
      .padding({ left: 10, right: 10, top: 6, bottom: 6 })
      .backgroundColor(this.isRunning ? '#1A4CAF50' : AppTheme.current().inputFill)
      .borderRadius(999)
  }
}

/** 错误横幅（对齐 Flutter _ErrorBanner） */
@ComponentV2
export struct DockerErrorBanner {
  @Param text: string = '';

  build() {
    Row({ space: 8 }) {
      SymbolGlyph($r('sys.symbol.exclamationmark_circle'))
        .fontSize(20)
        .fontColor(['#FFFFFF'])
      Text(this.text)
        .fontSize(13)
        .fontColor('#FFFFFF')
        .layoutWeight(1)
    }
    .width('100%')
    .padding(12)
    .backgroundColor(AppTheme.current().error)
    .borderRadius(12)
  }
}

/** 编辑标签（创建容器对话框端口/挂载/环境变量条目，对齐 Flutter _CreateEditorTag） */
@ComponentV2
export struct DockerEditorTag {
  @Param label: string = '';
  @Param onTap: () => void = (): void => {
  };
  @Param onDelete: () => void = (): void => {
  };

  build() {
    Row({ space: 8 }) {
      Text(this.label)
        .fontSize(12)
        .fontWeight(FontWeight.Medium)
        .fontColor(AppTheme.current().onSurface)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .constraintSize({ maxWidth: 190 })
      SymbolGlyph($r('sys.symbol.square_and_pencil'))
        .fontSize(14)
        .fontColor([AppTheme.current().subText])
      SymbolGlyph($r('sys.symbol.minus_circle'))
        .fontSize(14)
        .fontColor([AppTheme.current().subText])
        .onClick((): void => {
          this.onDelete();
        })
    }
    .padding({ left: 12, right: 10, top: 10, bottom: 10 })
    .backgroundColor(AppTheme.current().inputFill)
    .borderRadius(14)
    .border({
      width: 1,
      color: AppTheme.withAlpha(AppTheme.current().onSurface, 0.2)
    })
    .onClick((): void => {
      this.onTap();
    })
    .margin({ right: 8, bottom: 8 })
  }
}

/** 新增标签（对齐 Flutter _CreateAddTag） */
@ComponentV2
export struct DockerAddTag {
  @Param label: string = '';
  @Param onTap: () => void = (): void => {
  };

  build() {
    Row({ space: 6 }) {
      SymbolGlyph($r('sys.symbol.plus'))
        .fontSize(14)
        .fontColor(['#FFFFFF'])
      Text(this.label)
        .fontSize(12)
        .fontWeight(FontWeight.Medium)
        .fontColor('#FFFFFF')
        .maxLines(1)
    }
    .padding({ left: 14, right: 14, top: 12, bottom: 12 })
    .backgroundColor(AppTheme.current().primary)
    .borderRadius(14)
    .onClick((): void => {
      this.onTap();
    })
    .margin({ bottom: 8 })
  }
}

/** 基础/高级模式切换（对齐 Flutter _CreateModeToggle） */
@ComponentV2
export struct DockerModeToggle {
  @Param advanced: boolean = false;
  @Param onChanged: (advanced: boolean) => void = (_v: boolean): void => {
  };

  build() {
    Row({ space: 8 }) {
      this.Option($r('sys.symbol.bolt'), L10n.t('docker_basic_mode', '基础模式'), !this.advanced, false)
      this.Option($r('sys.symbol.slider_horizontal_2'), L10n.t('docker_advanced_mode', '高级模式'),
        this.advanced, true)
    }
    .width('100%')
    .padding(4)
    .backgroundColor(AppTheme.current().inputFill)
    .borderRadius(14)
    .border({ width: 1, color: AppTheme.current().divider })
  }

  @Builder
  Option(icon: Resource, label: string, selected: boolean, value: boolean) {
    Row({ space: 8 }) {
      SymbolGlyph(icon)
        .fontSize(16)
        .fontColor([selected ? '#FFFFFF' : AppTheme.current().subText])
      Text(label)
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor(selected ? '#FFFFFF' : AppTheme.current().onSurface)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .layoutWeight(1)
    .height(40)
    .justifyContent(FlexAlign.Center)
    .backgroundColor(selected ? AppTheme.current().primary : '#00000000')
    .borderRadius(10)
    .onClick((): void => {
      this.onChanged(value);
    })
  }
}

/**
 * 任务日志面板（对齐 Flutter _TaskLogsPanel）：
 * 展示选中任务标题/命令与实时日志行，移动端放底部弹层内。
 */
@ComponentV2
export struct DockerTaskLogsPanel {
  @Param ctrl: DockerController = new DockerController();

  private currentTask(): DockerTaskLogSource | undefined {
    const taskId = this.ctrl.selectedTaskId.trim();
    if (taskId.length === 0) {
      return undefined;
    }
    for (let i = 0; i < this.ctrl.tasks.length; i++) {
      if (this.ctrl.tasks[i].id === taskId) {
        const t = this.ctrl.tasks[i];
        return new DockerTaskLogSource(t.id, t.title, t.command);
      }
    }
    return undefined;
  }

  private logsText(): string {
    const lines: string[] = [];
    this.ctrl.taskLogs.forEach((item: DockerTaskLog): void => {
      lines.push(item.formatLine());
    });
    return lines.join('\n');
  }

  private async copyLogs(): Promise<void> {
    const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, this.logsText());
    pasteboard.getSystemPasteboard().setPasteData(data);
    ToastUtil.show(L10n.t('docker_logs_copied', '日志已复制'));
  }

  build() {
    Column() {
      if (this.currentTask() === undefined) {
        Column() {
          Text(L10n.t('docker_select_task_hint', '请选择一个任务查看日志输出'))
            .fontSize(13)
            .fontColor(AppTheme.current().hint)
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        Text(this.currentTask()!.title)
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppTheme.current().onSurface)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        Text(this.currentTask()!.command)
          .fontSize(11)
          .fontColor(AppTheme.current().subText)
          .copyOption(CopyOptions.InApp)
          .maxLines(3)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ top: 6 })
          .width('100%')
        Row() {
          Text(L10n.t('docker_view_logs', '日志'))
            .fontSize(13)
            .fontWeight(FontWeight.Bold)
            .fontColor(AppTheme.current().onSurface)
          Blank()
          if (this.logsText().trim().length > 0) {
            Text(L10n.t('copy', '复制'))
              .fontSize(13)
              .fontColor(AppTheme.current().primary)
              .onClick((): void => {
                void this.copyLogs();
              })
          }
        }
        .width('100%')
        .margin({ top: 12 })
        Column() {
          if (this.ctrl.taskLogs.length === 0) {
            Text(L10n.t('no_data', '暂无数据'))
              .fontSize(13)
              .fontColor(AppTheme.current().hint)
          } else {
            List({ space: 0 }) {
              ForEach(this.ctrl.taskLogs, (item: DockerTaskLog): void => {
                ListItem() {
                  Text(item.formatLine())
                    .fontSize(11)
                    .fontColor(AppTheme.current().onSurface)
                    .copyOption(CopyOptions.InApp)
                    .width('100%')
                    .padding({ bottom: 8 })
                }
              }, (item: DockerTaskLog, idx: number): string => `${idx}_${item.ts}_${item.text}`)
            }
            .width('100%')
            .height('100%')
            .scrollBar(BarState.Auto)
          }
        }
        .width('100%')
        .layoutWeight(1)
        .margin({ top: 8 })
        .padding(12)
        .backgroundColor(AppTheme.current().inputFill)
        .borderRadius(12)
      }
    }
    .width('100%')
    .height('100%')
  }
}

/** 面板内展示用的任务摘要（避免直接持有 @Trace 对象做 @Param 比较） */
export class DockerTaskLogSource {
  id: string;
  title: string;
  command: string;

  constructor(id: string, title: string, command: string) {
    this.id = id;
    this.title = title;
    this.command = command;
  }
}
