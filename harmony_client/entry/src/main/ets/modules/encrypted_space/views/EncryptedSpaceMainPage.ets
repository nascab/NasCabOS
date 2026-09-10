import { L10n } from '../../../core/localization/L10n';
import { AppTheme, ThemePalette } from '../../../core/theme/AppTheme';
import { ThemeManager } from '../../../core/theme/ThemeManager';
import { PageScaffold } from '../../../common/PageScaffold';
import { EmptyState } from '../../../common/components/EmptyState';
import { AppEventBus } from '../../../common/AppEventBus';
import { NavUtil } from '../../../common/NavUtil';
import {
  EncryptedSpaceController, EncryptedSpaceEntry
} from '../controllers/EncryptedSpaceController';
import { EncryptedSpaceActiveSpace } from '../models/EncryptedSpaceModels';
import {
  showEncryptedSpaceActionSheet
} from '../components/EncryptedSpaceSheets';
import {
  runEncryptedCreateSpaceFlow, runEncryptedImportSpaceFlow,
  runEncryptedExportSpaceFlow, showEncryptedExportTasksSheet
} from '../components/EncryptedSpaceDialogs';
import { EncryptedSpaceMainPageParam, EncryptedSpaceDetailPageParam } from '../router/EncryptedSpaceRoutes';
import { AppRouter } from '../../../router/AppRouter';

/**
 * 加密空间主页（对齐 Flutter AppEncryptedSpaceView + AppEncryptedSpaceSpaceGrid）：
 * 顶栏 刷新/创建/导入/导出任务，空间网格卡片（渐变预览 + 底部名称/更多）。
 */
@ComponentV2
export struct EncryptedSpaceMainPage {
  @Param param: EncryptedSpaceMainPageParam = new EncryptedSpaceMainPageParam();
  @Param popPage: () => void = (): void => {
  };
  @Local ctrl: EncryptedSpaceController = new EncryptedSpaceController();
  /** 主题变化刷新计数（AppTheme.current() 非响应式） */
  @Local themeTick: number = 0;
  /** 视口宽度（用于计算网格列数） */
  @Local viewWidth: number = 0;
  @Local refreshing: boolean = false;
  private themeListener: (data: string) => void = (_data: string): void => {
    this.themeTick++;
  };

  aboutToAppear(): void {
    AppEventBus.on(ThemeManager.EVENT_THEME_CHANGED, this.themeListener);
    void this.ctrl.refreshList(false);
  }

  aboutToDisappear(): void {
    AppEventBus.off(ThemeManager.EVENT_THEME_CHANGED, this.themeListener);
    // 释放活动空间并静默删除 token（对齐 Flutter controller.onClose）
    this.ctrl.release();
  }

  private th(): ThemePalette {
    return AppTheme.current();
  }

  /** 打开空间：密码校验成功后记录活动空间并进入详情页（对齐 _openSpaceMobile） */
  private openSpace(space: EncryptedSpaceEntry): void {
    this.ctrl.openSpaceFlow(space, (data: Record<string, Object>): void => {
      if (space.id <= 0) {
        return;
      }
      const token = `${data['token'] ?? ''}`.trim();
      if (token.length === 0) {
        return;
      }
      const active = new EncryptedSpaceActiveSpace(space.id, token, space.name, space.path);
      this.ctrl.openActiveSpace(active);
      const nav = new EncryptedSpaceDetailPageParam();
      nav.spaceId = active.spaceId;
      nav.token = active.token;
      nav.name = active.name;
      nav.path = active.path;
      NavUtil.push(AppRouter.ENCRYPTED_SPACE_DETAIL, nav);
    });
  }

  private gridColumnCount(): number {
    const width = this.viewWidth;
    if (width <= 0) {
      return 2;
    }
    return Math.min(4, Math.max(1, Math.floor(width / 320)));
  }

  private columnsTemplate(): string {
    const count = this.gridColumnCount();
    const parts: string[] = [];
    for (let i = 0; i < count; i++) {
      parts.push('1fr');
    }
    return parts.join(' ');
  }

  private async pullRefresh(): Promise<void> {
    if (this.refreshing) {
      return;
    }
    this.refreshing = true;
    try {
      await this.ctrl.refreshList(false);
    } finally {
      this.refreshing = false;
    }
  }

  build() {
    PageScaffold({
      title: L10n.t('app_encrypted', '加密空间'),
      showBack: true,
      onBack: (): void => {
        this.popPage();
      },
      actions: (): void => {
        this.HeaderActions()
      },
      content: (): void => {
        this.Body()
      }
    })
  }

