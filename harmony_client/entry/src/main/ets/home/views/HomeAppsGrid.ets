import { HomeViewModel } from '../HomeViewModel';
import { AppIconMap } from '../AppIconMap';
import { L10n } from '../../core/localization/L10n';

/** 应用图标网格：对应 Flutter AppAppsGrid（长按拖拽排序 + 点击打开） */
@ComponentV2
export struct HomeAppsGrid {
  @Require @Param vm: HomeViewModel;
  @Param onTapApp: (app: string) => void = (_app: string) => {
  };
  @Local crossCount: number = 4;
  private readonly minItemWidth: number = 75;
  private readonly spacing: number = 10;

  private updateCrossCount(width: number): void {
    const count = Math.floor((width + this.spacing) / (this.minItemWidth + this.spacing));
    const next = count > 0 ? count : 1;
    if (next !== this.crossCount) {
      this.crossCount = next;
    }
  }

  private columnsTemplate(): string {
    const parts: string[] = [];
    for (let i = 0; i < this.crossCount; i++) {
      parts.push('1fr');
    }
    return parts.join(' ');
  }

  build() {
    Grid() {
      ForEach(this.vm.filteredApps(), (app: string) => {
        GridItem() {
          Column() {
            Image(AppIconMap.getIcon(app))
              .width(60)
              .height(60)
              .interpolation(ImageInterpolation.High)
              .draggable(false)
            Text(this.vm.getAppDisplayName(app))
              .fontSize(12)
              .fontWeight(FontWeight.Medium)
              .fontColor(Color.White)
              .shadow({ color: '#B3000000', offsetX: 0, offsetY: 1, radius: 4 })
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .textAlign(TextAlign.Center)
              .margin({ top: 6 })
          }
          .width('100%')
          .aspectRatio(0.86)
          .justifyContent(FlexAlign.Center)
          .onClick(() => {
            this.onTapApp(app);
          })
        }
      }, (app: string) => app)
    }
    .columnsTemplate(this.columnsTemplate())
    .columnsGap(this.spacing)
    .rowsGap(this.spacing)
    .width('100%')
    .layoutWeight(1)
    .padding({ left: 10, right: 10, bottom: 10 })
    .scrollBar(BarState.Off)
    .editMode(true)
    .onAreaChange((_old: Area, newVal: Area) => {
      this.updateCrossCount(newVal.width as number);
    })
    .onItemDrop((event: ItemDragInfo, itemIndex: number, insertIndex: number, isSuccess: boolean) => {
      if (isSuccess && insertIndex >= 0 && itemIndex !== insertIndex) {
        this.vm.reorderApp(itemIndex, insertIndex);
      }
    })
    .onItemDragStart((_event: ItemDragInfo, itemIndex: number): (() => void) => {
      const apps = this.vm.filteredApps();
      const app = itemIndex >= 0 && itemIndex < apps.length ? apps[itemIndex] : '';
      return (): void => {
        this.dragBuilder(app);
      };
    })
  }

  @Builder
  dragBuilder(app: string) {
    Column() {
      Image(AppIconMap.getIcon(app))
        .width(66)
        .height(66)
      Text(this.vm.getAppDisplayName(app))
        .fontSize(12)
        .fontColor(Color.White)
    }
    .justifyContent(FlexAlign.Center)
  }
}
