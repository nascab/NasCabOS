import { L10n } from '../../../core/localization/L10n';
import { AppTheme } from '../../../core/theme/AppTheme';
import { DialogUtil } from '../../../common/DialogUtil';
import { GlassCard } from '../../../common/components/GlassCard';
import { EmptyState } from '../../../common/components/EmptyState';
import { DockerController } from '../controllers/DockerController';
import { DockerContainer, DockerMountInfo, DockerPortBinding } from '../models/DockerModels';
import {
  DockerActionButton, DockerContainerBadge, DockerInfoTag, DockerSectionHeader
} from './parts/DockerSharedWidgets';
import { showDockerCreateContainerDialog, showDockerLogsDialog } from '../components/DockerDialogs';

/** 状态筛选项 */
class DockerFilterChip {
  key: string;
  label: string;

  constructor(key: string, label: string) {
    this.key = key;
    this.label = label;
  }
}

/**
 * Docker 容器页签（对齐 Flutter _ContainersTab 移动端形态）：
 * 区块标题 + 刷新/创建操作，状态筛选 chips，容器卡片含状态徽标/端口/挂载与操作按钮。
 */
@ComponentV2
export struct DockerContainersTab {
  @Param ctrl: DockerController = new DockerController();

  private filters(): DockerFilterChip[] {
    return [
      new DockerFilterChip('', L10n.t('docker_filter_all', '全部')),
      new DockerFilterChip('running', L10n.t('docker_filter_running', '运行中')),
      new DockerFilterChip('exited', L10n.t('docker_filter_exited', '已停止'))
    ];
  }

  private async confirmDelete(item: DockerContainer): Promise<void> {
    await DialogUtil.showConfirmDialog(
      L10n.t('need_confirm', '需要确认'),
      L10n.t('docker_delete_container_confirm', '确认删除该容器吗？将使用强制删除。'),
      (): void => {
        void this.ctrl.deleteContainer(item.id, true);
      },
      L10n.t('delete', '删除'), L10n.t('cancel', '取消'));
  }

  @Builder
  FilterChip(item: DockerFilterChip) {
    Text(item.label)
      .fontSize(12)
      .fontWeight(FontWeight.Medium)
      .fontColor(this.ctrl.containerStatusFilter === item.key
        ? AppTheme.current().primary : AppTheme.current().subText)
      .padding({ left: 12, right: 12, top: 6, bottom: 6 })
      .backgroundColor(this.ctrl.containerStatusFilter === item.key
        ? AppTheme.withAlpha(AppTheme.current().primary, 0.12) : AppTheme.current().inputFill)
      .borderRadius(999)
      .border({
        width: 1,
        color: this.ctrl.containerStatusFilter === item.key
          ? AppTheme.current().primary : AppTheme.current().divider
      })
      .margin({ right: 8 })
      .onClick((): void => {
        if (this.ctrl.containerStatusFilter !== item.key) {
          this.ctrl.containerStatusFilter = item.key;
          void this.ctrl.refreshContainers(false);
        }
      })
  }

