import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:path/path.dart' as p;

import '../../../../../core/api/api_controller.dart';
import '../../../../../core/routes/app_routes.dart';
import '../../../../../utils/local_web_asset_server.dart';
import '../../../../../utils/file_util.dart';
import '../../../../../utils/device_utils.dart';
import '../../../base/components/custom_extended_image.dart';
import '../../controllers/custom_gallery_controller.dart';
import '../../../photo/timeline/models/photo_timeline_model.dart';
import '../../../home/views/pc_home_controller.dart';

class GalleryInfoPanel extends StatelessWidget {
  const GalleryInfoPanel({super.key, required this.controller, this.onClose});

  final CustomGalleryController controller;

  /// 关闭回调（如从底部 sheet 打开时传入，用于 Navigator.pop）
  final VoidCallback? onClose;

  void _openPathInFileBrowser(String targetPath) {
    final target = targetPath.trim();
    if (target.isEmpty) return;
    final openTarget = p.extension(target).isEmpty ? target : p.dirname(target);
    if (DeviceUtils.isDesktop && Get.isRegistered<PcHomeController>()) {
      PcHomeController.instance.openFolderAt(openTarget);
      return;
    }
    AppRoutes.toFiles(initialPath: openTarget);
  }

  String? _fmtIso(String? iso) {
    final s = (iso ?? '').trim();
    if (s.isEmpty) return null;
    final dt = DateTime.tryParse(s);
    if (dt == null) return s;
    return DateFormat('yyyy-MM-dd HH:mm:ss').format(dt.toLocal());
  }

  String? _fmtNum(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toString();
    final s = v.toString().trim();
    return s.isEmpty ? null : s;
  }

  String? _fmtFNumber(dynamic v) {
    final s = _fmtNum(v);
    if (s == null) return null;
    if (s.startsWith('f/') || s.startsWith('F/')) return s;
    return 'f/$s';
  }

  String? _fmtFocalMm(dynamic v) {
    final s = _fmtNum(v);
    if (s == null) return null;
    final n = double.tryParse(s);
    if (n == null) return s;
    final nice = (n % 1 == 0) ? n.toStringAsFixed(0) : n.toStringAsFixed(1);
    return '${nice}mm';
  }

  String? _fmtExposureFromSeconds(double seconds) {
    if (!seconds.isFinite || seconds <= 0) return null;
    if (seconds >= 1) {
      final s = (seconds % 1 == 0)
          ? seconds.toStringAsFixed(0)
          : seconds.toStringAsFixed(2);
      return '${s}s';
    }
    final denom = (1 / seconds).round();
    if (denom <= 0) return null;
    return '1/$denom';
  }

  String? _fmtExposure(dynamic exposureTime, dynamic shutterSpeedValue) {
    final et = _fmtNum(exposureTime);
    if (et != null) {
      if (et.contains('/')) return et;
      if (et.endsWith('s')) return et;
      final n = double.tryParse(et);
      if (n != null) return _fmtExposureFromSeconds(n) ?? et;
      return et;
    }

    final sv = _fmtNum(shutterSpeedValue);
    if (sv == null) return null;
    if (sv.contains('/')) return sv;
    if (sv.endsWith('s')) return sv;
    final n = double.tryParse(sv);
    if (n == null) return sv;
    final seconds = pow(2, -n).toDouble();
    return _fmtExposureFromSeconds(seconds) ?? sv;
  }

