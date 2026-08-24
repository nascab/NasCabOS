import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:flutter_fullscreen/flutter_fullscreen.dart';
import '../../../core/api/api_controller.dart';
import 'package:uuid/uuid.dart';
import '../../../utils/dialog_util.dart';
import '../../../utils/http_util.dart';
import '../../../utils/toast_util.dart';
import '../../../utils/device_utils.dart';
import '../../../utils/user_agent_util.dart';
import '../../music/play_service/controller/music_play_service_controller.dart';
import '../cache/video_range_memory_cache.dart';
import '../playback/playback_engine.dart';
import '../playback/playback_engine_factory.dart';
import '../playback/playback_engine_type.dart';
import 'platform/video_platform.dart';
import '../subtitle/webvtt_parser.dart';

part 'parts/controls.dart';
part 'parts/lifecycle.dart';
part 'parts/playback.dart';
part 'parts/polling.dart';
part 'parts/transcode.dart';
part 'parts/window.dart';
part 'parts/stream.dart';
part 'parts/stream_info.dart';
part 'parts/autosave.dart';
part 'parts/auto_skip.dart';
part 'parts/resume.dart';
part 'parts/preference.dart';
part 'parts/listener.dart';
part 'parts/engine_switch.dart';
part 'parts/web_subtitle.dart';

/// 视频播放器控制器
/// 负责管理视频播放状态、播放列表、窗口管理等
class PlayerController extends GetxController with WindowListener {
  /// 播放列表 (包含视频文件信息的Map)
  final List<Map<String, dynamic>> playlist = [];

  /// 当前播放索引
  final RxInt currentIndex = 0.obs;

  /// path是个url 从加密空间来的一般这个标记是true
  final RxBool isUrlSource = false.obs;

  /// 播放内核（FVP / Media3 等）；必须为 Rx，否则 Obx 不会在赋值后挂载 PlatformView。
  final Rxn<PlaybackEngine> playbackEngine = Rxn<PlaybackEngine>();

  /// 当前使用的播放内核类型；Android 可在设置中切换。
  final Rx<PlaybackEngineType> playbackEngineType =
      defaultPlaybackEngineType().obs;

  Completer<void>? _media3SurfaceReady;
  int? _media3WaitInitGeneration;

  /// 原画↔转码切换时禁止 Media3 热切换（HLS ↔ 直链需完整重建）
  bool _disallowEngineHotSwap = false;

  /// 从转码切回原画后，音轨/字幕在首帧播放后再应用，避免 FVP 黑屏
  bool _deferOriginalTracksUntilPlaying = false;

  /// 是否已初始化
  final RxBool isInitialized = false.obs;

  /// 是否应挂载 [PlaybackVideoSurface]。
  /// Media3 须先创建 PlatformView 才能完成 openUrl，不能等 [isInitialized] 为 true。
  bool get shouldMountVideoSurface {
    final engine = playbackEngine.value;
    if (engine == null) return false;
    if (isInitialized.value) return true;
    return engine.type == PlaybackEngineType.media3;
  }

  /// 是否正在播放
  final RxBool isPlaying = false.obs;

  /// 当前播放位置
  final Rx<Duration> position = Duration.zero.obs;

  /// 视频总时长
  final Rx<Duration> duration = Duration.zero.obs;

  /// 缓冲位置
  final Rx<Duration> buffered = Duration.zero.obs;

  /// 播放速度
  final RxDouble playbackSpeed = 1.0.obs;

  /// 音量
  final RxDouble volume = 1.0.obs;

  /// 是否全屏
  final RxBool isFullscreen = false.obs;

  final RxBool isLandscape = false.obs;

  final RxBool isLocked = false.obs;
  final RxBool showLockedIcon = false.obs;
  Timer? _lockIconTimer;

  final RxBool isLooping = false.obs;

  final RxString loopMode = 'sequence'.obs;

  /// 控制栏是否显示
  final RxBool showControls = true.obs;

  /// 按住 Ctrl 加速播放中
  final RxBool isCtrlSpeedBoost = false.obs;

  /// Ctrl 加速前的速度，用于恢复
  double _speedBeforeCtrlBoost = 1.0;

  /// 恢复播放提示倒计时（0 表示不显示）
  final RxInt resumeTipCountdown = 0.obs;
  Timer? _resumeTipTimer;

  /// 隐藏控制栏的计时器
  Timer? _hideTimer;

  /// 自动保存计时器
  Timer? _autoSaveTimer;

  Timer? _transcodeSeekTimer;
  Timer? _positionPollTimer;
  bool _isPollingPosition = false;
  bool _restoreMaximizedAfterExitFullscreen = false;

  /// 单曲循环时防止「片尾 → seek(0) + play → 未及时更新 position → 再次触发片尾」的无限 pause/start 循环
  bool _singleLoopCooldown = false;
  Timer? _singleLoopCooldownTimer;

  Worker? _autoSkipWorker;
  int _openSkipStartSeconds = 0;
  int _openSkipEndSeconds = 0;
  bool _didApplyResumeForCurrentSource = false;
  bool _skipIntroConsumed = false;
  bool _skipOutroConsumed = false;
  bool _skipOutroSuppressedByResume = false;

  /// 原始音轨列表 (Map)
  final List<Map<String, dynamic>> _rawAudioTracks = [];

