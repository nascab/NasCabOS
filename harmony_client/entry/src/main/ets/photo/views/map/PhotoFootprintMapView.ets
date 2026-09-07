import { L10n } from '../../../core/localization/L10n';
import { AppTheme } from '../../../core/theme/AppTheme';
import { APIClient } from '../../../core/network/APIClient';
import { ApiUrls } from '../../../core/network/ApiUrls';
import { NavUtil } from '../../../common/NavUtil';
import { AppRouter } from '../../../router/AppRouter';
import { ToastUtil } from '../../../common/ToastUtil';
import { SheetHandle, SheetParamsBase, SheetUtil } from '../../../common/SheetUtil';
import { PhotoMapIndexItem, PhotoMapTileServer } from '../../models/PhotoMapModels';
import { MapBounds, PhotoFootprintMapController } from '../../controllers/PhotoFootprintMapController';
import { LatLang } from '../../utils/CoordinateTransform';
import { LocalPlaybackProxy } from '../../../p2p/LocalPlaybackProxy';
import { PhotoTimelinePageParam } from '../timeline/PhotoTimelinePage';

// ===== Web Mercator 投影工具 =====

const TILE_SIZE = 256;
const MIN_LAT = -85.05112878;
const MAX_LAT = 85.05112878;

class MapProjection {
  /** 世界像素宽（连续 zoom） */
  static worldSize(zoom: number): number {
    return TILE_SIZE * Math.pow(2, zoom);
  }

  static lngToWorldX(lng: number, zoom: number): number {
    return (lng + 180) / 360 * MapProjection.worldSize(zoom);
  }

  static latToWorldY(lat: number, zoom: number): number {
    const clamped = Math.min(Math.max(lat, MIN_LAT), MAX_LAT);
    const s = Math.sin(clamped * Math.PI / 180);
    const y = 0.5 - Math.log((1 + s) / (1 - s)) / (4 * Math.PI);
    return y * MapProjection.worldSize(zoom);
  }

  static worldXToLng(x: number, zoom: number): number {
    return x / MapProjection.worldSize(zoom) * 360 - 180;
  }

  static worldYToLat(y: number, zoom: number): number {
    const n = Math.PI * (1 - 2 * y / MapProjection.worldSize(zoom));
    return Math.atan(Math.sinh(n)) * 180 / Math.PI;
  }
}

/** 可渲染瓦片信息 */
class TileRenderInfo {
  x: number = 0;
  y: number = 0;
  zoomInt: number = 0;
  left: number = 0;
  top: number = 0;
  size: number = TILE_SIZE;

  key(): string {
    return `t_${this.zoomInt}_${this.x}_${this.y}`;
  }
}

/** 可渲染标注信息 */
class MarkerRenderInfo {
  item: PhotoMapIndexItem = new PhotoMapIndexItem();
  position: LatLang = new LatLang(0, 0);
  left: number = 0;
  top: number = 0;
  size: number = 0;
}

/** 可视范围内瓦片（对齐 Flutter TileLayer 的 urlTemplate 逐瓦片加载） */
function computeVisibleTiles(center: LatLang, zoom: number, viewWidth: number, viewHeight: number): TileRenderInfo[] {
  const tiles: TileRenderInfo[] = [];
  if (viewWidth <= 0 || viewHeight <= 0) {
    return tiles;
  }
  const zoomInt = Math.floor(zoom);
  const scale = Math.pow(2, zoom - zoomInt);
  const maxIndex = Math.pow(2, zoomInt);
  // 中心在 zoomInt 级的世界像素
  const cx = MapProjection.lngToWorldX(center.longitude, zoomInt);
  const cy = MapProjection.latToWorldY(center.latitude, zoomInt);
  // 视口左上角（zoomInt 像素）
  const topLeftX = cx - viewWidth / 2 / scale;
  const topLeftY = cy - viewHeight / 2 / scale;
  const tileScreen = TILE_SIZE * scale;
  const xStart = Math.floor(topLeftX / TILE_SIZE);
  const yStart = Math.floor(topLeftY / TILE_SIZE);
  const xEnd = Math.floor((topLeftX + viewWidth / scale) / TILE_SIZE);
  const yEnd = Math.floor((topLeftY + viewHeight / scale) / TILE_SIZE);
  for (let x = xStart; x <= xEnd; x++) {
    for (let y = yStart; y <= yEnd; y++) {
      // 越界经度环绕（对齐地图服务行为），纬度越界跳过
      const wrappedX = ((x % maxIndex) + maxIndex) % maxIndex;
      if (y < 0 || y >= maxIndex) {
        continue;
      }
      const info = new TileRenderInfo();
      info.x = wrappedX;
      info.y = y;
      info.zoomInt = zoomInt;
      info.left = (x * TILE_SIZE - topLeftX) * scale;
      info.top = (y * TILE_SIZE - topLeftY) * scale;
      info.size = tileScreen;
      tiles.push(info);
    }
  }
  return tiles;
}

