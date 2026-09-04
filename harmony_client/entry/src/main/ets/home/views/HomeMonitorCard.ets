import { L10n } from '../../core/localization/L10n';

/** 快捷操作卡片：对应 Flutter AppMonitorCard */
@ComponentV2
export struct HomeMonitorCard {
  @Param onTapAction: (action: string) => void = (_action: string) => {
  };

  @Builder
  private ActionTile(icon: Resource, title: string, action: string) {
    Column() {
      Image(icon)
        .width(40)
        .height(40)
        .objectFit(ImageFit.Contain)
      Text(title)
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor(Color.White)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ top: 6 })
    }
    .layoutWeight(1)
    .constraintSize({ minHeight: 88 })
    .padding(6)
    .borderRadius(16)
    .backgroundColor('#E6252528')
    .justifyContent(FlexAlign.Center)
    .onClick(() => {
      this.onTapAction(action);
    })
  }

  build() {
    Row({ space: 12 }) {
      this.ActionTile($r('app.media.home_upload'), L10n.homeQuickUpload, 'upload')
      this.ActionTile($r('app.media.home_download'), L10n.homeDownloadCenter, 'download')
      this.ActionTile($r('app.media.home_album'), L10n.homePhotoBackup, 'photo_backup')
    }
    .width('100%')
    .padding({ left: 16, right: 16, bottom: 12 })
  }
}
