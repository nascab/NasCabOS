import { AppTheme, ThemePalette } from '../../../core/theme/AppTheme';
import { L10n } from '../../../core/localization/L10n';
import { EmptyState } from '../../../common/components/EmptyState';
import { UserManagementController } from '../controllers/UserManagementController';
import { LoginRecord } from '../models/UserModels';
import { LoginRecordCard } from './LoginRecordCard';

/**
 * 登录记录 Tab（对齐 Flutter _UserManagementLoginRecordsTab）：
 * 记录卡片列表 + 触底加载更多 + 空态。
 */
@ComponentV2
export struct LoginRecordsTab {
  @Require @Param ctrl: UserManagementController;

  aboutToAppear(): void {
    // 首次进入且无数据时拉取（详情页在进入前已 selectUser 触发刷新，这里兜底）
    if (this.ctrl.loginRecords.length === 0 && !this.ctrl.loginRecordsLoading
      && this.ctrl.selectedId >= 0) {
      void this.ctrl.refreshLoginRecords(this.ctrl.selectedId);
    }
  }

  private palette(): ThemePalette {
    return AppTheme.current();
  }

  @Builder
  Footer() {
    if (this.ctrl.loginRecordsLoading) {
      Row() {
        LoadingProgress()
          .width(20)
          .height(20)
          .color(this.palette().primary)
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
      .padding(12)
    } else if (!this.ctrl.loginRecordsHasMore) {
      Text(L10n.t('no_more', '没有更多'))
        .fontSize(13)
        .fontColor(this.palette().hint)
        .width('100%')
        .textAlign(TextAlign.Center)
        .padding(12)
    }
  }

  build() {
    if (this.ctrl.loginRecords.length === 0) {
      Column() {
        EmptyState({
          message: L10n.t('no_data', '暂无数据'),
          imagePath: $rawfile('icons/no_data.png')
        })
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
    } else {
      List({ space: 10 }) {
        ForEach(this.ctrl.loginRecords, (record: LoginRecord) => {
          ListItem() {
            LoginRecordCard({ record: record })
          }
        }, (record: LoginRecord): string =>
          `${record.browser}_${record.deviceInfo}_${record.createTimeRaw}`)
        ListItem() {
          this.Footer()
        }
      }
      .width('100%')
      .height('100%')
      .padding({ left: 12, right: 12, top: 8, bottom: 12 })
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
      .onReachEnd((): void => {
        void this.ctrl.loadMoreLoginRecords();
      })
    }
  }
}
