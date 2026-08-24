import 'dart:math' as math;

class CoordinateTransform {
  static const double _pi = math.pi;
  static const double _a = 6378245.0;
  static const double _ee = 0.00669342162296594323;

  static bool _outOfChina(double lat, double lng) {
    if (lng < 72.004 || lng > 137.8347) return true;
    if (lat < 0.8293 || lat > 55.8271) return true;
    return false;
  }

  static (double, double) wgs84ToGcj02(double lat, double lng) {
    if (_outOfChina(lat, lng)) return (lat, lng);
    final d = _delta(lat, lng);
    return (lat + d.$1, lng + d.$2);
  }

  static (double, double) gcj02ToWgs84(double lat, double lng) {
    if (_outOfChina(lat, lng)) return (lat, lng);
    final d = _delta(lat, lng);
    return (lat - d.$1, lng - d.$2);
  }

  static (double, double) gcj02ToBd09(double lat, double lng) {
    final x = lng;
    final y = lat;
    final z = math.sqrt(x * x + y * y) + 0.00002 * math.sin(y * _pi);
    final theta = math.atan2(y, x) + 0.000003 * math.cos(x * _pi);
    final bdLng = z * math.cos(theta) + 0.0065;
    final bdLat = z * math.sin(theta) + 0.006;
    return (bdLat, bdLng);
  }

  static (double, double) bd09ToGcj02(double lat, double lng) {
    final x = lng - 0.0065;
    final y = lat - 0.006;
    final z = math.sqrt(x * x + y * y) - 0.00002 * math.sin(y * _pi);
    final theta = math.atan2(y, x) - 0.000003 * math.cos(x * _pi);
    final ggLng = z * math.cos(theta);
    final ggLat = z * math.sin(theta);
    return (ggLat, ggLng);
  }

  static (double, double) wgs84ToBd09(double lat, double lng) {
    final gcj = wgs84ToGcj02(lat, lng);
    return gcj02ToBd09(gcj.$1, gcj.$2);
  }

  static (double, double) bd09ToWgs84(double lat, double lng) {
    final gcj = bd09ToGcj02(lat, lng);
    return gcj02ToWgs84(gcj.$1, gcj.$2);
  }

  static (double, double) toMapCoordinate(
    String coordinate,
    double lat,
    double lng,
  ) {
    final c = coordinate.trim().toUpperCase();
    if (c == 'GCJ-02' || c == 'GCJ02') return wgs84ToGcj02(lat, lng);
    if (c == 'BD-09' || c == 'BD09') return wgs84ToBd09(lat, lng);
    return (lat, lng);
  }

  static (double, double) fromMapCoordinate(
    String coordinate,
    double lat,
    double lng,
  ) {
    final c = coordinate.trim().toUpperCase();
    if (c == 'GCJ-02' || c == 'GCJ02') return gcj02ToWgs84(lat, lng);
    if (c == 'BD-09' || c == 'BD09') return bd09ToWgs84(lat, lng);
    return (lat, lng);
  }

  static (double, double) _delta(double lat, double lng) {
    final dLat = _transformLat(lng - 105.0, lat - 35.0);
    final dLng = _transformLng(lng - 105.0, lat - 35.0);
    final radLat = lat / 180.0 * _pi;
    var magic = math.sin(radLat);
    magic = 1 - _ee * magic * magic;
    final sqrtMagic = math.sqrt(magic);
    final mgLat =
        (dLat * 180.0) / ((_a * (1 - _ee)) / (magic * sqrtMagic) * _pi);
    final mgLng = (dLng * 180.0) / (_a / sqrtMagic * math.cos(radLat) * _pi);
    return (mgLat, mgLng);
  }

  static double _transformLat(double x, double y) {
    var ret =
        -100.0 +
        2.0 * x +
        3.0 * y +
        0.2 * y * y +
        0.1 * x * y +
        0.2 * math.sqrt(x.abs());
    ret +=
        (20.0 * math.sin(6.0 * x * _pi) + 20.0 * math.sin(2.0 * x * _pi)) *
        2.0 /
        3.0;
    ret +=
        (20.0 * math.sin(y * _pi) + 40.0 * math.sin(y / 3.0 * _pi)) * 2.0 / 3.0;
    ret +=
        (160.0 * math.sin(y / 12.0 * _pi) + 320 * math.sin(y * _pi / 30.0)) *
        2.0 /
        3.0;
    return ret;
  }

  static double _transformLng(double x, double y) {
    var ret =
        300.0 +
        x +
        2.0 * y +
        0.1 * x * x +
        0.1 * x * y +
        0.1 * math.sqrt(x.abs());
    ret +=
        (20.0 * math.sin(6.0 * x * _pi) + 20.0 * math.sin(2.0 * x * _pi)) *
        2.0 /
        3.0;
    ret +=
        (20.0 * math.sin(x * _pi) + 40.0 * math.sin(x / 3.0 * _pi)) * 2.0 / 3.0;
    ret +=
        (150.0 * math.sin(x / 12.0 * _pi) + 300.0 * math.sin(x / 30.0 * _pi)) *
        2.0 /
        3.0;
    return ret;
  }
}