/** 可视范围（地图坐标系，对齐 Flutter camera.visibleBounds） */
function computeVisibleBounds(center: LatLang, zoom: number, viewWidth: number, viewHeight: number): MapBounds {
  const cx = MapProjection.lngToWorldX(center.longitude, zoom);
  const cy = MapProjection.latToWorldY(center.latitude, zoom);
  const halfW = viewWidth / 2;
  const halfH = viewHeight / 2;
  const b = new MapBounds();
  b.southLng = MapProjection.worldXToLng(cx - halfW, zoom);
  b.northLng = MapProjection.worldXToLng(cx + halfW, zoom);
  b.southLat = MapProjection.worldYToLat(cy + halfH, zoom);
  b.northLat = MapProjection.worldYToLat(cy - halfH, zoom);
  return b;
}

/** 标注尺寸（对齐 Flutter _markerSizeForCount：数量越多越小形成聚合观感） */
function markerSizeForCount(count: number, zoom: number): number {
  const minSize = 35.0;
  let maxSize = 85.0;
  const minCountForMax = 5;
  const maxCountForMin = 200;
  if (zoom < 5.0) {
    maxSize = 40.0;
  }
  if (zoom < 7.0) {
    maxSize = 60.0;
  }
  if (zoom < 8.0) {
    maxSize = 70.0;
  }
  if (count <= minCountForMax) {
    return maxSize;
  }
  if (count >= maxCountForMin) {
    return minSize;
  }
  const t = (count - minCountForMax) / (maxCountForMin - minCountForMax);
  const size = maxSize + (minSize - maxSize) * t;
  return Math.min(Math.max(size, minSize), maxSize);
}

/** 可渲染标注（屏幕坐标 + 尺寸，超出视口的剔除） */
function computeMarkers(ctrl: PhotoFootprintMapController, viewWidth: number, viewHeight: number): MarkerRenderInfo[] {
  const result: MarkerRenderInfo[] = [];
  if (viewWidth <= 0 || viewHeight <= 0) {
    return result;
  }
  const zoom = ctrl.zoom;
  const cx = MapProjection.lngToWorldX(ctrl.center.longitude, zoom);
  const cy = MapProjection.latToWorldY(ctrl.center.latitude, zoom);
  const size = markerSizeForCount(ctrl.items.length, zoom);
  const margin = size + 8;
  for (const item of ctrl.items) {
    const p = ctrl.markerPosition(item);
    const px = MapProjection.lngToWorldX(p.longitude, zoom);
    const py = MapProjection.latToWorldY(p.latitude, zoom);
    const left = viewWidth / 2 + (px - cx);
    const top = viewHeight / 2 + (py - cy);
    if (left < -margin || left > viewWidth + margin || top < -margin || top > viewHeight + margin) {
      continue;
    }
    const info = new MarkerRenderInfo();
    info.item = item;
    info.position = p;
    info.left = left;
    info.top = top;
    info.size = size;
    result.push(info);
  }
  return result;
}

// ===== 切换瓦片服务器弹层（对齐 Flutter _openSwitchMapDialog AlertDialog） =====

class SwitchMapSheetParams extends SheetParamsBase {
  ctrl: PhotoFootprintMapController = new PhotoFootprintMapController();
  onPicked: (server: PhotoMapTileServer) => void = (_s: PhotoMapTileServer): void => {
  };
}