  @Builder
  ContainerCard(item: DockerContainer) {
    GlassCard({ padValue: 16, cornerRadius: 16 }) {
      Column() {
        DockerContainerBadge({ text: item.badgeText(), isRunning: item.isRunning() })
        Text(item.name.length > 0 ? item.name : '--')
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppTheme.current().onSurface)
          .copyOption(CopyOptions.InApp)
          .margin({ top: 10 })
          .width('100%')
        Text(item.image.length > 0 ? item.image : '--')
          .fontSize(13)
          .fontColor(AppTheme.current().subText)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ top: 6 })
          .width('100%')
        Text(item.id.length > 0 ? item.id : '--')
          .fontSize(11)
          .fontColor(AppTheme.current().subText)
          .copyOption(CopyOptions.InApp)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ top: 6 })
          .width('100%')
        if (item.ports.length > 0) {
          Text(L10n.t('docker_ports', '端口映射'))
            .fontSize(12)
            .fontWeight(FontWeight.Bold)
            .fontColor(AppTheme.current().onSurface)
            .margin({ top: 14 })
            .width('100%')
          Flex({ wrap: FlexWrap.Wrap, alignItems: ItemAlign.Start }) {
            ForEach(item.ports, (port: DockerPortBinding): void => {
              DockerInfoTag({ text: port.displayText() })
            }, (port: DockerPortBinding, idx: number): string => `${idx}_${port.displayText()}`)
          }
          .margin({ top: 6 })
          .width('100%')
        }
        if (item.mounts.length > 0) {
          Text(L10n.t('docker_mounts', '卷挂载'))
            .fontSize(12)
            .fontWeight(FontWeight.Bold)
            .fontColor(AppTheme.current().onSurface)
            .margin({ top: 12 })
            .width('100%')
          Flex({ wrap: FlexWrap.Wrap, alignItems: ItemAlign.Start }) {
            ForEach(item.mounts, (mount: DockerMountInfo): void => {
              DockerInfoTag({
                text: `${mount.source} -> ${mount.target}${mount.readOnly ? ' (ro)' : ''}`
              })
            }, (mount: DockerMountInfo, idx: number): string => `${idx}_${mount.source}_${mount.target}`)
          }
          .margin({ top: 6 })
          .width('100%')
        }
        Flex({ wrap: FlexWrap.Wrap }) {
          Column() {
            DockerActionButton({
              label: item.isRunning() ? L10n.t('docker_stop', '停止') : L10n.t('docker_start', '启动'),
              icon: item.isRunning() ? $r('sys.symbol.pause_circle') : $r('sys.symbol.play_circle'),
              kind: 'primary',
              onTap: (): void => {
                if (item.isRunning()) {
                  void this.ctrl.stopContainer(item.id);
                } else {
                  void this.ctrl.startContainer(item.id);
                }
              }
            })
          }
          .margin({ right: 8, bottom: 8 })
          Column() {
            DockerActionButton({
              label: L10n.t('docker_view_logs', '日志'),
              icon: $r('sys.symbol.doc_text'),
              onTap: (): void => {
                showDockerLogsDialog(this.ctrl, item);
              }
            })
          }
          .margin({ right: 8, bottom: 8 })
          Column() {
            DockerActionButton({
              label: L10n.t('delete', '删除'),
              kind: 'danger',
              onTap: (): void => {
                void this.confirmDelete(item);
              }
            })
          }
          .margin({ bottom: 8 })
        }
        .margin({ top: 14 })
        .width('100%')
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
  }

  build() {
    Scroll() {
      Column() {
        DockerSectionHeader({
          title: L10n.t('docker_tab_containers', '容器'),
          subtitle: L10n.t('docker_containers_subtitle', '查看容器状态、端口、挂载并执行常用操作')
        }) {
          Row({ space: 8 }) {
            DockerActionButton({
              label: L10n.t('refresh', '刷新'),
              icon: $r('sys.symbol.arrow_clockwise'),
              onTap: (): void => {
                void this.ctrl.refreshContainers(false);
              }
            })
            DockerActionButton({
              label: L10n.t('docker_create_container', '创建容器'),
              icon: $r('sys.symbol.plus_square_on_square'),
              kind: 'primary',
              onTap: (): void => {
                showDockerCreateContainerDialog(this.ctrl);
              }
            })
          }
        }
        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(this.filters(), (item: DockerFilterChip): void => {
            this.FilterChip(item)
          }, (item: DockerFilterChip): string => item.key)
        }
        .margin({ top: 12 })
        .width('100%')
        if (this.ctrl.containers.length === 0) {
          Column() {
            GlassCard({ padValue: 20, cornerRadius: 16 }) {
              Column() {
                EmptyState()
              }
              .width('100%')
            }
          }
          .margin({ top: 12 })
          .width('100%')
        } else {
          ForEach(this.ctrl.containers, (item: DockerContainer): void => {
            Column() {
              this.ContainerCard(item)
            }
            .margin({ top: 12 })
            .width('100%')
          }, (item: DockerContainer, idx: number): string => `${idx}_${item.id}`)
        }
      }
      .width('100%')
      .padding({ left: 12, right: 12, bottom: 12 })
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Auto)
    .align(Alignment.Top)
  }
}