  @Builder
  HeaderActions() {
    Row({ space: 14 }) {
      SymbolGlyph($r('sys.symbol.arrow_clockwise'))
        .fontSize(22)
        .fontColor([this.th().appBarFg])
        .onClick(() => {
          void this.ctrl.refreshList(true);
        })
      SymbolGlyph($r('sys.symbol.plus'))
        .fontSize(22)
        .fontColor([this.th().appBarFg])
        .onClick(() => {
          runEncryptedCreateSpaceFlow(this.ctrl);
        })
      SymbolGlyph($r('sys.symbol.folder'))
        .fontSize(22)
        .fontColor([this.th().appBarFg])
        .onClick(() => {
          runEncryptedImportSpaceFlow(this.ctrl);
        })
      SymbolGlyph($r('sys.symbol.list_bullet'))
        .fontSize(22)
        .fontColor([this.th().appBarFg])
        .onClick(() => {
          showEncryptedExportTasksSheet(this.ctrl);
        })
    }
  }

  @Builder
  Body() {
    Stack() {
      if (this.ctrl.isLoading && this.ctrl.spaces.length === 0) {
        Column() {
          LoadingProgress()
            .width(40)
            .height(40)
            .color(this.th().primary)
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
      } else if (this.ctrl.errorText.length > 0) {
        Text(this.ctrl.errorText)
          .fontSize(14)
          .fontColor(this.th().subText)
          .width('100%')
          .height('100%')
          .textAlign(TextAlign.Center)
      } else if (this.ctrl.spaces.length === 0) {
        EmptyState({ message: L10n.t('no_data', '暂无数据') })
      } else {
        Refresh({ refreshing: this.refreshing }) {
          Grid() {
            ForEach(this.ctrl.spaces, (item: EncryptedSpaceEntry, idx: number) => {
              GridItem() {
                EncryptedSpaceCard({
                  item: item,
                  onOpen: (): void => {
                    this.openSpace(item);
                  },
                  onExport: (): void => {
                    runEncryptedExportSpaceFlow(this.ctrl, item);
                  },
                  onRename: (): void => {
                    void this.ctrl.renameSpaceFlow(item);
                  },
                  onDelete: (): void => {
                    void this.ctrl.deleteSpaceFlow(item);
                  }
                })
              }
            }, (item: EncryptedSpaceEntry, idx: number) => `${item.id}_${idx}`)
          }
          .columnsTemplate(this.columnsTemplate())
          .columnsGap(12)
          .rowsGap(12)
          .padding({ left: 12, right: 12, top: 8, bottom: 12 })
          .width('100%')
          .height('100%')
          .onAreaChange((_o: Area, n: Area) => {
            this.viewWidth = Number(n.width);
          })
        }
        .onRefreshing((): void => {
          this.pullRefresh();
        })
      }
    }
    .width('100%')
    .height('100%')
  }
}

/**
 * 空间网格卡片（对齐 Flutter AppEncryptedSpaceGridCard + CustomAlbum）：
 * 渐变预览 + 锁图标，底部名称 + 更多按钮（打开/导出/重命名/删除）。
 */
@ComponentV2
struct EncryptedSpaceCard {
  @Param item: EncryptedSpaceEntry = new EncryptedSpaceEntry();
  @Param onOpen: () => void = (): void => {
  };
  @Param onExport: () => void = (): void => {
  };
  @Param onRename: () => void = (): void => {
  };
  @Param onDelete: () => void = (): void => {
  };

  private th(): ThemePalette {
    return AppTheme.current();
  }

  build() {
    Column() {
      // 预览区（对齐 gradient preview + lock icon）
      Stack() {
        Column()
          .width('100%')
          .height('100%')
          .linearGradient({
            angle: 135,
            colors: [[this.th().primary, 0.0], [this.th().secondary, 1.0]]
          })
        SymbolGlyph($r('sys.symbol.lock'))
          .fontSize(66)
          .fontColor(['#FFFFFF'])
      }
      .width('100%')
      .layoutWeight(1)

      // 底部标题行（对齐 headerPosition bottom）
      Row({ space: 6 }) {
        Text(this.item.displayTitle())
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor('#FFFFFF')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        SymbolGlyph($r('sys.symbol.more'))
          .fontSize(20)
          .fontColor(['#FFFFFF'])
          .onClick(() => {
            showEncryptedSpaceActionSheet(this.item, (): void => {
              this.onOpen();
            }, (): void => {
              this.onExport();
            }, (): void => {
              this.onRename();
            }, (): void => {
              this.onDelete();
            });
          })
      }
      .width('100%')
      .height(44)
      .padding({ left: 12, right: 8 })
      .backgroundColor('#33000000')
    }
    .width('100%')
    .height(176)
    .borderRadius(14)
    .clip(true)
    .onClick(() => {
      this.onOpen();
    })
  }
}
