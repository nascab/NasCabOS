import { PreferencesStore } from '../../core/storage/PreferencesStore';
import { LatLang, CoordinateTransform } from '../utils/CoordinateTransform';
import { PhotoMapIndexItem, PhotoMapTileServer, PhotoMapZoomInfo } from '../models/PhotoMapModels';
import { PhotoMapApiService } from '../service/PhotoMapApiService';

/** 可视范围（WGS-84，对齐 Flutter fm.LatLngBounds 的 SW/NE） */
export class MapBounds {
  southLat: number = 0;
  southLng: number = 0;
  northLat: number = 0;
  northLng: number = 0;
}

/** 地图状态持久化键（对齐 Flutter CacheKeys.photoFootprintMapState） */
const MAP_STATE_KEY = 'photo_footprint_map_state';
/** 防抖毫秒（对齐 Flutter 650ms） */
const FETCH_DEBOUNCE_MS = 650;

/**
 * 足迹地图控制器（对齐 Flutter PhotoFootprintMapController）：
 * 加载缩放范围/瓦片服务器、按可视范围防抖拉取照片、切换瓦片服务器、持久化视角。
 */
@ObservedV2
export class PhotoFootprintMapController {
  private api: PhotoMapApiService = new PhotoMapApiService();
  private debounceTimerId: number = -1;
  private lastFetchedBounds: MapBounds | undefined = undefined;
  private lastFetchedZoom: number = -1;

  @Trace loading: boolean = false;
  @Trace errorText: string = '';
  @Trace zoomInfo: PhotoMapZoomInfo | undefined = undefined;
  @Trace tileServer: PhotoMapTileServer | undefined = undefined;
  @Trace tileServerList: PhotoMapTileServer[] = [];
  @Trace items: PhotoMapIndexItem[] = [];
  @Trace center: LatLang = new LatLang(34.0, 108.0);
  @Trace zoom: number = 5.0;
  /** 瓦片服务器切换种子（URL 携带，切服后强制刷新瓦片） */
  @Trace mapRebuildSeed: number = 0;

  get mapCoordinate(): string {
    return this.tileServer !== undefined ? this.tileServer.coordinate : 'WGS-84';
  }

  /** 初始化（对齐 Flutter onInit）：恢复上次视角 + 加载数据 */
  init(): void {
    this.restoreState();
    void this.initData();
  }

  /** 页面销毁时调用（对齐 Flutter onClose） */
  dispose(): void {
    if (this.debounceTimerId >= 0) {
      clearTimeout(this.debounceTimerId);
      this.debounceTimerId = -1;
    }
  }

  private restoreState(): void {
    const cached = PreferencesStore.getInstance().getJson<Record<string, number>>(MAP_STATE_KEY);
    if (cached === undefined) {
      return;
    }
    const lat = Number(cached['lat']);
    const lng = Number(cached['lng']);
    const z = Number(cached['zoom']);
    if (Number.isFinite(lat) && Number.isFinite(lng)) {
      this.center = new LatLang(lat, lng);
    }
    if (Number.isFinite(z) && z > 0) {
      this.zoom = z;
    }
  }

  private persistState(): void {
    const state: Record<string, number> = {
      'lat': this.center.latitude,
      'lng': this.center.longitude,
      'zoom': this.zoom
    };
    void PreferencesStore.getInstance().setJson(MAP_STATE_KEY, state);
  }

  /** 初始化加载（对齐 Flutter initData） */
  async initData(): Promise<void> {
    this.loading = true;
    this.errorText = '';
    try {
      const zoomRes = await this.api.getZoom();
      if (zoomRes.success && zoomRes.data !== undefined) {
        this.zoomInfo = zoomRes.data.zoomInfo;
        this.tileServer = zoomRes.data.tileServer;
        this.zoom = Math.min(Math.max(this.zoom, this.zoomInfo.minZoom), this.zoomInfo.maxZoom);
      }
      const listRes = await this.api.getTileServerList();
      if (listRes.success && listRes.data !== undefined) {
        this.tileServerList = listRes.data;
      }
    } catch (e) {
      this.errorText = `${e}`;
    } finally {
      this.loading = false;
    }
  }

