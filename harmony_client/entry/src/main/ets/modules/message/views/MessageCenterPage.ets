import { L10n } from '../../../core/localization/L10n';
import { AppTheme } from '../../../core/theme/AppTheme';
import { PageScaffold } from '../../../common/PageScaffold';
import { DialogUtil } from '../../../common/DialogUtil';
import { SheetHandle, SheetParamsBase, SheetUtil } from '../../../common/SheetUtil';
import {
  formatMessageTime, MessageCenterController
} from '../controllers/MessageCenterController';
import { LEVEL_FILTER_ALL, MessageItem } from '../models/MessageModels';
import { MessageCenterParam } from '../router/MessageRoutes';

/** 颜色加透明度前缀（hex 形如 #RRGGBB；alphaHex 形如 '0D'=5%） */
function withAlpha(hex: string, alphaHex: string): string {
  return `${alphaHex}${hex.substring(1)}`;
}

/** 未读卡片底色：主色 5%（对齐 Flutter primary.withOpacity(0.05)） */
const ALPHA_5: string = '0D';
/** 等级徽章底色：等级色 10%（对齐 Flutter levelColor.withOpacity(0.1)） */
const ALPHA_10: string = '1A';

/**
 * 消息中心页面（对齐 Flutter MessageCenterView 移动端 showAppBar=true 布局）：
 * 标题栏（返回 + 标题 + 等级筛选 + 清空）+ 下拉刷新 + 分页消息列表（触底加载更多）。
 */
@ComponentV2
export struct MessageCenterPage {
  @Param param: MessageCenterParam = new MessageCenterParam();
  @Param popPage: () => void = (): void => {
  };
  @Local ctrl: MessageCenterController = new MessageCenterController();
  @Local refreshing: boolean = false;

  aboutToAppear(): void {
    this.ctrl.init();
  }

  build() {
    PageScaffold({
      title: L10n.t('message_center', '消息中心'),
      showBack: true,
      onBack: (): void => {
        this.popPage();
      },
      actions: (): void => {
        this.HeaderActions();
      },
      content: (): void => {
        this.PageBody();
      }
    })
  }

  // ==================== 标题栏右侧操作 ====================

  @Builder
  HeaderActions() {
    Row({ space: 16 }) {
      // 等级筛选
      SymbolGlyph($r('sys.symbol.funnel'))
        .fontSize(22)
        .fontColor([AppTheme.current().appBarFg])
        .onClick((): void => {
          this.showLevelSheet();
        })
      // 清空消息（列表为空时隐藏，对齐 Flutter 逻辑）
      if (this.ctrl.messages.length > 0) {
        SymbolGlyph($r('sys.symbol.trash_circle'))
          .fontSize(22)
          .fontColor([AppTheme.current().appBarFg])
          .onClick((): void => {
            void this.confirmClear();
          })
      }
    }
  }

  /** 清空确认弹窗（对齐 Flutter clear_messages 弹窗） */
  private async confirmClear(): Promise<void> {
    const r = await DialogUtil.showConfirmDialog(
      L10n.t('clear_messages', '清空消息'),
      L10n.t('clear_messages_confirm', '确定清空所有消息吗？'));
    if (r === true) {
      await this.ctrl.clearMessages();
    }
  }

  /** 弹出等级筛选底部菜单 */
  private showLevelSheet(): void {
    const p: LevelSheetParams = new LevelSheetParams();
    p.current = this.ctrl.selectedLevel;
    p.onPick = (level: number): void => {
      this.ctrl.filterByLevel(level);
    };
    SheetUtil.present(p, wrapBuilder(LevelSheetContent));
  }

  // ==================== 内容区 ====================

  @Builder
  PageBody() {
    Refresh({ refreshing: this.refreshing, offset: 40 }) {
      if (this.ctrl.isLoading && this.ctrl.messages.length === 0) {
        this.LoadingView()
      } else if (this.ctrl.messages.length === 0) {
        this.EmptyView()
      } else {
        List({ space: 12 }) {
          ForEach(this.ctrl.messages, (item: MessageItem): void => {
            ListItem() {
              MessageCard({ item: item, ctrl: this.ctrl })
            }
          }, (item: MessageItem): string => `${item.id}`)
          if (this.ctrl.hasMore) {
            ListItem() {
              this.FooterLoading()
            }
          }
        }
        .width('100%')
        .height('100%')
        .padding(16)
        .onReachEnd((): void => {
          void this.ctrl.loadMore();
        })
      }
    }
      .onRefreshing((): void => {
        this.refreshing = true;
        void this.ctrl.refreshMessages().then((): void => {
          this.refreshing = false;
        });
      })
      .layoutWeight(1)
      .width('100%')
  }

