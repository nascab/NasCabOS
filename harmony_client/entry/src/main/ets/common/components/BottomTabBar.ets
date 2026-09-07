import { AppTheme } from '../../core/theme/AppTheme';

/** 底部标签项数据 */
export class BottomTabItem {
  icon: Resource;
  label: string;

  constructor(icon: Resource, label: string) {
    this.icon = icon;
    this.label = label;
  }
}

/**
 * 通用底部标签栏（照片主页 文件页等复用）：
 * 56 高 + 顶部细分隔线 + surfaceBg 背景，背景通过 expandSafeArea
 * 延伸到底部导航条安全区，保证与安全区底色一致。
 */
@ComponentV2
export struct BottomTabBar {
  @Param items: BottomTabItem[] = [];
  @Param selectedIndex: number = 0;
  @Param onSelect: (index: number) => void = (_index: number): void => {
  };

  build() {
    Row() {
      ForEach(this.items, (item: BottomTabItem, index: number) => {
        Column() {
          SymbolGlyph(item.icon)
            .fontSize(22)
            .fontColor([this.selectedIndex === index ? AppTheme.current().primary : AppTheme.current().hint])
          Text(item.label)
            .fontSize(11)
            .fontColor(this.selectedIndex === index ? AppTheme.current().primary : AppTheme.current().hint)
            .margin({ top: 2 })
            .maxLines(1)
        }
        .layoutWeight(1)
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .onClick(() => {
          if (index !== this.selectedIndex) {
            this.onSelect(index);
          }
        })
      }, (item: BottomTabItem) => item.label)
    }
    .width('100%')
    .height(56)
    .border({ width: { top: 1 }, color: AppTheme.current().divider })
    .backgroundColor(AppTheme.current().surfaceBg)
    // 背景延伸到底部导航条安全区，避免露出页面底色（与 FileBrowserPage 底栏一致）
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
  }
}
