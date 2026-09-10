import { AppTheme, ThemePalette } from '../../../core/theme/AppTheme';
import { L10n } from '../../../core/localization/L10n';
import { EmptyState } from '../../../common/components/EmptyState';
import { GlassCard } from '../../../common/components/GlassCard';
import { SecurityCenterController } from '../controllers/SecurityCenterController';
import { SecurityBlacklistItem, formatSecurityTime } from '../models/SecurityModels';

/**
 * IP 黑名单面板（对齐 Flutter IpBlacklistPanel appMode: true 移动端形态）：
 * 无面板头（刷新/清空动作在页面顶栏），纯列表；空态顶部居中。
 */
@ComponentV2
export struct IpBlacklistPanel {
  @Require @Param ctrl: SecurityCenterController;

  private palette(): ThemePalette {
    return AppTheme.current();
  }

  build() {
    Column() {
      if (this.ctrl.blacklist.length === 0) {
        // 对齐 Flutter：Align(topCenter) + Padding(top: 10)
        Column() {
          EmptyState({
            message: L10n.t('no_data', '暂无数据'),
            imagePath: $rawfile('icons/no_data.png')
          })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Center)
        .padding({ top: 10 })
        .layoutWeight(1)
      } else {
        List({ space: 12 }) {
          ForEach(this.ctrl.blacklist, (item: SecurityBlacklistItem) => {
            ListItem() {
              this.BlacklistCard(item)
            }
          }, (item: SecurityBlacklistItem): string =>
            `${item.ip}_${item.createTime}_${item.description}`)
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

  /** 黑名单卡片（对齐 _buildItem：block 图标 + IP + 描述/记录时间 + 右上删除） */
  @Builder
  BlacklistCard(item: SecurityBlacklistItem) {
    GlassCard({ padValue: 16 }) {
      Stack({ alignContent: Alignment.TopEnd }) {
        Column() {
          Row({ space: 8 }) {
            SymbolGlyph($r('sys.symbol.nosign'))
              .fontSize(20)
              .fontColor([this.palette().primary])
            Text(item.ip)
              .fontSize(16)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.palette().onSurface)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
          }
          .width('100%')

          Column({ space: 6 }) {
            this.InfoRow(L10n.t('security.description', '描述'), this.descriptionText(item))
            this.InfoRow(L10n.t('security.record_time', '记录时间'), this.timeText(item))
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .margin({ top: 10 })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        // 内容 12 内边距 + 右上角删除按钮悬空预留位（12+36）
        .padding({ left: 12, right: 48, top: 12, bottom: 12 })

        this.CircleIconButton($r('sys.symbol.trash'), this.palette().onSurface, (): void => {
          void this.ctrl.deleteIp(item.ip);
        })
      }
      .width('100%')
    }
  }

  private descriptionText(item: SecurityBlacklistItem): string {
    return item.description.length > 0 ? item.description : '—';
  }

  private timeText(item: SecurityBlacklistItem): string {
    const time = formatSecurityTime(item.createTime);
    return time.length > 0 ? time : '—';
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

  /** 圆形图标按钮（对齐 IconButton，36 圆形） */
  @Builder
  CircleIconButton(icon: Resource, iconColor: string, onTap: () => void) {
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
    .onClick((): void => {
      onTap();
    })
  }
}
