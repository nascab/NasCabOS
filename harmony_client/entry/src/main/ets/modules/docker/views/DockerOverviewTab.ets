import { L10n } from '../../../core/localization/L10n';
import { AppTheme } from '../../../core/theme/AppTheme';
import { GlassCard } from '../../../common/components/GlassCard';
import { DockerController } from '../controllers/DockerController';
import { dockerStr } from '../models/DockerModels';
import { DockerKvRow } from './parts/DockerSharedWidgets';

/** 单条统计卡片数据 */
class DockerStatCard {
  label: string;
  value: string;
  icon: Resource;

  constructor(label: string, value: string, icon: Resource) {
    this.label = label;
    this.value = value;
    this.icon = icon;
  }
}

/** 从状态 Record 读取字符串（缺省 fallback） */
function statusText(status: Record<string, Object>, key: string, fallback: string): string {
  const v = status[key];
  if (v === undefined || v === null) {
    return fallback;
  }
  const text = dockerStr(v).trim();
  return text.length > 0 ? text : fallback;
}

/**
 * Docker 总览页签（对齐 Flutter _OverviewTab）：
 * 容器总数/运行中/镜像总数/Docker 版本 4 张统计卡 + 引擎信息卡。
 */
@ComponentV2
export struct DockerOverviewTab {
  @Param ctrl: DockerController = new DockerController();

  private cards(): DockerStatCard[] {
    const status = this.ctrl.status;
    return [
      new DockerStatCard(L10n.t('docker_status_containers', '容器总数'),
        statusText(status, 'containers', '0'), $r('sys.symbol.rectangle_stack')),
      new DockerStatCard(L10n.t('docker_status_running', '运行中'),
        statusText(status, 'containersRunning', '0'), $r('sys.symbol.play_circle')),
      new DockerStatCard(L10n.t('docker_status_images', '镜像总数'),
        statusText(status, 'images', '0'), $r('sys.symbol.square_stack_3d')),
      new DockerStatCard(L10n.t('docker_status_version', 'Docker 版本'),
        statusText(status, 'serverVersion', '--'), $r('sys.symbol.info_circle'))
    ];
  }

  @Builder
  StatCard(item: DockerStatCard) {
    GlassCard({ padValue: 16, cornerRadius: 16 }) {
      Row({ space: 14 }) {
        Column() {
          SymbolGlyph(item.icon)
            .fontSize(22)
            .fontColor([AppTheme.current().primary])
        }
        .width(46)
        .height(46)
        .justifyContent(FlexAlign.Center)
        .backgroundColor(AppTheme.withAlpha(AppTheme.current().primary, 0.10))
        .borderRadius(14)
        Column() {
          Text(item.label)
            .fontSize(13)
            .fontColor(AppTheme.current().subText)
          Text(item.value)
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor(AppTheme.current().onSurface)
            .margin({ top: 4 })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
    }
  }

  build() {
    Scroll() {
      Column() {
        ForEach(this.cards(), (item: DockerStatCard): void => {
          Column() {
            this.StatCard(item)
          }
          .margin({ bottom: 6 })
        }, (item: DockerStatCard): string => item.label)
        GlassCard({ padValue: 16, cornerRadius: 16 }) {
          Column() {
            Text(L10n.t('docker_engine_info', '引擎信息'))
              .fontSize(15)
              .fontWeight(FontWeight.Bold)
              .fontColor(AppTheme.current().onSurface)
              .margin({ bottom: 12 })
            DockerKvRow({
              label: L10n.t('docker_status_host', 'Docker Host'),
              value: statusText(this.ctrl.status, 'dockerHost', 'local')
            })
            DockerKvRow({
              label: L10n.t('docker_status_os', '操作系统'),
              value: statusText(this.ctrl.status, 'operatingSystem', '--')
            })
            DockerKvRow({
              label: L10n.t('docker_status_arch', '架构'),
              value: statusText(this.ctrl.status, 'architecture', '--')
            })
            DockerKvRow({
              label: L10n.t('docker_status_name', '引擎名称'),
              value: statusText(this.ctrl.status, 'name', '--')
            })
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
        }
      }
      .width('100%')
      .padding(12)
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Auto)
    .align(Alignment.Top)
  }
}
