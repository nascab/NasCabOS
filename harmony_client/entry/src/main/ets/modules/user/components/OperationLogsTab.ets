import { AppTheme, ThemePalette } from '../../../core/theme/AppTheme';
import { L10n } from '../../../core/localization/L10n';
import { EmptyState } from '../../../common/components/EmptyState';
import { SearchInputBar } from '../../../common/components/SearchInputBar';
import { UserManagementController } from '../controllers/UserManagementController';
import { FileOperationLog } from '../models/UserModels';
import { FileLogItem } from './FileLogItem';

/**
 * 操作日志 Tab（对齐 Flutter _UserManagementOperationLogsTab）：
 * 搜索框（500ms 防抖）+ 文件日志列表 + 触底加载更多 + 空态/加载态。
 */
@ComponentV2
export struct OperationLogsTab {
  @Require @Param ctrl: UserManagementController;
  @Local searchText: string = '';

  aboutToAppear(): void {
    // 首次进入且无数据时拉取（对齐 _maybeLoad 的 tab 激活惰性加载）
    if (this.ctrl.operationLogs.length === 0 && !this.ctrl.operationLogsLoading
      && this.ctrl.selectedId >= 0) {
      void this.ctrl.refreshOperationLogs(this.ctrl.selectedId);
    }
  }

  private palette(): ThemePalette {
    return AppTheme.current();
  }

  @Builder
  Footer() {
    if (this.ctrl.operationLogsLoading) {
      Row() {
        LoadingProgress()
          .width(20)
          .height(20)
          .color(this.palette().primary)
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
      .padding(12)
    } else if (!this.ctrl.operationLogsHasMore) {
      Text(L10n.t('no_more', '没有更多'))
        .fontSize(13)
        .fontColor(this.palette().hint)
        .width('100%')
        .textAlign(TextAlign.Center)
        .padding(12)
    }
  }

  build() {
    Column() {
      // 搜索框（对齐 Flutter 36 高搜索输入框）
      Row() {
        SearchInputBar({
          hintText: L10n.t('search', '搜索'),
          text: this.searchText,
          onChanged: (v: string): void => {
            this.searchText = v;
            this.ctrl.onOperationLogsSearchChanged(v);
          },
          onClear: (): void => {
            this.searchText = '';
            this.ctrl.onOperationLogsSearchChanged('');
          }
        })
      }
      .width('100%')
      .margin({ top: 8 })

      if (this.ctrl.operationLogs.length === 0) {
        Column() {
          if (this.ctrl.operationLogsLoading) {
            LoadingProgress()
              .width(28)
              .height(28)
              .color(this.palette().primary)
          } else {
            EmptyState({
              message: L10n.t('no_data', '暂无数据'),
              imagePath: $rawfile('icons/no_data.png')
            })
          }
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        List({ space: 4 }) {
          ForEach(this.ctrl.operationLogs, (log: FileOperationLog) => {
            ListItem() {
              FileLogItem({ log: log })
            }
          }, (log: FileOperationLog): string =>
            `${log.id}_${log.state}_${log.copiedSize}_${log.totalSize}`)
          ListItem() {
            this.Footer()
          }
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
        .onReachEnd((): void => {
          void this.ctrl.loadMoreOperationLogs();
        })
      }
    }
    .width('100%')
    .height('100%')
    .padding({ left: 12, right: 12 })
  }
}