@Builder
function SwitchMapSheetContent(p: SwitchMapSheetParams) {
  Column() {
    SheetHandle()
    Text(L10n.t('photo_map_switch_title', '切换地图'))
      .fontSize(16)
      .fontWeight(FontWeight.Medium)
      .fontColor(AppTheme.current().onSurface)
      .padding({ top: 4, bottom: 8 })
    if (p.ctrl.tileServerList.length === 0) {
      Text(L10n.t('no_data', '暂无数据'))
        .fontSize(14)
        .fontColor(AppTheme.withAlpha(AppTheme.current().onSurface, 0.6))
        .padding({ top: 24, bottom: 24 })
    } else {
      List() {
        ForEach(p.ctrl.tileServerList, (s: PhotoMapTileServer) => {
          ListItem() {
            Row() {
              Column({ space: 3 }) {
                Text(s.name)
                  .fontSize(15)
                  .fontColor(AppTheme.current().onSurface)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                Text(`${s.coordinate}  ${L10n.t('zoom_level', '缩放级别')}:${s.maxLevel}`)
                  .fontSize(12)
                  .fontColor(AppTheme.withAlpha(AppTheme.current().onSurface, 0.55))
                  .maxLines(1)
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)

              if (s.isCurrent) {
                SymbolGlyph($r('sys.symbol.checkmark'))
                  .fontSize(18)
                  .fontColor([AppTheme.current().primary])
              }
            }
            .width('100%')
            .height(56)
            .padding({ left: 16, right: 16 })
            .onClick(() => {
              p.onPicked(s);
            })
          }
        }, (s: PhotoMapTileServer) => `${s.server}_${s.name}`)
      }
      .width('100%')
      .height(Math.min(p.ctrl.tileServerList.length, 6) * 56)
      .divider({
        strokeWidth: 1,
        color: AppTheme.current().divider,
        startMargin: 16,
        endMargin: 16
      })
    }
    // 取消按钮（对齐 Flutter AlertDialog actions cancel）
    Text(L10n.cancel)
      .fontSize(15)
      .fontColor(AppTheme.current().primary)
      .height(44)
      .padding({ left: 16, right: 16 })
      .onClick(() => {
        p.close();
      })
    Blank().height(16)
  }
  .width('100%')
  .borderRadius({ topLeft: 16, topRight: 16 })
  .backgroundColor(AppTheme.current().surfaceBg)
}

// ===== 照片标注（对齐 Flutter _markerFor：白色圆角卡片 + 缩略图/占位 + 日期条） =====

@ComponentV2
struct MapMarker {
  @Param item: PhotoMapIndexItem = new PhotoMapIndexItem();
  @Param markerSize: number = 48;
  @Local url: string = '';
  @Param onTap: (item: PhotoMapIndexItem) => void = (_i: PhotoMapIndexItem): void => {
  };

  aboutToAppear(): void {
    this.resolve();
  }

  @Monitor('item')
  onItemChange(): void {
    this.resolve();
  }

  private resolve(): void {
    const fullpath = this.item.fullpath;
    if (fullpath.length === 0) {
      return;
    }
    ApiUrls.getTinyUrl(fullpath).then((u: string) => {
      this.url = u;
    }).catch(() => {
    });
  }

  /** 日期条文案（对齐 Flutter _formatYearMonth：yyyy/M） */
  private dateLabel(): string {
    const d = new Date(this.item.originalTime);
    return `${d.getFullYear()}/${d.getMonth() + 1}`;
  }

