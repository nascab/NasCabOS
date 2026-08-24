class PhotoMapTileServer {
  final String name;
  final String server;
  final String coordinate;
  final int maxLevel;
  final bool isDefault;
  final bool isCustom;
  final bool isCurrent;

  const PhotoMapTileServer({
    required this.name,
    required this.server,
    required this.coordinate,
    required this.maxLevel,
    required this.isDefault,
    required this.isCustom,
    required this.isCurrent,
  });

  factory PhotoMapTileServer.fromJson(Map<String, dynamic> json) {
    return PhotoMapTileServer(
      name: (json['name'] ?? '').toString(),
      server: (json['server'] ?? '').toString(),
      coordinate: (json['coordinate'] ?? 'WGS-84').toString(),
      maxLevel: int.tryParse((json['maxLevel'] ?? 18).toString()) ?? 18,
      isDefault: json['isDefault'] == true || json['isDefault'] == 1,
      isCustom: json['isCustom'] == true || json['isCustom'] == 1,
      isCurrent: json['current'] == true || json['current'] == 1,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'server': server,
      'coordinate': coordinate,
      'maxLevel': maxLevel,
      'isDefault': isDefault ? 1 : 0,
    };
  }
}

class PhotoMapZoomInfo {
  final int minZoom;
  final int maxZoom;

  const PhotoMapZoomInfo({required this.minZoom, required this.maxZoom});

  factory PhotoMapZoomInfo.fromJson(Map<String, dynamic> json) {
    return PhotoMapZoomInfo(
      minZoom: int.tryParse((json['minZoom'] ?? 2).toString()) ?? 2,
      maxZoom: int.tryParse((json['maxZoom'] ?? 18).toString()) ?? 18,
    );
  }
}

class PhotoMapIndexItem {
  final int id;
  final double latitude;
  final double longitude;
  final String? geohash;
  final int? originalTime;
  final String? fullpath;
  final String? type;
  final num? duration;

  const PhotoMapIndexItem({
    required this.id,
    required this.latitude,
    required this.longitude,
    this.geohash,
    this.originalTime,
    this.fullpath,
    this.type,
    this.duration,
  });

  factory PhotoMapIndexItem.fromJson(Map<String, dynamic> json) {
    return PhotoMapIndexItem(
      id: int.tryParse((json['id'] ?? 0).toString()) ?? 0,
      latitude: double.tryParse((json['latitude'] ?? 0).toString()) ?? 0,
      longitude: double.tryParse((json['longitude'] ?? 0).toString()) ?? 0,
      geohash: json['geohash']?.toString(),
      originalTime: int.tryParse((json['original_time'] ?? '').toString()),
      fullpath: json['fullpath']?.toString(),
      type: json['type']?.toString(),
      duration: json['duration'] as num?,
    );
  }
}
