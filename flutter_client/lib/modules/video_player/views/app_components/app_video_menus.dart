import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../controllers/video_player_controller.dart';
import '../../playback/playback_engine_type.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import '../../../../core/api/api_controller.dart';
import '../../../../core/api/dio_bad_certificate_compat.dart';
import 'package:dio/dio.dart' as dio;
import '../../../../utils/toast_util.dart';
import '../../../../utils/dialog_util.dart';
import '../../../../utils/http_util.dart';
import '../../../files/views/folder_picker_dialog.dart';

class AppVideoMenus {
  static Widget _tailEllipsisText(
    String text, {
    TextStyle? style,
    int maxLines = 2,
  }) {
    // Trick: render RTL so ellipsis appears at the "start", keeping tail visible.
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Text(
        text,
        style: style,
        maxLines: maxLines,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.left,
      ),
    );
  }

  static Future<List<Map<String, dynamic>>> _searchSubtitles({
    required String baseUrl,
    required String token,
    required String videoPath,
    required String searchType,
    String keyword = '',
  }) async {
    final res = await HttpUtil.post(
      '$baseUrl/api/videoPlayer/searchSubtitle',
      body: {
        'filePath': videoPath,
        'searchType': searchType,
        if (keyword.trim().isNotEmpty) 'keyword': keyword.trim(),
      },
      headers: token.isNotEmpty ? {'Authorization': 'Bearer $token'} : null,
    );
    if (!res.isOk) {
      throw Exception('player_subtitle_search_failed'.tr);
    }
    final json = res.json;
    final data = (json != null && json['data'] is Map)
        ? Map<String, dynamic>.from(json['data'] as Map)
        : <String, dynamic>{};
    final raw = data['items'];
    if (raw is! List) return <Map<String, dynamic>>[];
    return raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList(growable: false);
  }

  static Future<void> showSubtitleSearchDialog(
    BuildContext context,
    PlayerController controller,
  ) async {
    if (!ApiController.instance.isServerVersionAtLeast(6)) {
      DialogUtil.showInfoDialog(
        title: 'tip'.tr,
        content: 'server_version_too_low'.tr,
      );
      return;
    }

    final videoPath = controller.currentSourcePathForInfo();
    if (videoPath.isEmpty) {
      ToastUtil.show('player_cannot_get_video_path'.tr);
      return;
    }

    final baseUrl = ApiController.instance.baseUrl.trim();
    final token = ApiController.instance.accessToken ?? '';

    final defaultKeyword = p.basenameWithoutExtension(videoPath).trim();

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E2C),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      isScrollControlled: true,
      builder: (_) {
        return DefaultTabController(
          length: 2,
          child: _SubtitleSearchSheet(
            controller: controller,
            baseUrl: baseUrl,
            token: token,
            videoPath: videoPath,
            defaultKeyword: defaultKeyword,
          ),
        );
      },
    );
  }

  static Widget _buildChip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white10,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white12),
      ),
      child: Text(
        text,
        style: const TextStyle(color: Colors.white70, fontSize: 12),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  static void showSpeedMenu(BuildContext context, PlayerController controller) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E2C),
      builder: (_) => Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'player_play_speed'.tr,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 16,
              children: [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]
                  .map(
                    (speed) => ActionChip(
                      label: Text('${speed}x'),
                      backgroundColor: controller.playbackSpeed.value == speed
                          ? Colors.blueAccent
                          : Colors.grey[800],
                      labelStyle: const TextStyle(color: Colors.white),
                      onPressed: () {
                        controller.setSpeed(speed);
                        Get.back();
                      },
                    ),
                  )
                  .toList(),
            ),
          ],
        ),
      ),
    );
  }

  static void showQualityMenu(
    BuildContext context,
    PlayerController controller,
  ) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E2C),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) {
        final options = controller.qualityOptions.toList(growable: false);
        final selected = controller.currentQuality.value;
        return Container(
          padding: const EdgeInsets.all(16),
          constraints: BoxConstraints(maxHeight: Get.height * 0.6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'player_choose_quality'.tr,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Get.back(),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Flexible(
                child: ListView.builder(
                  itemCount: options.length,
                  itemBuilder: (context, index) {
                    final q = options[index];
                    final title = controller.qualityLabelShort(q);
                    return ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        title,
                        style: const TextStyle(color: Colors.white),
                      ),
                      trailing: selected == q
                          ? const Icon(Icons.check, color: Colors.blueAccent)
                          : null,
                      onTap: () {
                        Get.back();
                        controller.changeQuality(q);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  static void showLoopModeMenu(
    BuildContext context,
    PlayerController controller,
  ) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E2C),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) {
        final options = <String>['sequence', 'single', 'all', 'shuffle'];
        final selected = controller.loopMode.value;
        final labelMap = {
          'sequence': 'player_loop_sequence'.tr,
          'single': 'player_loop_single'.tr,
          'all': 'player_loop_all'.tr,
          'shuffle': 'player_loop_shuffle'.tr,
        };
        return Container(
          padding: const EdgeInsets.all(16),
          constraints: BoxConstraints(maxHeight: Get.height * 0.6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'player_loop'.tr,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Get.back(),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Flexible(
                child: ListView.builder(
                  itemCount: options.length,
                  itemBuilder: (context, index) {
                    final mode = options[index];
                    final label = labelMap[mode] ?? mode;
                    return ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        label,
                        style: const TextStyle(color: Colors.white),
                      ),
                      trailing: selected == mode
                          ? const Icon(Icons.check, color: Colors.blueAccent)
                          : null,
                      onTap: () {
                        Get.back();
                        controller.setLoopMode(mode);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  static void showSubtitleMenu(
    BuildContext context,
    PlayerController controller,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1E1E2C),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) {
        final sheetHeight = MediaQuery.of(sheetContext).size.height * 0.85;
        return SizedBox(
          height: sheetHeight,
          child: Container(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'player_subtitle'.tr,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => Get.back(),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.search, color: Colors.white70),
                title: Text(
                  'player_subtitle_search'.tr,
                  style: const TextStyle(color: Colors.white),
                ),
                onTap: () async {
                  Get.back();
                  await showSubtitleSearchDialog(context, controller);
                },
              ),
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.cloud, color: Colors.white70),
                title: Text(
                  'player_choose_server_subtitle'.tr,
                  style: TextStyle(color: Colors.white),
                ),
                onTap: () async {
                  Get.back();
                  final picked = await showFolderPickerBottomSheet(
                    context,
                    multiSelect: false,
                    allowFileSelect: true,
                  );
                  final subPath = (picked != null && picked.isNotEmpty)
                      ? picked.first.trim()
                      : '';
                  if (subPath.isEmpty) return;
                  final ext = p.extension(subPath).toLowerCase();
                  const exts = {'.srt', '.ass', '.vtt', '.ssa', '.sub', '.mks'};
                  if (!exts.contains(ext)) {
                    ToastUtil.show(
                      'player_subtitle_format_unsupported'.trParams({'ext': ext}),
                    );
                    return;
                  }
                  await controller.addAndSelectExternalSubtitle(
                    subtitlePath: subPath,
                    filename: p.basename(subPath),
                  );
                },
              ),
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.upload_file, color: Colors.white70),
                title: Text(
                  'player_upload_subtitle'.tr,
                  style: TextStyle(color: Colors.white),
                ),
                onTap: () async {
                  Get.back();
                  final result = await FilePicker.platform.pickFiles(
                    allowMultiple: false,
                    type: FileType.custom,
                    allowedExtensions: const [
                      'srt',
                      'ass',
                      'vtt',
                      'ssa',
                      'sub',
                      'mks',
                    ],
                    withData: false,
                  );
                  final file = (result != null && result.files.isNotEmpty)
                      ? result.files.first
                      : null;
                  if (file == null) return;
                  final localPath = file.path?.trim() ?? '';
                  if (localPath.isEmpty) {
                    ToastUtil.show('player_pick_local_subtitle_hint'.tr);
                    return;
                  }
                  final videoPath = controller.currentSourcePathForInfo();
                  if (videoPath.isEmpty) {
                    ToastUtil.show('player_cannot_get_video_path'.tr);
                    return;
                  }
                  try {
                    final base = ApiController.instance.baseUrl.trim();
                    final token = ApiController.instance.accessToken ?? '';
                    final client = createDioWithBadCertificateCompat(
                      dio.BaseOptions(
                        baseUrl: base,
                        headers: {
                          if (token.isNotEmpty) 'Authorization': 'Bearer $token',
                        },
                        validateStatus: (_) => true,
                      ),
                    );
                    final mp = await dio.MultipartFile.fromFile(
                      localPath,
                      filename: file.name.trim().isEmpty
                          ? p.basename(localPath)
                          : file.name.trim(),
                    );
                    final form = dio.FormData.fromMap({
                      'filePath': videoPath,
                      'file': mp,
                    });
                    final resp = await client.post(
                      '/api/videoPlayer/uploadSubtitle',
                      data: form,
                      options: dio.Options(contentType: 'multipart/form-data'),
                    );
                    final body = resp.data is Map
                        ? Map<String, dynamic>.from(resp.data as Map)
                        : <String, dynamic>{};
                    final ok = body['success'] == true || body['success'] == 'true';
                    if (!ok) {
                      final msg =
                          body['message']?.toString() ?? 'operation_failed'.tr;
                      throw Exception(msg);
                    }
                    final data = body['data'] is Map
                        ? Map<String, dynamic>.from(body['data'] as Map)
                        : <String, dynamic>{};
                    final savedPath = data['path']?.toString().trim() ?? '';
                    final filename = data['filename']?.toString().trim() ?? '';
                    if (savedPath.isEmpty || filename.isEmpty) {
                      throw Exception('operation_failed'.tr);
                    }
                    await controller.addAndSelectExternalSubtitle(
                      subtitlePath: savedPath,
                      filename: filename,
                      source: 'uploaded',
                    );
                    ToastUtil.show('player_subtitle_upload_success'.tr);
                  } catch (e) {
                    ToastUtil.show(e.toString());
                  }
                },
              ),
                const Divider(color: Colors.white24),
                Expanded(
                  child: Obx(() {
                    final tracks =
                        controller.subtitleTracks.toList(growable: false);
                    final selected = controller.currentSubtitleTrack.value;
                    controller.rawSubtitleTracks.length;
                    return ListView.builder(
                      itemCount: tracks.length,
                      itemBuilder: (context, index) {
                        final t = tracks[index];
                        final checked = t == selected;
                        final external = (() {
                          for (final e in controller.rawSubtitleTracks) {
                            if (e['isExternal'] == true && e['label'] == t) {
                              return e;
                            }
                          }
                          return null;
                        })();
                        final externalPath = external != null
                            ? external['path']?.toString().trim() ?? ''
                            : '';
                        final externalSource = external != null
                            ? external['source']?.toString().trim() ?? ''
                            : '';
                        final canDeleteExternal = externalPath.isNotEmpty &&
                            externalSource.isNotEmpty;
                        return ListTile(
                          dense: true,
                          leading: index == 0
                              ? const SizedBox(width: 28)
                              : Container(
                                  alignment: Alignment.centerLeft,
                                  width: 28,
                                  child: Text(
                                    '$index.',
                                    style: const TextStyle(
                                      color: Colors.white54,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                          title: _tailEllipsisText(
                            t,
                            style: const TextStyle(color: Colors.white),
                            maxLines: 2,
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (canDeleteExternal)
                                IconButton(
                                  tooltip: 'player_subtitle_delete'.tr,
                                  icon: const Icon(
                                    Icons.delete,
                                    color: Colors.white70,
                                    size: 18,
                                  ),
                                  onPressed: () async {
                                    await controller.deleteExternalSubtitle(
                                      subtitlePath: externalPath,
                                    );
                                  },
                                ),
                              if (checked)
                                const Icon(
                                  Icons.check,
                                  color: Colors.blueAccent,
                                ),
                            ],
                          ),
                          onTap: () {
                            Get.back();
                            controller.setSubtitleTrack(t);
                          },
                        );
                      },
                    );
                  }),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  static void showAudioMenu(BuildContext context, PlayerController controller) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E2C),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) {
        final tracks = controller.audioTracks.isEmpty
            ? <String>['default'.tr]
            : controller.audioTracks.toList(growable: false);
        final selected = controller.currentAudioTrack.value;
        return Container(
          padding: const EdgeInsets.all(16),
          constraints: BoxConstraints(maxHeight: Get.height * 0.6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'player_choose_audio'.tr,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Get.back(),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Flexible(
                child: ListView.builder(
                  itemCount: tracks.length,
                  itemBuilder: (context, index) {
                    final t = tracks[index];
                    final checked = t == selected;
                    return ListTile(
                      dense: true,
                      title: Text(
                        t,
                        style: const TextStyle(color: Colors.white),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: checked
                          ? const Icon(Icons.check, color: Colors.blueAccent)
                          : null,
                      onTap: () {
                        Get.back();
                        controller.setAudioTrack(t);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  static void showPlaybackEngineMenu(
    BuildContext context,
    PlayerController controller,
  ) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E2C),
      builder: (_) => Obx(() {
        final current = controller.playbackEngineType.value;
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: Text(
                  'player_engine_fvp'.tr,
                  style: const TextStyle(color: Colors.white),
                ),
                trailing: current == PlaybackEngineType.fvp
                    ? const Icon(Icons.check, color: Colors.white)
                    : null,
                onTap: () {
                  Get.back();
                  controller.switchPlaybackEngine(PlaybackEngineType.fvp);
                },
              ),
              ListTile(
                title: Text(
                  'player_engine_media3'.tr,
                  style: const TextStyle(color: Colors.white),
                ),
                trailing: current == PlaybackEngineType.media3
                    ? const Icon(Icons.check, color: Colors.white)
                    : null,
                onTap: () {
                  Get.back();
                  controller.switchPlaybackEngine(PlaybackEngineType.media3);
                },
              ),
            ],
          ),
        );
      }),
    );
  }

  static void showMoreMenu(BuildContext context, PlayerController controller) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E2C),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => Container(
        padding: const EdgeInsets.all(16),
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.6,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'player_operation'.tr,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Get.back(),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              GridView.count(
                crossAxisCount: 4,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 16,
                crossAxisSpacing: 16,
                children: [
                  if (!controller.isUrlSource.value)
                    _buildMenuItem(Icons.subtitles, 'player_subtitle'.tr, () {
                      Get.back();
                      showSubtitleMenu(context, controller);
                    }),
                  if (!controller.isUrlSource.value)
                    _buildMenuItem(
                      Icons.audiotrack,
                      'player_choose_audio'.tr,
                      () {
                        Get.back();
                        showAudioMenu(context, controller);
                      },
                    ),
                  // _buildMenuItem(Icons.cast, 'player_cast'.tr, () {
                  //   Get.back();
                  // }),
                  _buildMenuItem(Icons.loop, 'player_loop'.tr, () {
                    Get.back();
                    showLoopModeMenu(context, controller);
                  }),
                  if (controller.canUseMedia3Engine)
                    _buildMenuItem(
                      Icons.memory,
                      'player_playback_engine'.tr,
                      () {
                        Get.back();
                        showPlaybackEngineMenu(context, controller);
                      },
                    ),
                  // _buildMenuItem(
                  //   Icons.settings,
                  //   'player_advanced_settings'.tr,
                  //   () {},
                  // ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Widget _buildMenuItem(
    IconData icon,
    String label,
    VoidCallback onTap,
  ) {
    return InkWell(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 28),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _SubtitleSearchSheet extends StatefulWidget {
  const _SubtitleSearchSheet({
    required this.controller,
    required this.baseUrl,
    required this.token,
    required this.videoPath,
    required this.defaultKeyword,
  });

  final PlayerController controller;
  final String baseUrl;
  final String token;
  final String videoPath;
  final String defaultKeyword;

  @override
  State<_SubtitleSearchSheet> createState() => _SubtitleSearchSheetState();
}

class _SubtitleSearchSheetState extends State<_SubtitleSearchSheet> {
  bool _loading = true;
  int _tabIndex = 0; // 0 feature, 1 keyword
  String _keyword = '';
  List<Map<String, dynamic>> _items = [];

  @override
  void initState() {
    super.initState();
    _keyword = widget.defaultKeyword;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _runFeatureThenMaybeFallback();
    });
  }

  Future<void> _runFeatureThenMaybeFallback() async {
    setState(() {
      _loading = true;
      _tabIndex = 0;
      _items = [];
    });
    try {
      final feature = await AppVideoMenus._searchSubtitles(
        baseUrl: widget.baseUrl,
        token: widget.token,
        videoPath: widget.videoPath,
        searchType: 'feature',
      );
      if (!mounted) return;
      if (feature.isNotEmpty) {
        setState(() {
          _loading = false;
          _tabIndex = 0;
          _items = feature;
        });
        DefaultTabController.of(context).animateTo(0);
        return;
      }

      // auto fallback to keyword
      final kw = _keyword.trim();
      final keywordItems = await AppVideoMenus._searchSubtitles(
        baseUrl: widget.baseUrl,
        token: widget.token,
        videoPath: widget.videoPath,
        searchType: 'keyword',
        keyword: kw,
      );
      if (!mounted) return;
      setState(() {
        _loading = false;
        _tabIndex = 1;
        _items = keywordItems;
      });
      DefaultTabController.of(context).animateTo(1);
      if (keywordItems.isEmpty) {
        ToastUtil.show('player_subtitle_search_no_results'.tr);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ToastUtil.show(e.toString());
    }
  }

  Future<void> _runSearch({required int tabIndex}) async {
    setState(() {
      _loading = true;
      _tabIndex = tabIndex;
      _items = [];
    });
    try {
      final items = await AppVideoMenus._searchSubtitles(
        baseUrl: widget.baseUrl,
        token: widget.token,
        videoPath: widget.videoPath,
        searchType: tabIndex == 0 ? 'feature' : 'keyword',
        keyword: _keyword,
      );
      if (!mounted) return;
      setState(() {
        _loading = false;
        _items = items;
      });
      if (items.isEmpty) {
        ToastUtil.show('player_subtitle_search_no_results'.tr);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ToastUtil.show(e.toString());
    }
  }

  Future<void> _downloadItem(Map<String, dynamic> it, int index) async {
    final sname = it['sname']?.toString().trim() ?? '';
    final displayName = it['displayName']?.toString().trim() ?? '';
    final language = it['language']?.toString().trim() ?? '';
    final title = displayName.isNotEmpty
        ? displayName
        : (sname.isNotEmpty ? sname : 'subtitle');
    final surl = it['surl']?.toString().trim() ?? '';
    if (surl.isEmpty) return;

    Get.dialog(
      AlertDialog(
        backgroundColor: const Color(0xFF1E1E2C),
        title: Text(
          'player_subtitle_downloading'.tr,
          style: const TextStyle(color: Colors.white),
        ),
        content: Row(
          children: [
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(color: Colors.white70),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
      barrierDismissible: false,
    );

    try {
      final res = await HttpUtil.post(
        '${widget.baseUrl}/api/videoPlayer/downloadSearchedSubtitle',
        body: {
          'filePath': widget.videoPath,
          'surl': surl,
          'sname': sname,
          'language': language,
        },
        headers: widget.token.isNotEmpty
            ? {'Authorization': 'Bearer ${widget.token}'}
            : null,
      );
      if (!res.isOk) {
        throw Exception(res.errorMessage);
      }
      final json = res.json;
      final data = (json != null && json['data'] is Map)
          ? Map<String, dynamic>.from(json['data'] as Map)
          : <String, dynamic>{};
      final savedPath = data['path']?.toString().trim() ?? '';
      final filename = data['filename']?.toString().trim() ?? '';
      if (savedPath.isEmpty || filename.isEmpty) {
        throw Exception('operation_failed'.tr);
      }
      Get.back(); // close downloading
      await widget.controller.addAndSelectExternalSubtitle(
        subtitlePath: savedPath,
        filename: filename,
        source: 'searched',
      );
      ToastUtil.show('player_subtitle_download_success'.tr);
    } catch (e) {
      Get.back(); // close downloading
      ToastUtil.show(e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).viewInsets.bottom;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: bottomPadding),
        child: Container(
          padding: const EdgeInsets.all(16),
          constraints: BoxConstraints(maxHeight: Get.height * 0.75),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'player_subtitle_search_results'.tr,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Get.back(),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TabBar(
                onTap: (i) {
                  _tabIndex = i;
                  _runSearch(tabIndex: i);
                },
                tabs: [
                  Tab(text: 'player_subtitle_search_feature'.tr),
                  Tab(text: 'player_subtitle_search_keyword'.tr),
                ],
              ),
              const SizedBox(height: 10),
              if (_tabIndex == 1)
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: TextEditingController(text: _keyword)
                          ..selection = TextSelection.fromPosition(
                            TextPosition(offset: _keyword.length),
                          ),
                        onChanged: (v) => _keyword = v,
                        onSubmitted: (_) => _runSearch(tabIndex: 1),
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          isDense: true,
                          hintText: 'player_subtitle_keyword_hint'.tr,
                          hintStyle: const TextStyle(color: Colors.white38),
                          filled: true,
                          fillColor: Colors.white10,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    ElevatedButton(
                      onPressed: _loading ? null : () => _runSearch(tabIndex: 1),
                      child: Text('player_subtitle_search_action'.tr),
                    ),
                  ],
                ),
              if (_tabIndex == 1) const SizedBox(height: 10),
              if (_loading)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: Row(
                    children: [
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'player_subtitle_searching'.tr,
                          style: const TextStyle(color: Colors.white70),
                        ),
                      ),
                    ],
                  ),
                ),
              Flexible(
                child: _items.isEmpty
                    ? Center(
                        child: Text(
                          _loading
                              ? ''
                              : 'player_subtitle_search_no_results'.tr,
                          style: const TextStyle(color: Colors.white54),
                        ),
                      )
                    : ListView.separated(
                        itemCount: _items.length,
                        separatorBuilder: (_, __) =>
                            const Divider(color: Colors.white12, height: 1),
                        itemBuilder: (context2, index) {
                          final it = _items[index];
                          final sname = it['sname']?.toString().trim() ?? '';
                          final displayName =
                              it['displayName']?.toString().trim() ?? '';
                          final language = it['language']?.toString().trim() ?? '';
                          final ext = it['ext']?.toString().trim() ?? '';
                          final title = displayName.isNotEmpty
                              ? displayName
                              : (sname.isNotEmpty ? sname : 'subtitle');
                          final langText = language.isNotEmpty
                              ? language
                              : 'player_subtitle_language_unknown'.tr;
                          final typeText = ext.isNotEmpty ? ext : '-';

                          return ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: Container(
                              alignment: Alignment.centerLeft,
                              width: 28,
                              child: Text(
                                '${index + 1}.',
                                style: const TextStyle(
                                  color: Colors.white54,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            title: Text(
                              title,
                              style: const TextStyle(color: Colors.white),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Wrap(
                                spacing: 10,
                                runSpacing: 6,
                                children: [
                                  AppVideoMenus._buildChip(
                                    '${'player_subtitle_language'.tr}: $langText',
                                  ),
                                  AppVideoMenus._buildChip(
                                    '${'player_subtitle_type'.tr}: $typeText',
                                  ),
                                ],
                              ),
                            ),
                            trailing: const Icon(
                              Icons.download,
                              color: Colors.white70,
                            ),
                            onTap: () => _downloadItem(it, index),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
