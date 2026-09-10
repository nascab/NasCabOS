import { L10n } from '../../../core/localization/L10n';
import { AppTheme, ThemePalette } from '../../../core/theme/AppTheme';
import { ThemeManager } from '../../../core/theme/ThemeManager';
import { AppEventBus } from '../../../common/AppEventBus';
import { GlassCard } from '../../../common/components/GlassCard';
import { EmptyState } from '../../../common/components/EmptyState';
import { TransmissionController } from '../controllers/TransmissionController';

/**
 * 总览标签页（对齐 Flutter _OverviewTab）：
 * 服务运行状态卡（开关 + 端口信息 + 错误提示）+ 运行中统计卡（手机端纵向全宽排列）。
 */
@ComponentV2
export struct TransmissionOverviewTab {
  @Param ctrl: TransmissionController = new TransmissionController();
  /** 主题变化刷新计数（AppTheme.current() 非响应式） */
  @Local themeTick: number = 0;
  private themeListener: (data: string) => void = (_data: string): void => {
    this.themeTick++;
  };

  aboutToAppear(): void {
    AppEventBus.on(ThemeManager.EVENT_THEME_CHANGED, this.themeListener);
  }

  aboutToDisappear(): void {
    AppEventBus.off(ThemeManager.EVENT_THEME_CHANGED, this.themeListener);
  }

  build() {
    Scroll() {
      Column() {
        // 服务状态卡（对齐 CustomGlassCard 服务行）
        GlassCard({
          padValue: 14,
          content: (): void => {
            this.ServiceCard()
          }
        })

        if (this.ctrl.isRunning()) {
          // 统计卡（对齐 isPhone 分支：纵向全宽 statCards）
          Column({ space: 12 }) {
            this.StatCard(L10n.t('transmission_download_speed', '下载速度'),
              this.ctrl.formatSpeed(this.num(this.ctrl.sessionStats['downloadSpeed'])))
            this.StatCard(L10n.t('transmission_upload_speed', '上传速度'),
              this.ctrl.formatSpeed(this.num(this.ctrl.sessionStats['uploadSpeed'])))
            this.StatCard(L10n.t('transmission_active_torrents', '活跃任务'),
              `${this.numOrZero(this.ctrl.sessionStats['activeTorrentCount'])}`)
            this.StatCard(L10n.t('transmission_total_downloaded', '累计下载'),
              this.ctrl.formatBytes(this.ctrl.overviewTotalDownloaded))
            this.StatCard(L10n.t('transmission_total_uploaded', '累计上传'),
              this.ctrl.formatBytes(this.ctrl.overviewTotalUploaded))
          }
          .width('100%')
          .margin({ top: 12 })
        } else {
          Column() {
            EmptyState({
              message: L10n.t('transmission_service_not_running', 'Transmission 服务未运行'),
              imagePath: $rawfile('icons/no_data.png')
            })
          }
          .width('100%')
          .margin({ top: 12 })
        }
      }
      .width('100%')
      .padding(12)
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
    .align(Alignment.Top)
    .opacity(this.themeTick >= 0 ? 1 : 1)
  }

  /** 服务状态卡内容（对齐 Flutter 服务行：标题 + 端口 + 错误 + 开关） */
  @Builder
  ServiceCard() {
    Row() {
      Column({ space: 8 }) {
        Text(this.ctrl.isRunning()
          ? L10n.t('transmission_service_running', '服务运行中')
          : L10n.t('transmission_service_stopped', '服务已停止'))
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.palette().onSurface)
        Text(`${L10n.t('transmission_configured_port', '配置端口')}: ${this.ctrl.configuredPortText}  `
          + `${L10n.t('transmission_actual_port', '实际端口')}: ${this.ctrl.actualPortText}`)
          .fontSize(12)
          .fontColor(this.palette().subText)
        if (this.ctrl.portMismatch) {
          Text(L10n.t('transmission_restart_required', '部分配置需重启服务后生效'))
            .fontSize(12)
            .fontColor(this.palette().error)
        }
        if (this.ctrl.lastError.length > 0) {
          Text(`${L10n.t('error', '错误')}: ${this.ctrl.lastError}`)
            .fontSize(12)
            .fontColor(this.palette().error)
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      if (this.ctrl.serviceOperating) {
        LoadingProgress()
          .width(20)
          .height(20)
          .color(this.palette().primary)
          .margin({ right: 12 })
      }
      Toggle({ type: ToggleType.Switch, isOn: this.ctrl.isRunning() })
        .selectedColor(this.palette().primary)
        .enabled(!this.ctrl.serviceOperating)
        .onChange((on: boolean) => {
          void this.ctrl.toggleService(on);
        })
    }
    .alignItems(VerticalAlign.Center)
    .width('100%')
  }

  /** 统计小卡（对齐 _StatCard：标题 + 数值） */
  @Builder
  StatCard(title: string, value: string) {
    GlassCard({ padValue: 14 }) {
      Column({ space: 6 }) {
        Text(title)
          .fontSize(12)
          .fontColor(this.palette().subText)
        Text(value)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.palette().onSurface)
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')
    }
  }

  /** 数字字段读取（非数字 → 0） */
  private num(v: Object | undefined): number {
    return typeof v === 'number' && Number.isFinite(v) ? v : 0;
  }

  private numOrZero(v: Object | undefined): number {
    return this.num(v);
  }

  private palette(): ThemePalette {
    return AppTheme.current();
  }
}
