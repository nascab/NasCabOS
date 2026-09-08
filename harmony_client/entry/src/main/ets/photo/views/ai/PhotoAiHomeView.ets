import { L10n } from '../../../core/localization/L10n';
import { AppTheme } from '../../../core/theme/AppTheme';
import { ApiUrls } from '../../../core/network/ApiUrls';
import { NavUtil } from '../../../common/NavUtil';
import { AppRouter } from '../../../router/AppRouter';
import { CurrentUserStore } from '../../../core/user/CurrentUserStore';
import { AppImage } from '../../../common/components/AppImage';
import { GlassCard } from '../../../common/components/GlassCard';
import { EmptyState } from '../../../common/components/EmptyState';
import { AiFaceItem, AiSceneItem } from '../../models/PhotoAiModels';
import { PhotoAiOverviewController } from '../../controllers/PhotoAiOverviewController';
import { PhotoTimelinePageParam } from '../timeline/PhotoTimelinePage';
import { PhotoSettingsPageParam } from '../settings/PhotoSettingsPage';

/**
 * AI 相册主页（对齐 Flutter AppPhotoAiView 移动端）：
 * 人脸/场景预览区（标题行 + 横滑卡片 + 未启用面板）+ 管理员相似照片去重卡，
 * 下拉刷新 + 点击卡片进入对应时间线或列表页。
 */
@ComponentV2
export struct PhotoAiHomeView {
  ctrl: PhotoAiOverviewController = new PhotoAiOverviewController();
  @Local refreshing: boolean = false;

  aboutToAppear(): void {
    this.ctrl.init();
  }

  private isAdmin(): boolean {
    return CurrentUserStore.getInstance().isAdmin;
  }

  private faceDisplayName(face: AiFaceItem): string {
    const name = face.name.trim();
    return name.length > 0 ? name : `(${L10n.t('face_unnamed', '未命名')})`;
  }

  private openFaces(): void {
    NavUtil.push(AppRouter.PHOTO_AI_FACES);
  }

  private openScenes(): void {
    NavUtil.push(AppRouter.PHOTO_AI_SCENES);
  }

  private openSimilar(): void {
    NavUtil.push(AppRouter.PHOTO_AI_SIMILAR);
  }

  /** 打开照片设置页并定位 AI 设置 tab（对齐 Flutter initialTabIndex: 2） */
  private openAiSettings(): void {
    const p = new PhotoSettingsPageParam();
    p.initialTabIndex = 2;
    NavUtil.push(AppRouter.PHOTO_SETTINGS, p);
  }

  private openFaceTimeline(face: AiFaceItem): void {
    const p = new PhotoTimelinePageParam();
    p.title = `${L10n.t('photo_menu_ai_face', '人脸识别')}-${this.faceDisplayName(face)}`;
    p.listType = 'timeline';
    p.faceId = face.faceId;
    NavUtil.push(AppRouter.PHOTO_TIMELINE, p);
  }

  private openSceneTimeline(scene: AiSceneItem): void {
    const name = scene.placeName.trim();
    const displayName = name.length > 0 ? name : L10n.t('scene_unnamed', '未命名场景');
    const p = new PhotoTimelinePageParam();
    p.title = `${L10n.t('photo_menu_ai_scene', '场景识别')}-${displayName}`;
    p.listType = 'timeline';
    p.placeName = scene.placeNameRaw;
    NavUtil.push(AppRouter.PHOTO_TIMELINE, p);
  }

