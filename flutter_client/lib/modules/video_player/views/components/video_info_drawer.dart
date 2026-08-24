import 'dart:ui';
import 'package:NasCabOS/utils/device_utils.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../../core/api/api_controller.dart';
import '../../../../utils/http_util.dart';
import '../../controllers/video_player_controller.dart';
import '../../../../utils/file_util.dart';

class VideoInfoDrawer extends StatefulWidget {
  final String filePath;
  final PlayerController playerController;

  const VideoInfoDrawer({
    super.key,
    required this.filePath,
    required this.playerController,
  });

  @override
  State<VideoInfoDrawer> createState() => _VideoInfoDrawerState();
}

class _VideoInfoDrawerState extends State<VideoInfoDrawer> {
  Map<String, dynamic>? _basicInfo;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchBasicInfo();
  }

  Future<void> _fetchBasicInfo() async {
    try {
      final baseUrl = ApiController.instance.baseUrl;
      final token = ApiController.instance.accessToken;
      final res = await HttpUtil.get(
        '$baseUrl/api/file/attributes?path=${Uri.encodeComponent(widget.filePath)}',
        headers: token != null ? {'Authorization': 'Bearer $token'} : null,
      );

      if (res.isOk && res.json != null) {
        if (mounted) {
          setState(() {
            _basicInfo = res.json!['data'];
            _loading = false;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _error = res.json?['message'] ?? 'Failed to load info';
            _loading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  String _formatDuration(Duration duration) {
    final h = duration.inHours;
    final m = duration.inMinutes.remainder(60);
    final s = duration.inSeconds.remainder(60);
    if (h > 0) {
      return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Get.isDarkMode;
    final textColor = isDark ? Colors.white : Colors.black87;
    final subTextColor = isDark ? Colors.white70 : Colors.black54;
    final cardColor = isDark
        ? Colors.white.withOpacity(0.1)
        : Colors.black.withOpacity(0.05);

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          constraints: BoxConstraints(maxHeight: Get.height * 0.7),
          decoration: BoxDecoration(
            color: isDark
                ? Colors.black.withOpacity(0.8)
                : Colors.white.withOpacity(0.9),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            border: Border(
              top: BorderSide(color: isDark ? Colors.white24 : Colors.black12),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Handle bar
              Center(
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 12),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white24 : Colors.black12,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 8,
                ),
                child: Text(
                  'video_info'.tr,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: textColor,
                  ),
                ),
              ),

              if (_loading)
                const SizedBox(
                  height: 200,
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_error != null)
                SizedBox(
                  height: 200,
                  child: Center(
                    child: Text(
                      _error!,
                      style: const TextStyle(color: Colors.redAccent),
                    ),
                  ),
                )
              else
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 30),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 基础信息
                        _buildSectionTitle('basic_info'.tr, textColor),
                        const SizedBox(height: 12),
                        _buildInfoRow(
                          'filename'.tr,
                          _basicInfo?['name'] ?? '',
                          textColor,
                          subTextColor,
                        ),
                        _buildInfoRow(
                          'path'.tr,
                          _basicInfo?['path'] ?? '',
                          textColor,
                          subTextColor,
                        ),
                        _buildInfoRow(
                          'size'.tr,
                          FileUtil.formatSize(_basicInfo?['size'] ?? 0),
                          textColor,
                          subTextColor,
                        ),
                        // 优先使用 Controller 中的时长
                        _buildInfoRow(
                          'duration'.tr,
                          _formatDuration(
                            widget.playerController.duration.value,
                          ),
                          textColor,
                          subTextColor,
                        ),

                        const SizedBox(height: 24),

                        // 媒体流信息 (从 Controller 获取)
                        _buildSectionTitle('media_streams'.tr, textColor),
                        const SizedBox(height: 12),
                        _buildStreamsList(cardColor, textColor, subTextColor),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title, Color color) {
    return Text(
      title,
      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: color),
    );
  }

  Widget _buildInfoRow(
    String label,
    String value,
    Color textColor,
    Color subTextColor,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: TextStyle(color: subTextColor, fontSize: 14),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(color: textColor, fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStreamsList(
    Color cardColor,
    Color textColor,
    Color subTextColor,
  ) {
    final videoStreams = widget.playerController.rawVideoTracks;
    final audioStreams = widget.playerController.rawAudioTracks;
    final subtitleStreams = widget.playerController.rawSubtitleTracks;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (videoStreams.isNotEmpty) ...[
          _buildStreamCategory(
            'video_stream'.tr,
            videoStreams,
            Icons.videocam,
            cardColor,
            textColor,
            subTextColor,
          ),
          const SizedBox(height: 16),
        ],
        if (audioStreams.isNotEmpty) ...[
          _buildStreamCategory(
            'audio_stream'.tr,
            audioStreams,
            Icons.audiotrack,
            cardColor,
            textColor,
            subTextColor,
          ),
          const SizedBox(height: 16),
        ],
        if (subtitleStreams.isNotEmpty) ...[
          _buildStreamCategory(
            'subtitle_stream'.tr,
            subtitleStreams,
            Icons.subtitles,
            cardColor,
            textColor,
            subTextColor,
          ),
        ],
      ],
    );
  }

  Widget _buildStreamCategory(
    String title,
    List<Map<String, dynamic>> streams,
    IconData icon,
    Color cardColor,
    Color textColor,
    Color subTextColor,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              Icon(icon, size: 16, color: subTextColor),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  color: subTextColor,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: streams
              .map<Widget>(
                (s) => _buildStreamCard(s, cardColor, textColor, subTextColor),
              )
              .toList(),
        ),
      ],
    );
  }

  Widget _buildStreamCard(
    Map<String, dynamic> stream,
    Color cardColor,
    Color textColor,
    Color subTextColor,
  ) {
    final codec = stream['codec_name'] ?? 'unknown';
    final index = stream['index'] ?? -1;
    final lang = stream['tags']?['language'] ?? 'und';
    final title = stream['tags']?['title'];

    // Video specific
    final width = stream['width'];
    final height = stream['height'];

    // Audio specific
    final channels = stream['channels'];
    final sampleRate = stream['sample_rate'];

    // Calculate width based on screen width (2 columns for phone, more for tablet/desktop)
    final screenWidth = Get.width;
    // Padding 20*2 = 40, Spacing 12
    // If width < 600, use (width - 40 - 12) / 2
    double cardWidth = 160;
    if (DeviceUtils.isMobile) {
      cardWidth = (screenWidth - 40 - 12) / 2;
    }

    return Container(
      width: cardWidth,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: subTextColor.withOpacity(0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.blueAccent.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  //流序号 如果是-1 则是外置字幕
                  index == -1 ? 'subtitle_external'.tr : '$index',
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Colors.blueAccent,
                  ),
                ),
              ),
              Flexible(
                child: Text(
                  lang.toString().toUpperCase(),
                  style: TextStyle(fontSize: 10, color: subTextColor),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            codec.toString().toUpperCase(),
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: textColor,
            ),
          ),
          if (title != null)
            Tooltip(
              message: title,
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: subTextColor),
              ),
            ),
          const SizedBox(height: 4),
          if (width != null &&
              height != null &&
              width != "N/A" &&
              height != "N/A")
            Text(
              '${width}x$height',
              style: TextStyle(fontSize: 11, color: subTextColor),
            ),
          if (channels != null)
            Text(
              '$channels ch, ${sampleRate ?? ""}Hz',
              style: TextStyle(fontSize: 11, color: subTextColor),
            ),
        ],
      ),
    );
  }
}
