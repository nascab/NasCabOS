import { L10n } from '../../../core/localization/L10n';
import { AppTheme } from '../../../core/theme/AppTheme';
import { PageScaffold } from '../../../common/PageScaffold';
import { MonitorController, formatMonitorCpuInfo } from '../controllers/MonitorController';
import { MonitorDisk, MonitorGpuController, MonitorMetrics } from '../models/MonitorModels';
import { MonitorPageParam } from '../router/MonitorRoutes';

/** 使用率颜色（对齐 Flutter _getUsageColor） */
function usageColor(percent: number): string {
  if (percent > 0.9) {
    return '#F44336';
  }
  if (percent > 0.7) {
    return '#FF9800';
  }
  return '#2196F3';
}

/** 可用/总容量文案（对齐 Flutter availableFormatted + ' / ' + sizeFormatted） */
function diskSizeText(disk: MonitorDisk): string {
  if (disk.sizeFormatted.length > 0) {
    return `${disk.availableFormatted} / ${disk.sizeFormatted}`;
  }
  return disk.availableFormatted;
}

/**
 * 设备监控页（对齐 Flutter AppMonitorView + MonitorView 移动端布局）：
 * 顶部设备监控卡（CPU / 内存 / 网络 纵向排列）+ 存储设备卡片列表，
 * 数据由 MonitorController 每 3 秒轮询 /api/hw/metrics 刷新。
 */
@ComponentV2
export struct MonitorPage {
  @Param param: MonitorPageParam = new MonitorPageParam();
  @Param popPage: () => void = (): void => {
  };
  @Local ctrl: MonitorController = MonitorController.getInstance();

  aboutToAppear(): void {
    // 对齐 Flutter initState：HwMetricsController.instance.start()
    this.ctrl.start(getContext(this));
  }

  aboutToDisappear(): void {
    // 对齐 Flutter dispose：HwMetricsController.instance.stop()
    this.ctrl.stop();
  }

  build() {
    PageScaffold({
      title: L10n.t('monitor_device_monitor', '设备监控'),
      showBack: true,
      onBack: (): void => {
        this.popPage();
      },
      content: (): void => {
        this.MonitorBody()
      }
    })
  }