  /** 地图视角变化（对齐 Flutter onMapChanged）：立即取消旧请求 + 650ms 防抖拉取 + 持久化 */
  onMapChanged(bounds: MapBounds, zoomLevel: number, mapCenter: LatLang): void {
    this.center = mapCenter;
    this.zoom = zoomLevel;

    if (this.debounceTimerId >= 0) {
      clearTimeout(this.debounceTimerId);
    }
    this.debounceTimerId = setTimeout(() => {
      this.debounceTimerId = -1;
      void this.fetchBounds(bounds, zoomLevel);
      this.persistState();
    }, FETCH_DEBOUNCE_MS);
  }

  /** 拉取可视范围照片（对齐 Flutter fetchBounds） */
  async fetchBounds(mapBounds: MapBounds, zoomLevel: number): Promise<void> {
    const coord = this.mapCoordinate;
    const sw = CoordinateTransform.fromMapCoordinate(coord, mapBounds.southLat, mapBounds.southLng);
    const ne = CoordinateTransform.fromMapCoordinate(coord, mapBounds.northLat, mapBounds.northLng);
    const b = new MapBounds();
    b.southLat = sw.latitude;
    b.southLng = sw.longitude;
    b.northLat = ne.latitude;
    b.northLng = ne.longitude;
    const zInt = Math.round(zoomLevel);

    if (this.lastFetchedBounds !== undefined && this.lastFetchedZoom === zInt && this.boundsSimilar(this.lastFetchedBounds, b)) {
      return;
    }

    try {
      const res = await this.api.getBoundsPhoto(b.southLat, b.southLng, b.northLat, b.northLng, zoomLevel);
      if (res.success && res.data !== undefined) {
        this.lastFetchedBounds = b;
        this.lastFetchedZoom = zInt;
        this.items = res.data;
      }
    } catch (e) {
      const s = `${e}`;
      if (!s.includes('p2p_canceled') && !s.includes('cancel')) {
        this.errorText = s;
      }
    }
  }

  /** 刷新瓦片服务器列表并同步当前项（对齐 Flutter refreshTileServerList） */
  async refreshTileServerList(): Promise<void> {
    const res = await this.api.getTileServerList();
    if (res.success && res.data !== undefined) {
      this.tileServerList = res.data;
      const current = res.data.find((e: PhotoMapTileServer) => e.isCurrent);
      if (current !== undefined) {
        this.tileServer = current;
      }
    }
  }

  /** 切换瓦片服务器（对齐 Flutter switchTileServer）：切服成功后种子 +1 强制刷新瓦片 */
  async switchTileServer(server: PhotoMapTileServer): Promise<boolean> {
    const res = await this.api.setTileServer(server);
    if (!res.success) {
      return false;
    }

    const zoomRes = await this.api.getZoom();
    if (zoomRes.success && zoomRes.data !== undefined) {
      this.zoomInfo = zoomRes.data.zoomInfo;
      this.tileServer = zoomRes.data.tileServer;
      if (this.zoomInfo !== undefined) {
        this.zoom = Math.min(Math.max(this.zoom, this.zoomInfo.minZoom), this.zoomInfo.maxZoom);
      }
    }

    await this.refreshTileServerList();
    this.lastFetchedBounds = undefined;
    this.lastFetchedZoom = -1;
    this.mapRebuildSeed += 1;
    return true;
  }

  /** 照片标注位置（WGS-84 → 地图坐标系，对齐 Flutter markerPosition） */
  markerPosition(item: PhotoMapIndexItem): LatLang {
    return CoordinateTransform.toMapCoordinate(this.mapCoordinate, item.latitude, item.longitude);
  }

  /** geohash 反查地名（对齐 Flutter _openMarkerDetail 中的 getLocationStr，失败返回空串） */
  async getLocationName(geohash: string): Promise<string> {
    try {
      const res = await this.api.getLocationStr(geohash);
      if (res.success && res.data !== undefined) {
        return res.data;
      }
    } catch (_e) {
    }
    return '';
  }

  private boundsSimilar(a: MapBounds, b: MapBounds): boolean {
    const eps = 0.0008;
    const da = Math.abs(a.southLat - b.southLat) + Math.abs(a.southLng - b.southLng) +
      Math.abs(a.northLat - b.northLat) + Math.abs(a.northLng - b.northLng);
    return da < eps;
  }
}
