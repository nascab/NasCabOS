/**
 * 坐标系转换工具（对齐 Flutter coordinate_transform.dart）：
 * WGS-84 / GCJ-02（火星坐标） / BD-09（百度坐标）互转。
 */

/** 经纬度值对象（ArkTS 无元组，用类承载） */
export class LatLang {
  latitude: number;
  longitude: number;

  constructor(latitude: number, longitude: number) {
    this.latitude = latitude;
    this.longitude = longitude;
  }
}

export class CoordinateTransform {
  private static readonly PI: number = Math.PI;
  private static readonly A: number = 6378245.0;
  private static readonly EE: number = 0.00669342162296594323;

  private static outOfChina(lat: number, lng: number): boolean {
    if (lng < 72.004 || lng > 137.8347) {
      return true;
    }
    if (lat < 0.8293 || lat > 55.8271) {
      return true;
    }
    return false;
  }

  static wgs84ToGcj02(lat: number, lng: number): LatLang {
    if (CoordinateTransform.outOfChina(lat, lng)) {
      return new LatLang(lat, lng);
    }
    const d = CoordinateTransform.delta(lat, lng);
    return new LatLang(lat + d.latitude, lng + d.longitude);
  }

  static gcj02ToWgs84(lat: number, lng: number): LatLang {
    if (CoordinateTransform.outOfChina(lat, lng)) {
      return new LatLang(lat, lng);
    }
    const d = CoordinateTransform.delta(lat, lng);
    return new LatLang(lat - d.latitude, lng - d.longitude);
  }

  static gcj02ToBd09(lat: number, lng: number): LatLang {
    const x = lng;
    const y = lat;
    const z = Math.sqrt(x * x + y * y) + 0.00002 * Math.sin(y * CoordinateTransform.PI);
    const theta = Math.atan2(y, x) + 0.000003 * Math.cos(x * CoordinateTransform.PI);
    const bdLng = z * Math.cos(theta) + 0.0065;
    const bdLat = z * Math.sin(theta) + 0.006;
    return new LatLang(bdLat, bdLng);
  }

  static bd09ToGcj02(lat: number, lng: number): LatLang {
    const x = lng - 0.0065;
    const y = lat - 0.006;
    const z = Math.sqrt(x * x + y * y) - 0.00002 * Math.sin(y * CoordinateTransform.PI);
    const theta = Math.atan2(y, x) - 0.000003 * Math.cos(x * CoordinateTransform.PI);
    const ggLng = z * Math.cos(theta);
    const ggLat = z * Math.sin(theta);
    return new LatLang(ggLat, ggLng);
  }

  static wgs84ToBd09(lat: number, lng: number): LatLang {
    const gcj = CoordinateTransform.wgs84ToGcj02(lat, lng);
    return CoordinateTransform.gcj02ToBd09(gcj.latitude, gcj.longitude);
  }

  static bd09ToWgs84(lat: number, lng: number): LatLang {
    const gcj = CoordinateTransform.bd09ToGcj02(lat, lng);
    return CoordinateTransform.gcj02ToWgs84(gcj.latitude, gcj.longitude);
  }

  /** WGS-84 → 地图坐标系（对齐 Flutter toMapCoordinate） */
  static toMapCoordinate(coordinate: string, lat: number, lng: number): LatLang {
    const c = coordinate.trim().toUpperCase();
    if (c === 'GCJ-02' || c === 'GCJ02') {
      return CoordinateTransform.wgs84ToGcj02(lat, lng);
    }
    if (c === 'BD-09' || c === 'BD09') {
      return CoordinateTransform.wgs84ToBd09(lat, lng);
    }
    return new LatLang(lat, lng);
  }

  /** 地图坐标系 → WGS-84（对齐 Flutter fromMapCoordinate） */
  static fromMapCoordinate(coordinate: string, lat: number, lng: number): LatLang {
    const c = coordinate.trim().toUpperCase();
    if (c === 'GCJ-02' || c === 'GCJ02') {
      return CoordinateTransform.gcj02ToWgs84(lat, lng);
    }
    if (c === 'BD-09' || c === 'BD09') {
      return CoordinateTransform.bd09ToWgs84(lat, lng);
    }
    return new LatLang(lat, lng);
  }

  private static delta(lat: number, lng: number): LatLang {
    const dLat = CoordinateTransform.transformLat(lng - 105.0, lat - 35.0);
    const dLng = CoordinateTransform.transformLng(lng - 105.0, lat - 35.0);
    const radLat = lat / 180.0 * CoordinateTransform.PI;
    let magic = Math.sin(radLat);
    magic = 1 - CoordinateTransform.EE * magic * magic;
    const sqrtMagic = Math.sqrt(magic);
    const mgLat = (dLat * 180.0) /
      ((CoordinateTransform.A * (1 - CoordinateTransform.EE)) / (magic * sqrtMagic) * CoordinateTransform.PI);
    const mgLng = (dLng * 180.0) / (CoordinateTransform.A / sqrtMagic * Math.cos(radLat) * CoordinateTransform.PI);
    return new LatLang(mgLat, mgLng);
  }

  private static transformLat(x: number, y: number): number {
    const pi = CoordinateTransform.PI;
    let ret = -100.0 + 2.0 * x + 3.0 * y + 0.2 * y * y + 0.1 * x * y + 0.2 * Math.sqrt(Math.abs(x));
    ret += (20.0 * Math.sin(6.0 * x * pi) + 20.0 * Math.sin(2.0 * x * pi)) * 2.0 / 3.0;
    ret += (20.0 * Math.sin(y * pi) + 40.0 * Math.sin(y / 3.0 * pi)) * 2.0 / 3.0;
    ret += (160.0 * Math.sin(y / 12.0 * pi) + 320 * Math.sin(y * pi / 30.0)) * 2.0 / 3.0;
    return ret;
  }

  private static transformLng(x: number, y: number): number {
    const pi = CoordinateTransform.PI;
    let ret = 300.0 + x + 2.0 * y + 0.1 * x * x + 0.1 * x * y + 0.1 * Math.sqrt(Math.abs(x));
    ret += (20.0 * Math.sin(6.0 * x * pi) + 20.0 * Math.sin(2.0 * x * pi)) * 2.0 / 3.0;
    ret += (20.0 * Math.sin(x * pi) + 40.0 * Math.sin(x / 3.0 * pi)) * 2.0 / 3.0;
    ret += (150.0 * Math.sin(x / 12.0 * pi) + 300.0 * Math.sin(x / 30.0 * pi)) * 2.0 / 3.0;
    return ret;
  }
}