  build() {
    Column() {
      Stack() {
        if (this.url.length > 0) {
          Image(this.url)
            .width('100%')
            .height('100%')
            .objectFit(ImageFit.Cover)
            .draggable(false)
        } else {
          Column() {
            SymbolGlyph($r('sys.symbol.picture'))
              .fontSize(this.fallbackIconSize())
              .fontColor([AppTheme.current().primary])
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
          .backgroundColor(AppTheme.withAlpha(AppTheme.current().primary, 0.12))
        }
        if (this.item.originalTime > 0) {
          Text(this.dateLabel())
            .fontSize(this.barFontSize())
            .fontWeight(FontWeight.Medium)
            .fontColor('#FFFFFF')
            .maxLines(1)
            .textAlign(TextAlign.Center)
            .width('100%')
            .height(this.barHeight())
            .backgroundColor('#80000000')
        }
      }
      .width('100%')
      .height('100%')
      .borderRadius(this.innerRadius())
      .clip(true)
      .alignContent(Alignment.Bottom)
    }
    .width(this.markerSize)
    .height(this.markerSize)
    .borderRadius(this.outerRadius())
    .border({
      width: 2,
      color: '#FFFFFF'
    })
    .onClick(() => {
      this.onTap(this.item);
    })
  }

  private outerRadius(): number {
    return Math.min(Math.max(this.markerSize * 0.2, 6.0), 14.0);
  }

  private innerRadius(): number {
    return Math.min(Math.max(this.outerRadius() - 2, 4.0), 12.0);
  }

  private fallbackIconSize(): number {
    return Math.min(Math.max(this.markerSize * 0.35, 16.0), 26.0);
  }

  private barHeight(): number {
    return Math.min(Math.max(this.markerSize * 0.24, 10.0), 18.0);
  }

  private barFontSize(): number {
    return Math.min(Math.max(this.markerSize * 0.16, 8.0), 13.0);
  }
}

/** 缩略图 URL 解析见 MapMarker.resolve（复用 ApiUrls.getTinyUrl） */

// ===== 足迹地图视图（对齐 Flutter PhotoFootprintMapView） =====

@ComponentV2
export struct PhotoFootprintMapView {
  ctrl: PhotoFootprintMapController = new PhotoFootprintMapController();
  @Local viewWidth: number = 0;
  @Local viewHeight: number = 0;
  /** 瓦片请求基地址（P2P 模式走本地代理，对齐 Flutter LocalWebAssetServer） */
  @Local tileBaseUrl: string = '';
  private initialFetchDone: boolean = false;
  private panStartCenter: LatLang = new LatLang(0, 0);
  private pinchStartZoom: number = 0;

  aboutToAppear(): void {
    this.ctrl.init();
    // P2P 模式：启动本地代理供瓦片请求（对齐 Flutter isP2p 时 acquire LocalWebAssetServer）
    if (APIClient.getInstance().isP2pMode) {
      LocalPlaybackProxy.getInstance().start().then(() => {
        this.tileBaseUrl = LocalPlaybackProxy.getInstance().getBaseUrl() ?? '';
      }).catch(() => {
      });
    } else {
      this.tileBaseUrl = APIClient.getInstance().state.baseUrl;
    }
  }

  aboutToDisappear(): void {
    this.ctrl.dispose();
  }

  private minZoom(): number {
    return this.ctrl.zoomInfo !== undefined ? this.ctrl.zoomInfo.minZoom : 3.0;
  }

  private maxZoom(): number {
    return this.ctrl.zoomInfo !== undefined ? this.ctrl.zoomInfo.maxZoom : 18.0;
  }

  private clampZoom(z: number): number {
    return Math.min(Math.max(z, this.minZoom()), this.maxZoom());
  }

  /** 视角变化上报（对齐 Flutter onPositionChanged 回调路径） */
  private notifyMapChanged(): void {
    this.ctrl.onMapChanged(
      computeVisibleBounds(this.ctrl.center, this.ctrl.zoom, this.viewWidth, this.viewHeight),
      this.ctrl.zoom,
      this.ctrl.center
    );
  }

  private tileUrl(info: TileRenderInfo): string {
    const token = APIClient.getInstance().state.accessToken ?? '';
    let url = `${this.tileBaseUrl}/api/mapApi/tile?zoom=${info.zoomInt}&x=${info.x}&y=${info.y}&seed=${this.ctrl.mapRebuildSeed}`;
    if (token.length > 0) {
      url += `&accessToken=${encodeURIComponent(token)}`;
    }
    return url;
  }

  /** 打开附近时间线（对齐 Flutter _openMarkerDetail：移动端 push 页面） */
  private openNearbyTimeline(item: PhotoMapIndexItem): void {
    void this.ctrl.getLocationName(item.geohash).then((geoName: string) => {
      const title = `${L10n.t('location', '位置')}-${geoName.length > 0 ? geoName : L10n.t('photo_map_location', '地图位置')}`;
      const p = new PhotoTimelinePageParam();
      p.title = title;
      p.listType = 'timeline';
      p.geohash = item.geohash;
      NavUtil.push(AppRouter.PHOTO_TIMELINE, p);
    });
  }