  String? _shootingParamsLine(Map<String, dynamic> exif) {
    final f = _fmtFNumber(exif['fNumber'] ?? exif['apertureValue']);
    final exp = _fmtExposure(exif['exposureTime'], exif['shutterSpeedValue']);
    final focal = _fmtFocalMm(exif['focalLength']);
    final iso = _fmtNum(exif['iso']);

    final parts = <String>[];
    if (f != null) parts.add(f);
    if (exp != null) parts.add(exp);
    if (focal != null) parts.add(focal);
    if (iso != null) parts.add('ISO:$iso');
    if (parts.isEmpty) return null;
    return parts.join(' ');
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black.withValues(alpha: 0.85),
      padding: const EdgeInsets.fromLTRB(12, 24, 12, 12),
      child: Obx(() {
        final loading = controller.infoLoading.value;
        final errorText = controller.infoErrorText.value;
        final data = controller.infoData.value;

        final exif =
            (data != null ? data['exif'] as Map? : null)
                ?.cast<String, dynamic>() ??
            <String, dynamic>{};

        final geo = data != null ? (data['geo'] ?? '').toString().trim() : '';
        final lat = (data != null ? data['latitude'] : null);
        final lng = (data != null ? data['longitude'] : null);
        final latNum = lat is num ? lat.toDouble() : double.tryParse('$lat');
        final lngNum = lng is num ? lng.toDouble() : double.tryParse('$lng');
        final hasGps =
            latNum != null && lngNum != null && latNum != 0 && lngNum != 0;

        final fullpath = data != null
            ? (data['fullpath'] ?? '').toString().trim()
            : '';
        final size = data != null ? data['size'] : null;
        final w = data != null ? data['width'] : null;
        final h = data != null ? data['height'] : null;

        final createTime = data != null ? data['createTime'] : null;
        final mtime = data != null ? data['mtime'] : null;
        final originalTime = data != null ? data['originalTime'] : null;
        final photoIndex =
            (data != null ? data['photoIndex'] as Map? : null)
                ?.cast<String, dynamic>() ??
            <String, dynamic>{};
        final photoFileHash = (photoIndex['fileHash'] ?? '').toString().trim();
        final detectedFaces =
            (data != null ? data['photoFaces'] as List<dynamic>? : null)
                ?.whereType<TimelineDetectedFaceItem>()
                .toList() ??
            const <TimelineDetectedFaceItem>[];

        final sizeInt = size is int ? size : int.tryParse('$size');
        final sizeText = (sizeInt != null && sizeInt > 0)
            ? FileUtil.formatSize(sizeInt)
            : null;

        final widthNum = (w is num) ? w.toInt() : int.tryParse('$w');
        final heightNum = (h is num) ? h.toInt() : int.tryParse('$h');
        final dimensionText =
            (widthNum != null &&
                heightNum != null &&
                widthNum > 0 &&
                heightNum > 0)
            ? '$widthNum × $heightNum'
            : null;

        final mtimeText = _fmtIso(mtime?.toString());
        final createTimeText = _fmtIso(createTime?.toString());
        final originalTimeText = _fmtIso(originalTime?.toString());

        final baseRows = <Widget>[];
        if (fullpath.isNotEmpty) {
          baseRows.add(
            _InfoRow(
              label: 'path'.tr,
              valueChild: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onTap: () => _openPathInFileBrowser(fullpath),
                      child: Text(
                        fullpath,
                        style: const TextStyle(color: Colors.blue),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }
        if (sizeText != null) {
          baseRows.add(_InfoRow(label: 'size'.tr, value: sizeText));
        }
        if (dimensionText != null) {
          baseRows.add(
            _InfoRow(label: 'gallery_info_dimensions'.tr, value: dimensionText),
          );
        }
        if (mtimeText != null) {
          baseRows.add(_InfoRow(label: 'modified_at'.tr, value: mtimeText));
        }
        if (createTimeText != null) {
          baseRows.add(
            _InfoRow(label: 'create_time'.tr, value: createTimeText),
          );
        }
        if (originalTimeText != null) {
          baseRows.add(
            _InfoRow(
              label: 'gallery_info_taken_time'.tr,
              value: originalTimeText,
            ),
          );
        }

        final device =
            '${(exif['make'] ?? '').toString()} ${(exif['model'] ?? '').toString()}'
                .trim();
        final lens = _fmtNum(exif['lensModel']);
        final shootingLine = _shootingParamsLine(exif);

        final exifRows = <Widget>[];
        if (device.isNotEmpty) {
          exifRows.add(
            _InfoRow(label: 'gallery_info_device'.tr, value: device),
          );
        }
        if (lens != null) {
          exifRows.add(_InfoRow(label: 'gallery_info_lens'.tr, value: lens));
        }

        return DefaultTextStyle(
          style: const TextStyle(color: Colors.white, fontSize: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 6),
              Row(
                children: [
                  const Spacer(),
                  IconButton(
                    onPressed: () => (onClose != null
                        ? onClose!()
                        : controller.toggleInfoPanel()),
                    icon: Icon(
                      onClose != null ? Icons.close : Icons.chevron_left,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
              if (loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Center(child: CircularProgressIndicator()),
                ),
              if (!loading && errorText.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(errorText),
                ),
              if (data != null)
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (baseRows.isNotEmpty) ...[
                          _InfoSectionTitle(title: 'gallery_info_basic'.tr),
                          ...baseRows,
                          const SizedBox(height: 12),
                        ],
                        if (shootingLine != null) ...[
                          _InfoSectionTitle(
                            title: 'gallery_info_shooting_params'.tr,
                          ),
                          _InfoRow(
                            label: '',
                            value: shootingLine,
                            labelWidth: 0,
                          ),
                          const SizedBox(height: 12),
                        ],
                        if (exifRows.isNotEmpty) ...[
                          _InfoSectionTitle(title: 'gallery_info_exif'.tr),
                          ...exifRows,
                          const SizedBox(height: 12),
                        ],
                        if (detectedFaces.isNotEmpty &&
                            photoFileHash.isNotEmpty) ...[
                          _InfoSectionTitle(title: 'gallery_info_people'.tr),
                          const SizedBox(height: 8),
                          ...detectedFaces.map(
                            (face) => Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: _InfoFaceRow(
                                face: face,
                                fileHash: photoFileHash,
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],
                        if (hasGps) ...[
                          _InfoSectionTitle(title: 'location'.tr),
                          if (geo.isNotEmpty)
                            _InfoRow(label: '', value: geo, labelWidth: 0),
                          const SizedBox(height: 8),
                          SizedBox(
                            height: 220,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: _LatLngMap(lat: latNum, lng: lngNum),
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],
                      ],
                    ),
                  ),
                ),
            ],
          ),
        );
      }),
    );
  }
}

class _InfoSectionTitle extends StatelessWidget {
  const _InfoSectionTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.label,
    this.value,
    this.valueChild,
    this.labelWidth = 70,
  });

  final String label;
  final String? value;
  final Widget? valueChild;
  final double labelWidth;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (labelWidth > 0)
            SizedBox(
              width: labelWidth,
              child: Text(
                label,
                textAlign: TextAlign.left,
                style: TextStyle(color: Colors.white.withValues(alpha: 0.8)),
              ),
            ),
          if (labelWidth > 0) const SizedBox(width: 8),
          Expanded(
            child: valueChild ?? Text((value ?? '').trim(), softWrap: true),
          ),
        ],
      ),
    );
  }
}