  /// 原始视频流列表 (Map)
  final List<Map<String, dynamic>> _rawVideoTracks = [];
  List<Map<String, dynamic>> get rawVideoTracks => _rawVideoTracks;
  List<Map<String, dynamic>> get rawAudioTracks => _rawAudioTracks;
  List<Map<String, dynamic>> get rawSubtitleTracks => _rawSubtitleTracks;

  /// 音轨列表 (Display Names)
  final RxList<String> audioTracks = <String>[].obs;
  final RxString currentAudioTrack = ''.obs;

  /// 原始字幕列表 (Map)
  final List<Map<String, dynamic>> _rawSubtitleTracks = [];

  /// 字幕列表 (Display Names)
  final RxList<String> subtitleTracks = <String>[].obs;
  final RxString currentSubtitleTrack = ''.obs;

  // Client subtitle overlay (Web + 非 Web 转码；与播放引擎解耦)
  final RxList<SubtitleCue> webSubtitleCues = <SubtitleCue>[].obs;
  final RxString webActiveSubtitleText = ''.obs;
  String _webSubtitleCacheKey = '';
  bool _webSubtitleLoading = false;

  /// 当前播放ID (用于转码)
  String? _playId;

  /// 当前播放质量 (original, 480p_1m, 720p_2m, 1080p_5m, 4k_10m ...)
  final RxString currentQuality = 'original'.obs;

  /// 质量列表
  final List<String> qualityOptions = [
    'original',
    '4k_20m',
    '4k_15m',
    '4k_10m',
    '1080p_8m',
    '1080p_5m',
    '1080p_3m',
    '1080p_2m',
    '720p_3m',
    '720p_2m',
    '720p_1m',
    '480p_1m',
  ];

  static const Map<String, String> _qualityLabelShortMap = {
    '4k_20m': '4K 20M',
    '4k_15m': '4K 15M',
    '4k_10m': '4K 10M',
    '1080p_8m': '1080P 8M',
    '1080p_5m': '1080P 5M',
    '1080p_3m': '1080P 3M',
    '1080p_2m': '1080P 2M',
    '720p_3m': '720P 3M',
    '720p_2m': '720P 2M',
    '720p_1m': '720P 1M',
    '480p_1m': '480P 1M',
  };

  String qualityLabelShort(String quality) {
    if (quality == 'original') return 'player_quality_original'.tr;
    return _qualityLabelShortMap[quality] ?? 'player_quality'.tr;
  }

  Map<String, dynamic>? _pendingPreference;
  Duration? _pendingResumePosition;

  /// 首帧 URL 已带 `seek=`（转码），避免再发起一次客户端 seek。
  int? _resumeSeekBakedIntoUrlSeconds;
  int? _sourceDurationSeconds; // 视频源总时长
  int? _sourceFileSizeBytes; // 文件大小（字节），用于 P2P 中继下大文件默认转码
  int ignoreFindSub = 1;
  int _transcodeBaseSeconds = 0; // 转码基础秒数
  int? _pendingTranscodeSeekSeconds;

  final String defaultTranscodeQuality = '1080p_3m'; // 默认转码质量
  int maxReloadRetries = 2; // 最大重试次数
  int _reloadRetryCount = 0; // 当前重试次数
  bool _isRecoveringFromError = false; // 是否正在从错误中恢复
  bool _isPlaybackErrorDialogOpen = false; // 是否正在显示播放出错对话框
  bool _autoSwitchedToTranscode = false; // 原画失败后是否已自动切转码（对齐 TV 端）
  late final _PlayerFullScreenRelay _fullScreenRelay = _PlayerFullScreenRelay(
    onChanged: _onFullScreenChanged,
  );

  String? _pendingInitKey;
  int _initGeneration = 0;
  bool _isClosingPlayer = false;
  static const MethodChannel _macosAudioOutputChannel = MethodChannel(
    'nascab.macos.audio_output',
  );

  @override
  void onInit() {
    super.onInit();
    _onControllerInit();
  }

  @override
  void onClose() {
    _onControllerClose();
    super.onClose();
  }

  void _onFullScreenChanged(bool enabled, SystemUiMode? systemUiMode) {
    if (isClosed) return;
    isFullscreen.value = enabled;
  }

  Future<void> openPlaylist({
    required List<Map<String, dynamic>> items,
    int initialIndex = 0,
    int? maxRetryCount,
  }) async {
    if (isClosed) return;
    final list = items.toList(growable: false);
    playlist
      ..clear()
      ..addAll(list);
    if (maxRetryCount != null && maxRetryCount >= 0) {
      maxReloadRetries = maxRetryCount;
    }
    final idx = list.isEmpty
        ? 0
        : initialIndex.clamp(0, max(0, list.length - 1)).toInt();
    currentIndex.value = idx;
    _reloadRetryCount = 0;
    _isRecoveringFromError = false;
    _isPlaybackErrorDialogOpen = false;
    _autoSwitchedToTranscode = false;
    _isClosingPlayer = false;
    final initKey = _pendingInitKey;
    if (initKey != null && initKey.isNotEmpty) {
      cancelVideoControllerInit(initKey);
      _pendingInitKey = null;
    }
    if (playlist.isEmpty) return;
    await loadPlaybackEnginePreference();
    await _initializePlayer(keepPosition: false);
  }
}