  @Builder
  MonitorBody() {
    if (this.ctrl.metrics === undefined) {
      // 无数据（未拉取/上次拉取失败）时显示加载中
      Column() {
        LoadingProgress()
          .width(36)
          .height(36)
          .color(AppTheme.current().primary)
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
    } else {
      Scroll() {
        Column() {
          // 第一部分：设备监控（Flutter 中该节标题右对齐）
          Row() {
            Text(L10n.t('monitor_device_monitor', '设备监控'))
              .fontSize(16)
              .fontWeight(FontWeight.Bold)
              .fontColor(AppTheme.current().onSurface)
          }
          .width('100%')
          .justifyContent(FlexAlign.End)

          this.DeviceMonitorCard(this.ctrl.metrics)

          // 第二部分：存储设备
          Text(L10n.t('monitor_storage_device', '存储设备'))
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor(AppTheme.current().onSurface)
            .margin({ top: 12 })
            .width('100%')

          this.StorageDevicesList(this.ctrl.metrics)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding(12)
      }
      .width('100%')
      .height('100%')
      .align(Alignment.Top)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
    }
  }

  /** 水平分割线（对齐 Flutter CustomDivider(height: 24, thickness: 1)） */
  @Builder
  SectionDivider() {
    Divider()
      .strokeWidth(1)
      .color(AppTheme.current().divider)
      .margin({ top: 12, bottom: 12 })
  }

  /** 设备监控卡片（对齐 Flutter _buildDeviceMonitorCard 移动端分支：纵向排列） */
  @Builder
  DeviceMonitorCard(metrics: MonitorMetrics) {
    Column() {
      this.CpuSection(metrics)
      this.SectionDivider()
      this.MemorySection(metrics)
      this.SectionDivider()
      this.NetworkSection(metrics)
    }
    .width('100%')
    .padding(12)
    .borderRadius(12)
    .backgroundColor(AppTheme.current().cardBg)
    .shadow({
      radius: 4,
      color: '#14000000',
      offsetY: 1
    })
    .margin({ top: 8 })
  }

  /** CPU 信息区域（对齐 Flutter _buildCpuInfo） */
  @Builder
  CpuSection(metrics: MonitorMetrics) {
    if (metrics.cpu !== undefined) {
      Column({ space: 4 }) {
        SymbolGlyph($r('sys.symbol.computer'))
          .fontSize(24)
          .fontColor(['#2196F3'])

        // GPU 型号列表（对齐 Flutter gpuInfo 列表渲染）
        if (metrics.gpu !== undefined && metrics.gpu.controllers.length > 0) {
          ForEach(metrics.gpu.controllers, (g: MonitorGpuController, idx: number) => {
            Text(`GPU${idx + 1}: ${g.model}`)
              .fontSize(10)
              .fontColor('#9E9E9E')
          }, (g: MonitorGpuController, idx: number) => `${idx}_${g.model}`)
        }

        Row({ space: 8 }) {
          Text('CPU:')
            .fontSize(12)
            .fontColor(AppTheme.current().onSurface)
          if (metrics.cpuInfo !== undefined) {
            Text(formatMonitorCpuInfo(metrics.cpuInfo))
              .fontSize(12)
              .fontColor(AppTheme.current().onSurface)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .constraintSize({ maxWidth: '75%' })
          }
        }
        .justifyContent(FlexAlign.Center)
        .constraintSize({ maxWidth: '100%' })

        Text(`${L10n.t('monitor_used', '已用')}: ${metrics.cpu.usage.toFixed(1)}%`)
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppTheme.current().onSurface)

        if (metrics.cpu.temperature > 0) {
          Row({ space: 2 }) {
            SymbolGlyph($r('sys.symbol.thermometer'))
              .fontSize(12)
              .fontColor(['#FF9800'])
            Text(`${metrics.cpu.temperature.toFixed(1)}°C`)
              .fontSize(12)
              .fontColor(AppTheme.current().onSurface)
          }
          .justifyContent(FlexAlign.Center)
        }
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
    }
  }

  /** 内存信息区域（对齐 Flutter _buildMemoryInfo） */
  @Builder
  MemorySection(metrics: MonitorMetrics) {
    if (metrics.memory !== undefined) {
      Column({ space: 2 }) {
        Stack() {
          Progress({
            value: Math.min(Math.max(metrics.memory.usage, 0), 100),
            total: 100,
            type: ProgressType.Ring
          })
            .width(50)
            .height(50)
            .style({
              strokeWidth: 5
            })
            .color('#9C27B0')
          Text(`${metrics.memory.usage.toFixed(1)}%`)
            .fontSize(12)
            .fontWeight(FontWeight.Bold)
            .fontColor(AppTheme.current().onSurface)
        }

        Text(L10n.t('monitor_memory', '内存'))
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppTheme.current().onSurface)
          .margin({ top: 6 })

        Text(`${L10n.t('monitor_used', '已用')}: ${metrics.memory.usedFormatted} / `
          + `${L10n.t('monitor_total', '总量')}: ${metrics.memory.totalFormatted}`)
          .fontSize(12)
          .fontColor(AppTheme.current().onSurface)
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
    }
  }

  /** 网络信息区域（对齐 Flutter _buildNetworkInfo） */
  @Builder
  NetworkSection(metrics: MonitorMetrics) {
    if (metrics.network !== undefined) {
      Column({ space: 2 }) {
        SymbolGlyph($r('sys.symbol.wifi'))
          .fontSize(24)
          .fontColor(['#4CAF50'])

        Text(L10n.t('monitor_network', '网络'))
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppTheme.current().onSurface)
          .margin({ top: 6 })

        Row({ space: 2 }) {
          SymbolGlyph($r('sys.symbol.arrow_up'))
            .fontSize(14)
            .fontColor(['#FF9800'])
          Text(`${L10n.t('upload', '上传')}: ${metrics.network.uploadSpeed}`)
            .fontSize(12)
            .fontColor(AppTheme.current().onSurface)
        }
        .justifyContent(FlexAlign.Center)
        .margin({ top: 6 })

        Row({ space: 2 }) {
          SymbolGlyph($r('sys.symbol.arrow_down'))
            .fontSize(14)
            .fontColor(['#2196F3'])
          Text(`${L10n.t('download', '下载')}: ${metrics.network.downloadSpeed}`)
            .fontSize(12)
            .fontColor(AppTheme.current().onSurface)
        }
        .justifyContent(FlexAlign.Center)
        .margin({ top: 2 })
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
    }
  }

  /** 存储设备列表（对齐 Flutter _buildStorageDevicesList） */
  @Builder
  StorageDevicesList(metrics: MonitorMetrics) {
    if (metrics.disks.length === 0) {
      Column() {
        Text(L10n.t('no_data', '暂无数据'))
          .fontSize(14)
          .fontColor(AppTheme.current().hint)
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
      .padding({ top: 16, bottom: 16 })
    } else {
      Column() {
        ForEach(metrics.disks, (disk: MonitorDisk) => {
          this.DiskCard(disk)
        }, (disk: MonitorDisk, idx: number) =>
          `${idx}_${disk.mount}_${disk.fs}_${disk.usagePercent}`)
      }
      .width('100%')
      .margin({ top: 8 })
    }
  }

  /** 单个磁盘卡片（对齐 Flutter _buildDiskCard） */
  @Builder
  DiskCard(disk: MonitorDisk) {
    Row() {
      // 图标（蓝色圆形底）
      Column() {
        SymbolGlyph($r('sys.symbol.externaldrive'))
          .fontSize(20)
          .fontColor(['#2196F3'])
      }
      .width(36)
      .height(36)
      .borderRadius(18)
      .backgroundColor('#1A2196F3')
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)

      // 详情
      Column({ space: 2 }) {
        Text(disk.mount)
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppTheme.current().onSurface)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        Text(`${L10n.t('type', '类型')}: ${disk.type}`)
          .fontSize(12)
          .fontColor(AppTheme.current().onSurface)
        Text(`${L10n.t('path', '路径')}: ${disk.fs}`)
          .fontSize(12)
          .fontColor(AppTheme.current().onSurface)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .margin({ left: 12 })

      // 使用率环形图 / 可用容量
      if (disk.usagePercent >= 0) {
        Column({ space: 4 }) {
          Stack() {
            Progress({
              value: Math.round(disk.usagePercent * 100),
              total: 100,
              type: ProgressType.Ring
            })
              .width(40)
              .height(40)
              .style({
                strokeWidth: 4
              })
              .color(usageColor(disk.usagePercent))
            Text(`${Math.round(disk.usagePercent * 100)}%`)
              .fontSize(10)
              .fontWeight(FontWeight.Bold)
              .fontColor(AppTheme.current().onSurface)
          }

          Row() {
            Text(diskSizeText(disk))
              .fontSize(10)
              .fontColor(AppTheme.current().onSurface)
          }
          .justifyContent(FlexAlign.Center)
        }
        .alignItems(HorizontalAlign.Center)
        .margin({ left: 12 })
      } else {
        Text(disk.availableFormatted)
          .fontSize(12)
          .fontColor(AppTheme.current().onSurface)
          .margin({ left: 12 })
      }
    }
    .width('100%')
    .padding(12)
    .borderRadius(12)
    .backgroundColor(AppTheme.current().cardBg)
    .shadow({
      radius: 4,
      color: '#14000000',
      offsetY: 1
    })
    .margin({ bottom: 8 })
    .alignItems(VerticalAlign.Center)
  }
}
