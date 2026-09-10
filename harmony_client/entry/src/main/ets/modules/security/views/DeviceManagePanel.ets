import { AppTheme, ThemePalette } from '../../../core/theme/AppTheme';
import { L10n } from '../../../core/localization/L10n';
import { EmptyState } from '../../../common/components/EmptyState';
import { GlassCard } from '../../../common/components/GlassCard';
import { SecurityCenterController } from '../controllers/SecurityCenterController';
import { SecurityDevice, formatSecurityTime } from '../models/SecurityModels';

/**
 * 设备管理面板（对齐 Flutter DeviceManagePanel appMode: true 移动端形态）：
 * 无面板头（刷新在页面顶栏），纯列表；空态居中。
 */
@ComponentV2
export struct DeviceManagePanel {
  @Require @Param ctrl: SecurityCenterController;

  private palette(): ThemePalette {
    return AppTheme.current();
  }

  build() {
    Column() {
      if (this.ctrl.devices.length === 0) {
        // 对齐 Flutter：const CustomNoData() 居中
        Column() {
          EmptyState({
            message: L10n.t('no_data', '暂无数据'),
            imagePath: $rawfile('icons/no_data.png')
          })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      } else {
        List({ space: 12 }) {
          ForEach(this.ctrl.devices, (item: SecurityDevice) => {
            ListItem() {
              this.DeviceCard(item)
            }
          }, (item: SecurityDevice): string =>
            `${item.deviceId}_${item.deviceName}_${item.lastSeenAt}`)
        }
        .width('100%')
        .height('100%')
        .padding(12)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.palette().pageBg)
  }

  /** 设备卡片（对齐 _buildItem：类型图标 + 名称 + 设备ID/首次/最近/系统版本/可信 + 右上踢出） */
  @Builder
  DeviceCard(item: SecurityDevice) {
    GlassCard({ padValue: 16 }) {
      Stack({ alignContent: Alignment.TopEnd }) {
        Column() {
          Row({ space: 8 }) {
            SymbolGlyph(deviceSymbol(item))
              .fontSize(20)
              .fontColor([this.palette().primary])
            Text(item.deviceName)
              .fontSize(16)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.palette().onSurface)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
          }
          .width('100%')

          Column({ space: 6 }) {
            this.InfoRow(L10n.t('security.device_id', '设备ID'),
              this.orDash(item.deviceId))
            this.InfoRow(L10n.t('security.device_first_seen', '首次登录'),
              this.orDash(formatSecurityTime(item.firstSeenAt)))
            this.InfoRow(L10n.t('security.device_last_seen', '最近登录'),
              this.orDash(formatSecurityTime(item.lastSeenAt)))
            this.InfoRow(L10n.t('security.device_os_version', '系统版本'),
              this.orDash(item.osVersion))
            this.InfoRow(L10n.t('security.device_trusted', '可信'),
              item.trusted ? L10n.t('yes', '是') : L10n.t('no', '否'))
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .margin({ top: 10 })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        // 内容 12 内边距 + 右上角踢出按钮悬空预留位（12+36）
        .padding({ left: 12, right: 48, top: 12, bottom: 12 })

        this.CircleIconButton($r('sys.symbol.entrance_and_exit'), this.palette().error,
          item.deviceId.length > 0, (): void => {
            void this.ctrl.kickDevice(item.deviceId);
          })
      }
      .width('100%')
    }
  }

  private orDash(value: string): string {
    return value.length > 0 ? value : '—';
  }

  /** 信息行（对齐 _infoRow：80 宽标签 + 值最多两行） */
  @Builder
  InfoRow(label: string, value: string) {
    Row() {
      Text(label)
        .fontSize(12)
        .fontColor(this.palette().subText)
        .width(80)
      Text(value)
        .fontSize(14)
        .fontColor(this.palette().onSurface)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
  }

  /** 圆形图标按钮（对齐 IconButton，36 圆形；disabled 不响应） */
  @Builder
  CircleIconButton(icon: Resource, iconColor: string, isEnabled: boolean, onTap: () => void) {
    Column() {
      SymbolGlyph(icon)
        .fontSize(20)
        .fontColor([iconColor])
    }
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .width(36)
    .height(36)
    .borderRadius(18)
    .opacity(isEnabled ? 1 : 0.4)
    .onClick((): void => {
      if (isEnabled) {
        onTap();
      }
    })
  }
}

/**
 * 设备类型图标（对齐 Flutter _deviceIcon 的关键词匹配；符号名均经 SDK 字体验证存在）：
 * android/iphone/ios→phone，ipad/tablet→pad_and_iphone，mac/darwin→pc，
 * windows/win→desktop，linux→display，web/browser→wifi，tv→monitor_fill，默认→display。
 */
function deviceSymbol(item: SecurityDevice): Resource {
  const raw = item.deviceTypeRaw;
  if (raw.includes('android')) {
    return $r('sys.symbol.phone');
  }
  if (raw.includes('iphone') || raw.includes('ios')) {
    return $r('sys.symbol.phone');
  }
  if (raw.includes('ipad') || raw.includes('tablet')) {
    return $r('sys.symbol.pad_and_iphone');
  }
  if (raw.includes('mac') || raw.includes('darwin')) {
    return $r('sys.symbol.pc');
  }
  if (raw.includes('windows') || raw.includes('win')) {
    return $r('sys.symbol.desktop');
  }
  if (raw.includes('linux')) {
    return $r('sys.symbol.display');
  }
  if (raw.includes('web') || raw.includes('browser')) {
    return $r('sys.symbol.wifi');
  }
  if (raw.includes('tv')) {
    return $r('sys.symbol.monitor_fill');
  }
  return $r('sys.symbol.display');
}
