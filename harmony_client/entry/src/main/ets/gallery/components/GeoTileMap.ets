import { APIClient } from '../../core/network/APIClient';

/**
 * 通用轻量瓦片地图（信息面板位置展示，对齐 Flutter flutter_map 用法）：
 * 服务端瓦片 /api/mapApi/tile?zoom=&x=&y=&accessToken=，
 * 3x3 瓦片网格 + 红色定位标记，单指拖动平移、双指捏合缩放（zoom 3-18，默认 10）。
 */
@ComponentV2
export struct GeoTileMap {
  @Param lat: number = 0;
  @Param lng: number = 0;

  @Local zoom: number = 10;
  @Local centerLat: number = 0;
  @Local centerLng: number = 0;
  @Local tilePx: number = 256;
  private panStartLat: number = 0;
  private panStartLng: number = 0;
  private panStartX: number = 0;
  private panStartY: number = 0;
  private pinchBase: number = 10;

  aboutToAppear(): void {
    this.centerLat = this.lat;
    this.centerLng = this.lng;
  }

  /** Web Mercator：纬度 → y 瓦片坐标（浮点） */
  private static latToY(lat: number, zoom: number): number {
    const clamped = Math.min(Math.max(lat, -85.05112878), 85.05112878);
    const rad = clamped * Math.PI / 180;
    const n = Math.pow(2, zoom);
    return (1 - Math.log(Math.tan(rad) + 1 / Math.cos(rad)) / Math.PI) / 2 * n;
  }

  private static lngToX(lng: number, zoom: number): number {
    const n = Math.pow(2, zoom);
    return (lng + 180) / 360 * n;
  }

  private static yToLat(y: number, zoom: number): number {
    const n = Math.pow(2, zoom);
    const ty = y / n;
    return Math.atan(Math.sinh(Math.PI * (1 - 2 * ty))) * 180 / Math.PI;
  }

  private static xToLng(x: number, zoom: number): number {
    const n = Math.pow(2, zoom);
    return x / n * 360 - 180;
  }

  /** 中心点对应的浮点瓦片坐标 */
  private centerX(): number {
    return GeoTileMap.lngToX(this.centerLng, this.zoom);
  }

  private centerY(): number {
    return GeoTileMap.latToY(this.centerLat, this.zoom);
  }

  private tileUrl(x: number, y: number): string {
    const api = APIClient.getInstance();
    const base = api.state.baseUrl;
    const token = api.state.accessToken ?? '';
    const max = Math.pow(2, this.zoom);
    const tx = ((Math.floor(x) % max) + max) % max;
    const ty = Math.min(Math.max(Math.floor(y), 0), max - 1);
    let url = `${base}/api/mapApi/tile?zoom=${this.zoom}&x=${tx}&y=${ty}`;
    if (token.length > 0) {
      url += `&accessToken=${encodeURIComponent(token)}`;
    }
    return url;
  }

  private onPanStart(e: GestureEvent): void {
    this.panStartX = e.offsetX;
    this.panStartY = e.offsetY;
    this.panStartLat = this.centerLat;
    this.panStartLng = this.centerLng;
  }

  private onPanUpdate(e: GestureEvent): void {
    const dx = e.offsetX - this.panStartX;
    const dy = e.offsetY - this.panStartY;
    const pxPerTile = this.tilePx;
    const nx = GeoTileMap.lngToX(this.panStartLng, this.zoom) - dx / pxPerTile;
    const ny = GeoTileMap.latToY(this.panStartLat, this.zoom) - dy / pxPerTile;
    this.centerLng = GeoTileMap.xToLng(nx, this.zoom);
    this.centerLat = GeoTileMap.yToLat(ny, this.zoom);
  }

  private onPinchUpdate(e: GestureEvent): void {
    const target = Math.round(this.pinchBase + Math.log2(Math.max(e.scale, 0.2)));
    this.zoom = Math.min(Math.max(target, 3), 18);
  }

  /** 标记相对视图中心的像素偏移 */
  private markerOffsetX(): number {
    return (GeoTileMap.lngToX(this.lat, this.zoom) - this.centerX()) * this.tilePx;
  }

  private markerOffsetY(): number {
    return (GeoTileMap.latToY(this.lat, this.zoom) - this.centerY()) * this.tilePx;
  }

  build() {
    Stack() {
      // 3x3 瓦片网格（以中心瓦片为锚，覆盖视口；子瓦片级定位用整体平移）
      Grid() {
        ForEach([-1, 0, 1], (gy: number) => {
          ForEach([-1, 0, 1], (gx: number) => {
            GridItem() {
              Stack() {
                Image(this.tileUrl(this.centerX() + gx, this.centerY() + gy))
                  .width(this.tilePx + 1)
                  .height(this.tilePx + 1)
                  .objectFit(ImageFit.Fill)
                  .draggable(false)
                  .interpolation(ImageInterpolation.Medium)
              }
              .width(this.tilePx + 1)
              .height(this.tilePx + 1)
              .backgroundColor('#1E2A32')
            }
          }, (gx: number): string => `${gx}`)
        }, (gy: number): string => `${gy}`)
      }
      .columnsTemplate('1fr 1fr 1fr')
      .rowsTemplate('1fr 1fr 1fr')
      .width(3 * this.tilePx)
      .height(3 * this.tilePx)
      .scrollBar(BarState.Off)
      .enabled(false)
      .translate({
        // 中心瓦片锚定视口中心：浮点偏移部分向反方向平移（误差 0~0.5 瓦片）
        x: (Math.floor(this.centerX()) + 0.5 - this.centerX()) * this.tilePx,
        y: (Math.floor(this.centerY()) + 0.5 - this.centerY()) * this.tilePx
      })

      // 红色定位标记（相对视图中心的瓦片像素偏移，对齐 Flutter Icons.location_on 36）
      SymbolGlyph($r('sys.symbol.pin_fill'))
        .fontSize(36)
        .fontColor(['#F44336'])
        .translate({ x: this.markerOffsetX(), y: this.markerOffsetY() })
    }
    .width('100%')
    .height('100%')
    .clip(true)
    .backgroundColor('#141C22')
    .gesture(GestureGroup(GestureMode.Parallel,
      PanGesture({ fingers: 1, direction: PanDirection.All, distance: 3 })
        .onActionStart((e: GestureEvent): void => {
          this.onPanStart(e);
        })
        .onActionUpdate((e: GestureEvent): void => {
          this.onPanUpdate(e);
        }),
      PinchGesture({ fingers: 2 })
        .onActionStart((_e: GestureEvent): void => {
          this.pinchBase = this.zoom;
        })
        .onActionUpdate((e: GestureEvent): void => {
          this.onPinchUpdate(e);
        })
    ))
  }
}