  build() {
    Stack() {
      Refresh({ refreshing: this.refreshing }) {
        if (this.ctrl.overview === undefined && this.ctrl.isLoading) {
          Column() {
            LoadingProgress()
              .width(36)
              .height(36)
              .color(AppTheme.current().primary)
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
        } else {
          Scroll() {
            Column() {
              AiPreviewSection({
                isAdmin: this.isAdmin(),
                title: L10n.t('photo_menu_ai_face', '人脸识别'),
                total: this.ctrl.overview?.faces.total ?? 0,
                isEnabled: this.ctrl.faceEnabled,
                hasData: (this.ctrl.overview?.faces.items.length ?? 0) > 0,
                disabledText: L10n.t('photo_ai_face_disabled', '人脸识别未开启'),
                onOpenAll: (): void => {
                  this.openFaces();
                },
                onEnable: (): void => {
                  this.openAiSettings();
                },
                content: (): void => {
                  this.FacePreviewRow()
                }
              })
              Blank().height(16)
              AiPreviewSection({
                isAdmin: this.isAdmin(),
                title: L10n.t('photo_menu_ai_scene', '场景识别'),
                total: this.ctrl.overview?.scenes.total ?? 0,
                isEnabled: this.ctrl.sceneEnabled,
                hasData: (this.ctrl.overview?.scenes.items.length ?? 0) > 0,
                disabledText: L10n.t('photo_ai_scene_disabled', '场景识别未开启'),
                onOpenAll: (): void => {
                  this.openScenes();
                },
                onEnable: (): void => {
                  this.openAiSettings();
                },
                content: (): void => {
                  this.ScenePreviewRow()
                }
              })
              if (this.isAdmin()) {
                Blank().height(16)
                this.DedupCard()
              }
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
            .padding(16)
          }
          .width('100%')
          .height('100%')
          .scrollBar(BarState.Off)
          .align(Alignment.Top)
        }
      }
      .onRefreshing(() => {
        this.refreshing = true;
        this.ctrl.refreshOverview(true).finally(() => {
          this.refreshing = false;
        });
      })
      .width('100%')
      .height('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor(AppTheme.current().pageBg)
  }

  /** 人脸预览横滑（对齐 Flutter _FacePreviewRow：高 144，卡宽 108） */
  @Builder
  FacePreviewRow() {
    Scroll() {
      Row({ space: 10 }) {
        ForEach(this.ctrl.overview?.faces.items.slice(0, 20) ?? [], (face: AiFaceItem) => {
          this.FacePreviewCard(face)
        }, (face: AiFaceItem) => `face_${face.faceId}`)
      }
      .padding({ top: 2, bottom: 2, left: 2, right: 2 })
      .alignItems(VerticalAlign.Center)
    }
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .width('100%')
    .height(144)
  }

  @Builder
  FacePreviewCard(face: AiFaceItem) {
    Column() {
      // 圆形头像（对齐 Flutter ClipOval + getFaceImageUrl(240,85)）
      Column() {
        FaceAvatar({ faceId: face.faceId, coverHash: face.coverFileHash, avatarSize: 78 })
      }
      .width(78)
      .height(78)
      .borderRadius(39)
      .clip(true)
      .border({
        width: 1,
        color: AppTheme.withAlpha(AppTheme.current().onSurface, 0.06)
      })

      Blank().height(8)
      Text(this.faceDisplayName(face))
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor(AppTheme.current().onSurface)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      if (this.isAdmin()) {
        Blank().height(2)
        Text(L10n.t('total_count', '共 @count 张', L10n.paramsOf('count', `${face.faceCount}`)))
          .fontSize(10)
          .fontColor(AppTheme.withAlpha(AppTheme.current().onSurface, 0.55))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
    }
    .width(108)
    .padding(10)
    .borderRadius(12)
    .backgroundColor(AppTheme.withAlpha(AppTheme.current().surfaceBg, 0.55))
    .border({
      width: 1,
      color: AppTheme.withAlpha(AppTheme.current().onSurface, 0.06)
    })
    .onClick(() => {
      this.openFaceTimeline(face);
    })
  }

  /** 场景预览横滑（对齐 Flutter _ScenePreviewRow：高 172，卡宽 172） */
  @Builder
  ScenePreviewRow() {
    Scroll() {
      Row({ space: 12 }) {
        ForEach(this.ctrl.overview?.scenes.items.slice(0, 20) ?? [], (scene: AiSceneItem) => {
          this.ScenePreviewCard(scene)
        }, (scene: AiSceneItem) => `scene_${scene.placeNameRaw}`)
      }
      .padding({ top: 2, bottom: 2, left: 2, right: 2 })
      .alignItems(VerticalAlign.Top)
    }
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .width('100%')
    .height(172)
  }

  @Builder
  ScenePreviewCard(scene: AiSceneItem) {
    Column() {
      SceneCover({ coverFullpath: scene.coverFullpath })
      Blank().height(8)
      Text(scene.placeName.trim().length > 0 ? scene.placeName : L10n.t('scene_unnamed', '未命名场景'))
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor(AppTheme.current().onSurface)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      if (this.isAdmin()) {
        Blank().height(2)
        Text(L10n.t('total_count', '共 @count 张', L10n.paramsOf('count', `${scene.photoCount}`)))
          .fontSize(10)
          .fontColor(AppTheme.withAlpha(AppTheme.current().onSurface, 0.55))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
    }
    .width(172)
    .alignItems(HorizontalAlign.Start)
    .padding(10)
    .borderRadius(12)
    .backgroundColor(AppTheme.withAlpha(AppTheme.current().surfaceBg, 0.55))
    .border({
      width: 1,
      color: AppTheme.withAlpha(AppTheme.current().onSurface, 0.06)
    })
    .onClick(() => {
      this.openSceneTimeline(scene);
    })
  }

  /** 相似照片去重卡（对齐 Flutter _DedupCard，仅管理员显示） */
  @Builder
  DedupCard() {
    Row() {
      Column() {
        SymbolGlyph($r('sys.symbol.wand_and_stars'))
          .fontSize(24)
          .fontColor([AppTheme.current().primary])
      }
      .width(44)
      .height(44)
      .borderRadius(12)
      .backgroundColor(AppTheme.withAlpha(AppTheme.current().primary, 0.12))
      .justifyContent(FlexAlign.Center)

      Blank().width(12)
      Column({ space: 4 }) {
        Text(L10n.t('photo_menu_ai_similar', '相似照片'))
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppTheme.current().onSurface)
        Text(this.ctrl.similarEnabled
          ? L10n.t('photo_ai_enable_similar_subtitle', '查找并整理相似的照片')
          : L10n.t('photo_dedup_disabled', '照片去重未开启'))
          .fontSize(12)
          .fontColor(AppTheme.withAlpha(AppTheme.current().onSurface, 0.6))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Blank().width(12)
      if (!this.ctrl.similarEnabled) {
        Text(L10n.t('photo_ai_enable_now', '立即开启'))
          .fontSize(13)
          .fontColor(AppTheme.current().primary)
          .padding({ left: 10, right: 10, top: 6, bottom: 6 })
          .borderRadius(10)
          .border({
            width: 1,
            color: AppTheme.current().primary
          })
          .onClick(() => {
            this.openAiSettings();
          })
      } else {
        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(20)
          .fontColor([AppTheme.withAlpha(AppTheme.current().onSurface, 0.55)])
      }
    }
    .width('100%')
    .padding(14)
    .borderRadius(14)
    .backgroundColor(AppTheme.withAlpha(AppTheme.current().surfaceBg, 0.55))
    .border({
      width: 1,
      color: AppTheme.withAlpha(AppTheme.current().onSurface, 0.06)
    })
    .onClick(() => {
      this.openSimilar();
    })
  }
}

/**
 * AI 预览区（对齐 Flutter _PreviewSection）：
 * 标题行（标题 + 管理员总数 + 箭头，可点击进入全部列表）+ 启用内容 / 未启用面板 / 空数据。
 */
@ComponentV2
struct AiPreviewSection {
  @Param isAdmin: boolean = false;
  @Param title: string = '';
  @Param total: number = 0;
  /** 是否启用（避免与组件内置 enabled 属性重名） */
  @Param isEnabled: boolean = true;
  @Param hasData: boolean = false;
  @Param disabledText: string = '';
  @Param onOpenAll: () => void = (): void => {
  };
  @Param onEnable: () => void = (): void => {
  };
  @BuilderParam content: () => void;

  build() {
    Column() {
      // 标题行（对齐 Flutter InkWell + Row：enabled 时可点击）
      Row() {
        Text(this.title)
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppTheme.current().onSurface)
        if (this.isAdmin) {
          Blank().width(10)
          Text(L10n.t('folder_status_total', '共 @total 个', L10n.paramsOf('total', `${this.total}`)))
            .fontSize(12)
            .fontColor(AppTheme.withAlpha(AppTheme.current().onSurface, 0.55))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
        }
        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(18)
          .fontColor([AppTheme.withAlpha(AppTheme.current().onSurface, 0.55)])
      }
      .width('100%')
      .padding({ top: 6, bottom: 6 })
      .onClick(() => {
        if (this.isEnabled) {
          this.onOpenAll();
        }
      })

      Blank().height(8)
      if (!this.isEnabled) {
        // 未启用面板（对齐 Flutter _DisabledPanel）
        Row() {
          Text(this.disabledText)
            .fontSize(14)
            .fontColor(AppTheme.withAlpha(AppTheme.current().onSurface, 0.75))
            .layoutWeight(1)
          Blank().width(12)
          // 立即开启（对齐 Flutter CustomOutlinedButton + settings 图标）
          Row({ space: 6 }) {
            SymbolGlyph($r('sys.symbol.gearshape'))
              .fontSize(15)
              .fontColor([AppTheme.current().primary])
            Text(L10n.t('photo_ai_enable_now', '立即开启'))
              .fontSize(13)
              .fontColor(AppTheme.current().primary)
          }
          .padding({ left: 12, right: 12, top: 8, bottom: 8 })
          .borderRadius(10)
          .border({
            width: 1,
            color: AppTheme.withAlpha(AppTheme.current().primary, 0.6)
          })
          .onClick(() => {
            this.onEnable();
          })
        }
        .width('100%')
        .padding(14)
        .borderRadius(12)
        .backgroundColor(AppTheme.current().surfaceBg)
        .border({
          width: 1,
          color: AppTheme.withAlpha(AppTheme.current().onSurface, 0.06)
        })
        .alignItems(VerticalAlign.Center)
      } else if (this.hasData) {
        this.content()
      } else {
        // 空数据（对齐 Flutter SizedBox(120) + CustomNoData）
        Column() {
          EmptyState({ message: L10n.t('no_data', '暂无数据'), iconSize: 100 })
        }
        .width('100%')
        .height(120)
        .borderRadius(12)
        .clip(true)
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}

/**
 * 人脸圆形头像（异步 getFaceImageUrl，对齐 Flutter CustomExtendedImage 用法）
 */
@ComponentV2
struct FaceAvatar {
  @Param faceId: number = 0;
  @Param coverHash: string = '';
  /** 头像尺寸（避免与组件内置 size 属性重名） */
  @Param avatarSize: number = 78;
  @Local url: string = '';

  aboutToAppear(): void {
    this.resolve();
  }

  @Monitor('faceId')
  onFaceChange(): void {
    this.resolve();
  }

  private resolve(): void {
    ApiUrls.getFaceImageUrl(this.faceId, 240, 85, this.coverHash).then((u: string) => {
      this.url = u;
    }).catch(() => {
    });
  }

  build() {
    if (this.url.length > 0) {
      AppImage({ url: this.url })
        .width(this.avatarSize)
        .height(this.avatarSize)
    } else {
      Column() {
        SymbolGlyph($r('sys.symbol.person'))
          .fontSize(this.avatarSize * 0.4)
          .fontColor([AppTheme.withAlpha(AppTheme.current().onSurface, 0.35)])
      }
      .width(this.avatarSize)
      .height(this.avatarSize)
      .justifyContent(FlexAlign.Center)
    }
  }
}

/**
 * 场景封面（异步 getTinyUrl，对齐 Flutter CustomExtendedImage 用法）
 */
@ComponentV2
struct SceneCover {
  @Param coverFullpath: string = '';
  @Local url: string = '';

  aboutToAppear(): void {
    this.resolve();
  }

  @Monitor('coverFullpath')
  onPathChange(): void {
    this.resolve();
  }

  private resolve(): void {
    const fp = this.coverFullpath;
    if (fp.trim().length === 0) {
      this.url = '';
      return;
    }
    ApiUrls.getTinyUrl(fp).then((u: string) => {
      if (fp === this.coverFullpath) {
        this.url = u;
      }
    }).catch(() => {
    });
  }

  build() {
    Stack() {
      if (this.url.length > 0) {
        AppImage({ url: this.url })
      } else {
        Column() {
          SymbolGlyph($r('sys.symbol.picture'))
            .fontSize(40)
            .fontColor([AppTheme.withAlpha(AppTheme.current().onSurface, 0.55)])
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .backgroundColor(AppTheme.current().inputFill)
      }
    }
    .width(152)
    .height(104)
    .borderRadius(12)
    .clip(true)
  }
}
