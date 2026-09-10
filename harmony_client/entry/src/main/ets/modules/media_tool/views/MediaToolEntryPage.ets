import { L10n } from '../../../core/localization/L10n';
import { AppTheme, ThemePalette } from '../../../core/theme/AppTheme';
import { PageScaffold } from '../../../common/PageScaffold';
import { NavUtil } from '../../../common/NavUtil';
import { CurrentUserStore } from '../../../core/user/CurrentUserStore';
import { MEDIA_TOOL_MENU_ITEMS, MediaToolMenuItem } from '../models/MediaToolModels';
import { MediaToolRoutes, MediaToolEntryPageParam } from '../router/MediaToolRoutes';

/**
 * 媒体工具入口页（对齐 Flutter AppMediaToolEntryView）：
 * 分组菜单（图片/视频/音频/其他）；非管理员仅可见图片压缩转换。
 */
@ComponentV2
export struct MediaToolEntryPage {
  @Param param: MediaToolEntryPageParam = new MediaToolEntryPageParam();
  @Param popPage: () => void = (): void => {
  };
  /** 主题变化刷新计数（依赖驱动整页重渲染换色） */
  @Local tick: number = 0;

  aboutToAppear(): void {
    this.tick = 1;
  }

  private palette(): ThemePalette {
    return AppTheme.current();
  }

  /** 分组 key 顺序（对齐 Flutter keys 列表） */
  private static readonly GROUP_KEYS: string[] = ['media_tool_menu_image',
    'media_tool_menu_video', 'media_tool_menu_audio', 'media_tool_menu_other'];

  /** 可见菜单项：非管理员仅 image.compress（对齐 Flutter _groupedItems 过滤规则） */
  private visibleItems(): MediaToolMenuItem[] {
    const isAdmin = CurrentUserStore.getInstance().isAdmin;
    const out: MediaToolMenuItem[] = [];
    MEDIA_TOOL_MENU_ITEMS.forEach((it: MediaToolMenuItem): void => {
      if (isAdmin || it.key === 'image.compress') {
        out.push(it);
      }
    });
    return out;
  }

  /** 菜单 key → 路由页面名 */
  private routeFor(key: string): string {
    if (key === 'image.compress') {
      return MediaToolRoutes.IMAGE_COMPRESS;
    }
    if (key === 'image.batch_compress') {
      return MediaToolRoutes.IMG_BATCH_COMPRESS;
    }
    if (key === 'video.trans') {
      return MediaToolRoutes.VIDEO_TRANS;
    }
    if (key === 'audio.trans') {
      return MediaToolRoutes.AUDIO_TRANS;
    }
    if (key === 'other.media_arrange') {
      return MediaToolRoutes.MEDIA_ARRANGE;
    }
    return '';
  }

  build() {
    PageScaffold({
      title: L10n.t('app_media_tool', '媒体工具'),
      showBack: true,
      statusBarBg: AppTheme.current().pageBg,
      onBack: (): void => {
        this.popPage();
      },
      content: (): void => {
        this.PageContent()
      }
    })
  }

  @Builder
  PageContent() {
    Scroll() {
      Column() {
        ForEach(MediaToolEntryPage.GROUP_KEYS, (groupKey: string) => {
          this.Section(groupKey)
        }, (groupKey: string) => groupKey)
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 16 })
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
    .align(Alignment.Top)
    .opacity(this.tick >= 0 ? 1 : 1)
  }

  /** 分组可见成员 */
  private itemsForGroup(groupKey: string): MediaToolMenuItem[] {
    const out: MediaToolMenuItem[] = [];
    this.visibleItems().forEach((it: MediaToolMenuItem): void => {
      if (it.groupTitleKey === groupKey) {
        out.push(it);
      }
    });
    return out;
  }

  /** 分组区块：组标题 + 卡片列表（无成员时整块隐藏，对齐 Flutter _Section） */
  @Builder
  Section(groupKey: string) {
    if (this.itemsForGroup(groupKey).length > 0) {
      Column() {
        Text(L10n.t(groupKey, ''))
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.palette().onSurface)
          .width('100%')
          .padding({ left: 4, right: 4, top: 6, bottom: 10 })
        Column() {
          ForEach(this.itemsForGroup(groupKey), (item: MediaToolMenuItem) => {
            this.MenuCard(item)
          }, (item: MediaToolMenuItem) => item.key)
        }
        .width('100%')
      }
      .width('100%')
      .margin({ bottom: 16 })
    }
  }

  /** 菜单卡片（对齐 Flutter AppMediaToolMenuCard） */
  @Builder
  MenuCard(item: MediaToolMenuItem) {
    Row() {
      // 图标块：primary 10% 底 + primary 图标（底色层独立控制透明度）
      Stack() {
        Column()
          .width(42)
          .height(42)
          .borderRadius(12)
          .backgroundColor(this.palette().primary)
          .opacity(0.10)
        SymbolGlyph(item.icon)
          .fontSize(22)
          .fontColor([this.palette().primary])
      }
      .width(42)
      .height(42)

      Column({ space: 4 }) {
        Text(L10n.t(item.titleKey, ''))
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.palette().onSurface)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(L10n.t(item.subtitleKey, ''))
          .fontSize(13)
          .fontColor(this.palette().subText)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .margin({ left: 12 })

      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(16)
        .fontColor([this.palette().hint])
        .margin({ left: 10 })
    }
    .width('100%')
    .padding({ left: 14, right: 12, top: 12, bottom: 12 })
    .borderRadius(14)
    .backgroundColor(this.palette().surfaceBg)
    .border({ width: 1, color: this.palette().divider })
    .margin({ bottom: 12 })
    .onClick(() => {
      const route = this.routeFor(item.key);
      if (route.length > 0) {
        NavUtil.push(route);
      }
    })
  }
}