  /** 首次加载中 */
  @Builder
  LoadingView() {
    Column() {
      LoadingProgress()
        .width(40)
        .height(40)
        .color(AppTheme.current().primary)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
  }

  /** 空态（对齐 Flutter bell 图标 + no_messages 文案） */
  @Builder
  EmptyView() {
    Column({ space: 16 }) {
      SymbolGlyph($r('sys.symbol.bell'))
        .fontSize(64)
        .fontColor([AppTheme.current().hint])
      Text(L10n.t('no_messages', '暂无消息'))
        .fontSize(14)
        .fontColor(AppTheme.current().subText)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
  }

  /** 列表底部加载更多指示器 */
  @Builder
  FooterLoading() {
    Row() {
      LoadingProgress()
        .width(24)
        .height(24)
        .color(AppTheme.current().primary)
    }
    .width('100%')
    .justifyContent(FlexAlign.Center)
    .padding(8)
  }
}

/**
 * 单条消息卡片（对齐 Flutter _buildMessageItem）：
 * 等级色条 + 等级徽章/时间/外链图标 + 标题 + 正文 + 右侧删除按钮；点击卡片执行消息动作。
 */
@ComponentV2
struct MessageCard {
  @Require @Param item: MessageItem;
  @Require @Param ctrl: MessageCenterController;

  build() {
    Row({ space: 12 }) {
      // 左侧等级色条
      Column()
        .width(4)
        .height(40)
        .borderRadius(2)
        .backgroundColor(this.ctrl.levelColor(this.item.level))

      Column() {
        Row() {
          // 等级徽章
          Text(this.ctrl.levelText(this.item.level))
            .fontSize(11)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.ctrl.levelColor(this.item.level))
            .padding({ left: 8, right: 8, top: 2, bottom: 2 })
            .borderRadius(4)
            .backgroundColor(withAlpha(this.ctrl.levelColor(this.item.level), ALPHA_10))
          // 创建时间
          Text(formatMessageTime(this.item.createTime))
            .fontSize(12)
            .fontColor(AppTheme.current().hint)
            .margin({ left: 8 })
          // 有动作时显示外链图标
          if (this.isActionable()) {
            SymbolGlyph($r('sys.symbol.arrow_up_right'))
              .fontSize(14)
              .fontColor([AppTheme.current().hint])
              .margin({ left: 8 })
          }
        }
        .width('100%')

        if (this.item.title.trim().length > 0) {
          Text(this.item.title.trim())
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor(AppTheme.current().onSurface)
            .width('100%')
            .margin({ top: 10 })
        }

        Text(this.item.message)
          .fontSize(14)
          .fontColor(AppTheme.current().onSurface)
          .fontWeight(this.item.readStatus === 0 ? FontWeight.Medium : FontWeight.Normal)
          .width('100%')
          .margin({ top: 8 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      // 右侧删除按钮
      SymbolGlyph($r('sys.symbol.xmark'))
        .fontSize(18)
        .fontColor([AppTheme.current().hint])
        .onClick((): void => {
          void this.confirmDelete();
        })
    }
    .alignItems(VerticalAlign.Top)
    .width('100%')
    .padding(16)
    .borderRadius(12)
    .backgroundColor(this.item.readStatus === 0
      ? withAlpha(AppTheme.current().primary, ALPHA_5)
      : AppTheme.current().cardBg)
    .border({ width: 1, color: AppTheme.current().divider })
    .onClick((): void => {
      void this.ctrl.onMessageTap(this.item);
    })
  }

  /** 是否带可执行动作（对齐 Flutter actionable 判定） */
  private isActionable(): boolean {
    const action = this.item.action;
    if (action === undefined) {
      return false;
    }
    const t: string = MessageItem.toStr(action['type']).trim();
    return t.length > 0 && t !== 'none';
  }

  /** 删除确认弹窗（对齐 Flutter delete_message 弹窗） */
  private async confirmDelete(): Promise<void> {
    const r = await DialogUtil.showConfirmDialog(
      L10n.t('delete_message', '删除消息'),
      L10n.t('delete_message_confirm', '确定删除这条消息吗？'));
    if (r === true) {
      await this.ctrl.deleteMessage(this.item.id);
    }
  }
}

/** 等级筛选菜单参数 */
class LevelSheetParams extends SheetParamsBase {
  /** 当前选中的等级 */
  current: number = LEVEL_FILTER_ALL;
  onPick: (level: number) => void = (_level: number): void => {
  };
}

/** 等级筛选菜单内容 */
@Builder
function LevelSheetContent(p: LevelSheetParams) {
  Column() {
    SheetHandle()
    LevelSheetRow(p, LEVEL_FILTER_ALL, L10n.t('all_levels', '全部等级'))
    LevelSheetRow(p, 0, L10n.t('normal', '普通'))
    LevelSheetRow(p, 1, L10n.t('important', '重要'))
    LevelSheetRow(p, 2, L10n.t('urgent', '紧急'))
  }
  .width('100%')
  .backgroundColor(AppTheme.current().surfaceBg)
  .borderRadius({ topLeft: 20, topRight: 20 })
  .padding({ bottom: 30 })
}

/** 等级筛选菜单单行：选中项前显示对勾，未选中显示等宽空白占位 */
@Builder
function LevelSheetRow(p: LevelSheetParams, level: number, label: string) {
  Row() {
    if (p.current === level) {
      SymbolGlyph($r('sys.symbol.checkmark'))
        .fontSize(20)
        .fontColor([AppTheme.current().primary])
    } else {
      Column()
        .width(20)
        .height(20)
    }
    Text(label)
      .fontSize(16)
      .fontColor(AppTheme.current().onSurface)
      .margin({ left: 12 })
  }
  .width('100%')
  .padding({ left: 20, right: 20, top: 12, bottom: 12 })
  .onClick((): void => {
    p.close();
    p.onPick(level);
  })
}