class _InfoFaceRow extends StatelessWidget {
  const _InfoFaceRow({required this.face, required this.fileHash});

  final TimelineDetectedFaceItem face;
  final String fileHash;

  @override
  Widget build(BuildContext context) {
    final name = (face.name ?? '').trim();
    final displayName = name.isNotEmpty ? name : '(${'face_unnamed'.tr})';
    final subtitle =
        '${'total_count'.trParams({'count': face.faceCount.toString()})}'
        '${face.isHide ? ' · ${'face_action_hide'.tr}' : ''}';
    const avatarSize = 34.0;

    return Row(
      children: [
        Container(
          width: avatarSize,
          height: avatarSize,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
          ),
          child: ClipOval(
            child: CustomExtendedImage(
              cache: false,
              imageUrl: ApiController.instance.getFaceImageUrl(
                faceId: face.faceId,
                fileHash: fileHash,
                size: 120,
                quality: 85,
              ),
              width: avatarSize,
              height: avatarSize,
              fit: BoxFit.cover,
              borderRadius: avatarSize / 2,
              showLoading: false,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(displayName, maxLines: 1, overflow: TextOverflow.ellipsis),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Colors.white.withValues(alpha: 0.72)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _LatLngMap extends StatelessWidget {
  const _LatLngMap({required this.lat, required this.lng});

  final double lat;
  final double lng;

  @override
  Widget build(BuildContext context) {
    final token = ApiController.instance.accessToken ?? '';
    final baseUrl = ApiController.instance.baseUrl;
    final point = LatLng(lat, lng);

    final isP2p = ApiController.instance.isP2pMode;

    return _LatLngMapInner(
      point: point,
      token: token,
      baseUrl: baseUrl,
      isP2p: isP2p,
    );
  }
}

class _LatLngMapInner extends StatefulWidget {
  const _LatLngMapInner({
    required this.point,
    required this.token,
    required this.baseUrl,
    required this.isP2p,
  });

  final LatLng point;
  final String token;
  final String baseUrl;
  final bool isP2p;

  @override
  State<_LatLngMapInner> createState() => _LatLngMapInnerState();
}

class _LatLngMapInnerState extends State<_LatLngMapInner> {
  Uri? _localProxyBase;
  bool _localProxyAcquired = false;

  @override
  void dispose() {
    if (_localProxyAcquired) {
      LocalWebAssetServer.instance.release();
      _localProxyAcquired = false;
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isWeb = DeviceUtils.isWeb;
    final isP2p = widget.isP2p;

    if (isP2p && !isWeb && _localProxyBase == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted || _localProxyBase != null) return;
        final base = await LocalWebAssetServer.instance.acquire();
        if (!mounted) return;
        setState(() {
          _localProxyBase = base;
          _localProxyAcquired = true;
        });
      });
    }
    if (!isP2p && !isWeb && _localProxyAcquired && _localProxyBase != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await LocalWebAssetServer.instance.release();
      });
      _localProxyAcquired = false;
      _localProxyBase = null;
    }

    final tileBase = isP2p
        ? (isWeb ? '/__p2p__' : (_localProxyBase?.toString() ?? ''))
        : widget.baseUrl;
    final urlTemplate = tileBase.isEmpty
        ? ''
        : (widget.token.isNotEmpty
              ? '$tileBase/api/mapApi/tile?zoom={z}&x={x}&y={y}&accessToken=${Uri.encodeComponent(widget.token)}'
              : '$tileBase/api/mapApi/tile?zoom={z}&x={x}&y={y}');

    return FlutterMap(
      options: MapOptions(
        initialCenter: widget.point,
        initialZoom: 10,
        minZoom: 3,
        maxZoom: 18,
      ),
      children: [
        if (urlTemplate.isNotEmpty)
          TileLayer(urlTemplate: urlTemplate, userAgentPackageName: 'NasCabOS'),
        MarkerLayer(
          markers: [
            Marker(
              point: widget.point,
              width: 40,
              height: 40,
              child: const Icon(Icons.location_on, color: Colors.red, size: 36),
            ),
          ],
        ),
      ],
    );
  }
}