  /** 打开切换地图弹层（对齐 Flutter _openSwitchMapDialog） */
  private openSwitchMapSheet(): void {
    void this.ctrl.refreshTileServerList().then(() => {
      const p = new SwitchMapSheetParams();
      p.ctrl = this.ctrl;
      p.onPicked = (s: PhotoMapTileServer): void => {
        p.close();
        void this.ctrl.switchTileServer(s).then((ok: boolean) => {
          if (ok) {
            this.notifyMapChanged();
          } else {
            ToastUtil.show(L10n.t('operation_failed', '操作失败'));
          }
        });
      };
      SheetUtil.present(p, wrapBuilder(SwitchMapSheetContent));
    });
  }

  build() {
    Stack() {
      // 地图层（瓦片 + 标注）
      Stack() {
        ForEach(this.visibleTiles(), (info: TileRenderInfo) => {
          Image(this.tileUrl(info))
            .width(info.size)
            .height(info.size)
            .position({ x: info.left, y: info.top })
            .backgroundColor('#D9D9D9')
            .draggable(false)
            .interpolation(ImageInterpolation.Medium)
        }, (info: TileRenderInfo) => `${this.ctrl.mapRebuildSeed}_${info.key()}`)

        ForEach(this.visibleMarkers(), (info: MarkerRenderInfo) => {
          Column() {
            MapMarker({
              item: info.item,
              markerSize: info.size,
              onTap: (item: PhotoMapIndexItem): void => {
                this.openNearbyTimeline(item);
              }
            })
          }
          .position({ x: info.left - info.size / 2, y: info.top - info.size / 2 })
        }, (info: MarkerRenderInfo) => `m_${info.item.id}_${Math.round(info.left)}_${Math.round(info.top)}`)
      }
      .width('100%')
      .height('100%')
      .clip(true)
      .backgroundColor(AppTheme.current().pageBg)
      .onAreaChange((_o: Area, n: Area) => {
        this.viewWidth = Number(n.width);
        this.viewHeight = Number(n.height);
        if (!this.initialFetchDone && this.viewWidth > 0) {
          // 首次布局完成后触发初始拉取（对齐 Flutter _scheduleInitialFetch）
          this.initialFetchDone = true;
          this.notifyMapChanged();
        }
      })
      .gesture(GestureGroup(GestureMode.Parallel,
        PanGesture({ fingers: 1 })
          .onActionStart((_e: GestureEvent) => {
            this.panStartCenter = new LatLang(this.ctrl.center.latitude, this.ctrl.center.longitude);
          })
          .onActionUpdate((e: GestureEvent) => {
            const z = this.ctrl.zoom;
            const wx = MapProjection.lngToWorldX(this.panStartCenter.longitude, z) - e.offsetX;
            const wy = MapProjection.latToWorldY(this.panStartCenter.latitude, z) - e.offsetY;
            this.ctrl.center = new LatLang(
              MapProjection.worldYToLat(wy, z),
              MapProjection.worldXToLng(wx, z)
            );
          })
          .onActionEnd((_e: GestureEvent) => {
            this.notifyMapChanged();
          }),
        PinchGesture()
          .onActionStart((_e: GestureEvent) => {
            this.pinchStartZoom = this.ctrl.zoom;
          })
          .onActionUpdate((e: GestureEvent) => {
            if (e.scale > 0) {
              this.ctrl.zoom = this.clampZoom(this.pinchStartZoom + Math.log2(e.scale));
            }
          })
          .onActionEnd((_e: GestureEvent) => {
            this.notifyMapChanged();
          })
      ))

      // 顶部渐变遮罩（对齐 Flutter 顶部 40 高黑色渐变）
      Column()
        .width('100%')
        .height(40)
        .linearGradient({
          angle: 180,
          colors: [['#73000000', 0], ['#00000000', 1]]
        })
        .hitTestBehavior(HitTestMode.None)
        .align(Alignment.Top)

      // 切换地图按钮（对齐 Flutter _FloatingSwitchMapButton）
      Row({ space: 6 }) {
        SymbolGlyph($r('sys.symbol.rectangle_stack'))
          .fontSize(16)
          .fontColor([AppTheme.current().onSurface])
        Text(L10n.t('photo_map_switch', '切换地图'))
          .fontSize(14)
          .fontColor(AppTheme.current().onSurface)
      }
      .padding({ left: 10, right: 10, top: 8, bottom: 8 })
      .borderRadius(12)
      .backgroundColor(AppTheme.withAlpha(AppTheme.current().surfaceBg, 0.7))
      .onClick(() => {
        this.openSwitchMapSheet();
      })
      .position({ x: this.viewWidth - this.switchButtonWidth(), y: 10 })

      // 缩放级别徽标（对齐 Flutter _InfoBadge 左下）
      Text(`${L10n.t('zoom_level', '缩放级别')}: ${this.ctrl.zoom.toFixed(1)}`)
        .fontSize(12)
        .fontColor(AppTheme.current().onSurface)
        .padding({ left: 10, right: 10, top: 6, bottom: 6 })
        .borderRadius(10)
        .backgroundColor(AppTheme.withAlpha(AppTheme.current().surfaceBg, 0.92))
        .border({ width: 1, color: AppTheme.current().divider })
        .position({ x: 12, y: this.viewHeight - 50 })

      // 缩放按钮（对齐 Flutter _MapZoomButtons 右下）
      Row() {
        SymbolGlyph($r('sys.symbol.minus'))
          .fontSize(18)
          .fontColor([this.ctrl.zoom > this.minZoom() ? AppTheme.current().onSurface : AppTheme.current().hint])
          .padding({ left: 10, right: 10, top: 8, bottom: 8 })
          .onClick(() => {
            if (this.ctrl.zoom > this.minZoom()) {
              this.ctrl.zoom = this.clampZoom(this.ctrl.zoom - 1);
              this.notifyMapChanged();
            }
          })
        SymbolGlyph($r('sys.symbol.plus'))
          .fontSize(18)
          .fontColor([this.ctrl.zoom < this.maxZoom() ? AppTheme.current().onSurface : AppTheme.current().hint])
          .padding({ left: 10, right: 10, top: 8, bottom: 8 })
          .onClick(() => {
            if (this.ctrl.zoom < this.maxZoom()) {
              this.ctrl.zoom = this.clampZoom(this.ctrl.zoom + 1);
              this.notifyMapChanged();
            }
          })
      }
      .borderRadius(10)
      .backgroundColor(AppTheme.withAlpha(AppTheme.current().surfaceBg, 0.92))
      .border({ width: 1, color: AppTheme.current().divider })
      .position({ x: this.viewWidth - this.zoomButtonsWidth(), y: this.viewHeight - 56 })

      // 加载中（对齐 Flutter Positioned.fill CircularProgressIndicator）
      if (this.ctrl.loading) {
        Column() {
          LoadingProgress()
            .width(36)
            .height(36)
            .color(AppTheme.current().primary)
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .hitTestBehavior(HitTestMode.None)
      }

      // 错误徽标（对齐 Flutter errorText _InfoBadge）
      if (this.ctrl.errorText.length > 0) {
        Text(this.ctrl.errorText)
          .fontSize(12)
          .fontColor(AppTheme.current().onSurface)
          .maxLines(2)
          .padding({ left: 10, right: 10, top: 6, bottom: 6 })
          .borderRadius(10)
          .backgroundColor(AppTheme.withAlpha(AppTheme.current().surfaceBg, 0.92))
          .border({ width: 1, color: AppTheme.current().divider })
          .position({
            x: 12,
            y: this.viewHeight - 96
          })
          .constraintSize({ maxWidth: this.viewWidth - 24 })
      }
    }
    .width('100%')
    .height('100%')
    .clip(true)
  }

  private visibleTiles(): TileRenderInfo[] {
    return computeVisibleTiles(this.ctrl.center, this.ctrl.zoom, this.viewWidth, this.viewHeight);
  }

  private visibleMarkers(): MarkerRenderInfo[] {
    return computeMarkers(this.ctrl, this.viewWidth, this.viewHeight);
  }

  private switchButtonWidth(): number {
    // 估算：图标16 + 间距6 + 文本宽度约 4 字符 * 14 + 左右 padding 20
    const textWidth = L10n.t('photo_map_switch', '切换地图').length * 14;
    return 16 + 6 + textWidth + 20 + 12;
  }

  private zoomButtonsWidth(): number {
    return 38 + 38 + 12;
  }
}
