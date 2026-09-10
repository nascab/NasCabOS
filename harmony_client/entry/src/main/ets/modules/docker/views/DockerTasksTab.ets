import { L10n } from '../../../core/localization/L10n';
import { AppTheme } from '../../../core/theme/AppTheme';
import { GlassCard } from '../../../common/components/GlassCard';
import { EmptyState } from '../../../common/components/EmptyState';
import { DockerController } from '../controllers/DockerController';
import { DockerTask, translateTaskType } from '../models/DockerModels';
import { DockerActionButton, DockerSectionHeader, DockerStatusBadge } from './parts/DockerSharedWidgets';
import { showDockerTaskLogsSheet } from '../components/DockerDialogs';

/**
 * Docker 任务页签（对齐 Flutter _TasksTab 移动端形态）：
 * 区块标题 + 刷新，任务卡片含状态徽标/类型/进度条与操作按钮，
 * 点击卡片选中任务，日志按钮拉取日志并弹出实时日志弹层。
 */
@ComponentV2
export struct DockerTasksTab {
  @Param ctrl: DockerController = new DockerController();

  private async openLogs(taskId: string): Promise<void> {
    await this.ctrl.openTaskLogs(taskId, false, true);
    showDockerTaskLogsSheet(this.ctrl);
  }

  @Builder
  TaskCard(item: DockerTask) {
    GlassCard({
      padValue: 16,
      cornerRadius: 16,
      onCardTap: (): void => {
        this.ctrl.selectTask(item.id, true);
      }
    }) {
      Column() {
        Row() {
          Text(item.title.length > 0 ? item.title : '--')
            .fontSize(15)
            .fontWeight(FontWeight.Bold)
            .fontColor(AppTheme.current().onSurface)
            .layoutWeight(1)
          DockerStatusBadge({ status: item.status })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
        Text(translateTaskType(item.type))
          .fontSize(12)
          .fontColor(AppTheme.current().subText)
          .margin({ top: 8 })
          .width('100%')
        if (item.progress !== undefined) {
          Progress({
            value: Math.min(Math.max(item.progress, 0), 100),
            total: 100,
            type: ProgressType.Linear
          })
            .color(AppTheme.current().primary)
            .width('100%')
            .margin({ top: 10 })
        }
        Flex({ wrap: FlexWrap.Wrap }) {
          Column() {
            DockerActionButton({
              label: L10n.t('docker_view_logs', '日志'),
              onTap: (): void => {
                void this.openLogs(item.id);
              }
            })
          }
          .margin({ right: 8, bottom: 8 })
          if (item.command.length > 0) {
            Column() {
              DockerActionButton({
                label: L10n.t('docker_copy_command', '复制命令'),
                onTap: (): void => {
                  void this.ctrl.copyCommand(item.command);
                }
              })
            }
            .margin({ right: 8, bottom: 8 })
          }
          if (item.canCancel()) {
            Column() {
              DockerActionButton({
                label: item.status === 'running'
                  ? L10n.t('docker_stop', '停止') : L10n.t('cancel', '取消'),
                onTap: (): void => {
                  void this.ctrl.cancelTask(item.id);
                }
              })
            }
            .margin({ right: 8, bottom: 8 })
          }
          if (!item.canCancel()) {
            Column() {
              DockerActionButton({
                label: L10n.t('delete', '删除'),
                onTap: (): void => {
                  void this.ctrl.deleteTask(item.id);
                }
              })
            }
            .margin({ bottom: 8 })
          }
        }
        .margin({ top: 10 })
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
          title: L10n.t('docker_tab_tasks', '任务'),
          subtitle: L10n.t('docker_tasks_subtitle', '查看耗时任务进度、命令行与实时输出')
        }) {
          Row({ space: 8 }) {
            DockerActionButton({
              label: L10n.t('refresh', '刷新'),
              icon: $r('sys.symbol.arrow_clockwise'),
              onTap: (): void => {
                void this.ctrl.refreshTasks(false);
              }
            })
          }
        }
        if (this.ctrl.tasks.length === 0) {
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
          ForEach(this.ctrl.tasks, (item: DockerTask): void => {
            Column() {
              this.TaskCard(item)
            }
            .margin({ top: 12 })
            .width('100%')
          }, (item: DockerTask, idx: number): string => `${idx}_${item.id}_${item.status}_${item.progress ?? ''}`)
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
