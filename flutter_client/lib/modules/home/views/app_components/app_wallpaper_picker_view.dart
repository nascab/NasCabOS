import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:dio/dio.dart' as dio;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;

import '../../../../core/api/api_controller.dart';
import '../../../../core/api/dio_bad_certificate_compat.dart';
import '../../../../core/user/current_user_controller.dart';
import '../../../../utils/dialog_util.dart';
import '../../../../utils/toast_util.dart';
import '../../../base/components/custom_extended_image.dart';
import '../../../base/components/mobile_upload_source_picker.dart';
import '../../../transfer/utils/mobile_media_file_picker.dart';
import '../../service/appearance_api_service.dart';

/// 手机端壁纸选择视图：顶部随机/固定，中间自适应 GridView，底部应用/取消
class AppWallpaperPickerView extends StatefulWidget {
  const AppWallpaperPickerView({super.key});

  @override
  State<AppWallpaperPickerView> createState() => _AppWallpaperPickerViewState();
}

class _AppWallpaperPickerViewState extends State<AppWallpaperPickerView> {
  List<Map<String, dynamic>> _wallpapers = [];
  String _mode = 'fixed';
  String? _selectedName;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadWallpapers();
  }

  Future<void> _loadWallpapers() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final resp = await AppearanceApiService.instance.getWallpapers();
    if (!resp.success || resp.data is! List) {
      setState(() {
        _loading = false;
        _error = resp.message ?? 'operation_failed'.tr;
      });
      return;
    }
    final list = List<Map<String, dynamic>>.from(resp.data as List);
    setState(() {
      _wallpapers = list;
      _loading = false;
    });
  }

  Future<void> _apply() async {
    if (_mode == 'fixed' && (_selectedName == null || _selectedName!.isEmpty)) {
      return;
    }
    final resp = await AppearanceApiService.instance.setWallpaper(
      mode: _mode,
      name: _mode == 'fixed' ? _selectedName : null,
    );
    if (!resp.success || resp.data is! Map) {
      ToastUtil.show(resp.message ?? 'home_wallpaper_save_failed'.tr);
      return;
    }
    final map = Map<String, dynamic>.from(resp.data as Map);
    CurrentUserController.instance.setWallpaper(map);
    // await CustomExtendedImage.clearCache();
    if (mounted) Get.back();
    ToastUtil.show('home_wallpaper_save_success'.tr);
  }

  Future<void> _uploadCustomWallpaper() async {
    try {
      Uint8List? bytes;
      String filename = 'wallpaper';

      if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) {
        final result = await FilePicker.platform.pickFiles(
          type: FileType.image,
          allowMultiple: false,
          withData: true,
        );
        if (result == null || result.files.isEmpty) return;
        final file = result.files.first;
        filename = file.name.trim().isNotEmpty ? file.name.trim() : 'wallpaper';
        bytes = file.bytes;
      } else {
        final source = await showMobileUploadSourcePicker(context);
        if (source == null) return;

        if (source == MobileUploadSourceType.media) {
          final entries = await MobileMediaFilePicker.pickMediaUploadEntries(
            context,
            includeLivePhotoVideo: false,
            maxAssets: 1,
          );
          if (entries.isEmpty) return;
          final xf = entries.first['file'];
          if (xf is! XFile) return;
          try {
            bytes = await xf.readAsBytes();
          } catch (_) {
            ToastUtil.show('home_wallpaper_upload_failed'.tr);
            return;
          }
          final n = (entries.first['name'] ?? '').toString().trim();
          filename = n.isNotEmpty
              ? n
              : (xf.name.trim().isNotEmpty ? xf.name.trim() : 'wallpaper');
        } else {
          final result = await FilePicker.platform.pickFiles(
            type: FileType.image,
            allowMultiple: false,
            withData: true,
          );
          if (result == null || result.files.isEmpty) return;
          final file = result.files.first;
          filename = file.name.trim().isNotEmpty ? file.name.trim() : 'wallpaper';
          bytes = file.bytes;
        }
      }

      if (bytes == null || bytes.isEmpty) {
        ToastUtil.show('home_wallpaper_upload_failed'.tr);
        return;
      }

      final baseUrl = ApiController.instance.baseUrl.trim();
      if (baseUrl.isEmpty) {
        ToastUtil.show('network_failure'.tr);
        return;
      }

      final token = (ApiController.instance.accessToken ?? '').trim();
      final d = createDioWithBadCertificateCompat(
        dio.BaseOptions(
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(minutes: 3),
          sendTimeout: const Duration(minutes: 3),
          headers: {if (token.isNotEmpty) 'Authorization': 'Bearer $token'},
        ),
      );

      final progress = ValueNotifier<double>(0);
      final cancelToken = dio.CancelToken();

      Get.dialog(
        DialogUtil.createAlertDialog(
          title: Text('home_wallpaper_uploading'.tr),
          content: ValueListenableBuilder<double>(
            valueListenable: progress,
            builder: (context, v, _) {
              final pct = (v * 100).clamp(0, 100).toStringAsFixed(0);
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  LinearProgressIndicator(value: v <= 0 ? null : v),
                  const SizedBox(height: 12),
                  Text('$pct%'),
                ],
              );
            },
          ),
          actions: [
            TextButton(
              onPressed: () {
                cancelToken.cancel();
                Get.back();
              },
              child: Text('cancel'.tr),
            ),
          ],
        ),
        barrierDismissible: false,
      );

      Map<String, dynamic>? data;
      try {
        if (ApiController.instance.isP2pMode) {
          progress.value = 0.1;
          final uri = Uri.parse('$baseUrl/api/appearance/uploadWallpaper');
          final req = http.MultipartRequest('POST', uri)
            ..files.add(
              http.MultipartFile.fromBytes(
                'file',
                bytes,
                filename: filename,
              ),
            );
          if (token.isNotEmpty) {
            req.headers['Authorization'] = 'Bearer $token';
          }
          progress.value = 0.35;
          final resp = await ApiController.instance.sendP2pRequest(
            req,
            timeout: const Duration(minutes: 5),
            cancelFuture: cancelToken.whenCancel,
          );
          progress.value = 0.9;
          final rawBytes = await resp.stream.toBytes();
          final rawText = utf8.decode(rawBytes);
          final raw = jsonDecode(rawText);
          if (raw is Map && raw['success'] == true && raw['data'] is Map) {
            data = Map<String, dynamic>.from(raw['data'] as Map);
          } else {
            final msg = raw is Map ? raw['message']?.toString() : null;
            ToastUtil.show(msg ?? 'home_wallpaper_upload_failed'.tr);
          }
        } else {
          final mp = dio.MultipartFile.fromBytes(bytes, filename: filename);
          final formData = dio.FormData.fromMap({'file': mp});
          final resp = await d.post(
            '$baseUrl/api/appearance/uploadWallpaper',
            data: formData,
            cancelToken: cancelToken,
            onSendProgress: (sent, total) {
              if (total > 0) {
                progress.value = (sent / total).clamp(0, 1);
              }
            },
          );
          final raw = resp.data;
          if (raw is Map && raw['success'] == true && raw['data'] is Map) {
            data = Map<String, dynamic>.from(raw['data'] as Map);
          } else {
            final msg = raw is Map ? raw['message']?.toString() : null;
            ToastUtil.show(msg ?? 'home_wallpaper_upload_failed'.tr);
          }
        }
        progress.value = 1;
      } on dio.DioException catch (e) {
        if (e.type == dio.DioExceptionType.cancel) {
          ToastUtil.show('cancelled'.tr);
          return;
        }
        final msg = e.response?.data is Map
            ? (e.response?.data['message']?.toString())
            : null;
        ToastUtil.show(msg ?? 'home_wallpaper_upload_failed'.tr);
        return;
      } on http.ClientException catch (_) {
        ToastUtil.show('home_wallpaper_upload_failed'.tr);
        return;
      } on FormatException {
        ToastUtil.show('home_wallpaper_upload_failed'.tr);
        return;
      } catch (_) {
        if (cancelToken.isCancelled) {
          ToastUtil.show('cancelled'.tr);
          return;
        }
        ToastUtil.show('home_wallpaper_upload_failed'.tr);
        return;
      } finally {
        progress.dispose();
        if (Get.isDialogOpen == true) {
          Get.back();
        }
      }

      final uploadedName = data?['name']?.toString().trim();
      if (uploadedName != null && uploadedName.isNotEmpty && mounted) {
        setState(() {
          _mode = 'fixed';
          _selectedName = uploadedName;
        });
      }

      await _loadWallpapers();
      ToastUtil.show('home_wallpaper_upload_success'.tr);
    } catch (_) {
      ToastUtil.show('home_wallpaper_upload_failed'.tr);
    }
  }

  Future<void> _deleteCustomWallpaper(String name) async {
    final theme = Theme.of(context);
    final ok = await Get.dialog<bool>(
      DialogUtil.createAlertDialog(
        title: Text('home_wallpaper_delete_confirm_title'.tr),
        content: Text(
          'home_wallpaper_delete_confirm_content'.trParams({'name': name}),
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(result: false),
            child: Text('cancel'.tr),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: theme.colorScheme.error,
              foregroundColor: theme.colorScheme.onError,
            ),
            onPressed: () => Get.back(result: true),
            child: Text('delete'.tr),
          ),
        ],
      ),
    );
    if (ok != true) return;

    final resp = await AppearanceApiService.instance.deleteWallpaper(
      name: name,
    );
    if (!resp.success || resp.data is! Map) {
      ToastUtil.show(resp.message ?? 'delete_failed'.tr);
      return;
    }
    final data = Map<String, dynamic>.from(resp.data as Map);
    final fallback = data['fallback'];
    if (fallback is Map) {
      CurrentUserController.instance.setWallpaper(
        Map<String, dynamic>.from(fallback),
      );
    }

    if (mounted) {
      setState(() {
        if (_selectedName == name) {
          _selectedName = null;
        }
      });
    }

    await _loadWallpapers();
    ToastUtil.show('delete_success'.tr);
  }

  Widget _buildUploadCard(ThemeData theme, double itemSize) {
    final borderColor = theme.colorScheme.onSurface.withValues(alpha: 0.12);
    final fg = theme.colorScheme.onSurface.withValues(alpha: 0.75);
    return InkWell(
      onTap: _uploadCustomWallpaper,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: borderColor),
          color: theme.colorScheme.surface,
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.upload_file, size: itemSize * 0.35, color: fg),
              const SizedBox(height: 6),
              Text(
                'home_wallpaper_upload'.tr,
                style: theme.textTheme.bodySmall?.copyWith(color: fg),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final supportsWallpaperPreview = ApiController.instance.isServerVersionAtLeast(
      5,
      unknownAsSupported: false,
    );
    final padding = MediaQuery.paddingOf(context);
    final topPadding = padding.top + 8;
    final bottomPadding = padding.bottom + 16;

    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 顶部：标题 + 随机/固定
          Padding(
            padding: EdgeInsets.fromLTRB(16, topPadding, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'home_wallpaper_title'.tr,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    FilterChip(
                      label: Text('home_wallpaper_random'.tr),
                      selected: _mode == 'random',
                      onSelected: (s) {
                        if (s) {
                          setState(() {
                            _mode = 'random';
                            _selectedName = null;
                          });
                        }
                        return;
                      },
                    ),
                    const SizedBox(width: 12),
                    FilterChip(
                      label: Text('home_wallpaper_fixed'.tr),
                      selected: _mode == 'fixed',
                      onSelected: (s) {
                        if (s) {
                          setState(() {
                            _mode = 'fixed';
                          });
                        }
                        return;
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
          // 中间：自适应 GridView
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(_error!),
                        ),
                      )
                    : LayoutBuilder(
                        builder: (context, constraints) {
                          const spacing = 10.0;
                          const aspectRatio = 4 / 3;
                          final width = constraints.maxWidth;
                          final crossCount = (width / (100 + spacing)).floor().clamp(2, 4);

                          return GridView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            gridDelegate:
                                SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: crossCount,
                              mainAxisSpacing: spacing,
                              crossAxisSpacing: spacing,
                              childAspectRatio: aspectRatio,
                            ),
                            itemCount: _wallpapers.length + 1,
                            itemBuilder: (context, index) {
                              if (index == _wallpapers.length) {
                                final size = width / crossCount - spacing;
                                return _buildUploadCard(theme, size);
                              }
                              final item = _wallpapers[index];
                              final name = (item['name'] ?? '').toString();
                              final isCustom =
                                  (item['source'] ?? '').toString() == 'custom' ||
                                  (item['url'] ?? '').toString().contains(
                                        '/customWallpaper/',
                                      );
                              final previewUrl = ApiController.instance.getWallpaperAssetUrl(
                                ((supportsWallpaperPreview
                                                ? item['previewUrl']
                                                : null) ??
                                            item['url'] ??
                                            '')
                                        .toString(),
                              );
                              final selected = _selectedName == name;
                              return InkWell(
                                onTap: _mode == 'fixed'
                                    ? () {
                                        setState(() {
                                          _selectedName = name;
                                        });
                                      }
                                    : null,
                                borderRadius: BorderRadius.circular(8),
                                child: Stack(
                                  clipBehavior: Clip.antiAlias,
                                  children: [
                                    AnimatedContainer(
                                      duration: const Duration(milliseconds: 150),
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: selected
                                              ? theme.colorScheme.primary
                                              : Colors.transparent,
                                          width: 2,
                                        ),
                                      ),
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(6),
                                        child: SizedBox.expand(
                                          child: CustomExtendedImage(
                                            imageUrl: previewUrl,
                                            fit: BoxFit.cover,
                                          ),
                                        ),
                                      ),
                                    ),
                                    if (isCustom)
                                      Positioned(
                                        right: 4,
                                        top: 4,
                                        child: Material(
                                          color: theme.colorScheme.surface
                                              .withValues(alpha: 0.9),
                                          borderRadius: BorderRadius.circular(6),
                                          child: InkWell(
                                            borderRadius: BorderRadius.circular(6),
                                            onTap: () => _deleteCustomWallpaper(name),
                                            child: Padding(
                                              padding: const EdgeInsets.all(4),
                                              child: Icon(
                                                Icons.delete_outline,
                                                size: 16,
                                                color: theme.colorScheme.error,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    if (selected)
                                      Positioned(
                                        left: 4,
                                        top: 4,
                                        child: Container(
                                          decoration: BoxDecoration(
                                            color: theme.colorScheme.primary,
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          padding: const EdgeInsets.all(2),
                                          child: const Icon(
                                            Icons.check,
                                            size: 14,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              );
                            },
                          );
                        },
                      ),
          ),
          // 底部：取消 + 应用
          Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, bottomPadding),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Get.back(),
                    child: Text('home_wallpaper_cancel'.tr),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: _mode == 'fixed' && _selectedName == null
                        ? null
                        : _apply,
                    child: Text('home_wallpaper_apply'.tr),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
