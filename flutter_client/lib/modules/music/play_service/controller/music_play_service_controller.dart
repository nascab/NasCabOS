import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:video_player/video_player.dart';
import '../../../../core/api/api_controller.dart';
import '../../../../core/api/base_api_service.dart';
import '../../../../utils/cache_manager.dart';
import '../../../../utils/dialog_util.dart';
import '../../list/models/music_list_models.dart';
import '../../list/service/music_list_api_service.dart';
import '../../../video_player/controllers/platform/video_platform.dart';
import '../cache/music_audio_cache.dart';
import '../player/music_player_adapter.dart';
import '../player/music_player_just_audio.dart';
import '../player/music_player_video.dart';

part 'parts/audio_handler.dart';
part 'parts/lifecycle.dart';
part 'parts/lyrics.dart';
part 'parts/playback.dart';
part 'parts/recovery.dart';

typedef MusicProgressListener =
    void Function(Duration position, Duration duration, Duration buffered);

enum MusicLoopMode { sequence, listLoop, singleLoop, shuffle }

class MusicPlaylistPaging {
  final bool Function() hasMore;
  final Future<List<MusicListItem>> Function() loadMore;

  const MusicPlaylistPaging({required this.hasMore, required this.loadMore});

  factory MusicPlaylistPaging.fromQuery(MusicListPagingQuery query) {
    var page = query.page;
    var pageSize = query.pageSize;
    var more = query.hasMore;
    return MusicPlaylistPaging(
      hasMore: () => more,
      loadMore: () async {
        if (!more) return const <MusicListItem>[];
        final res = await MusicListApiService.instance.listPaged(
          page: page + 1,
          pageSize: pageSize,
          listType: query.listType,
          listId: query.listId,
          seriesIndexId: query.seriesIndexId,
          collectionId: query.collectionId,
          isFavorite: query.isFavorite,
          isHistory: query.isHistory,
          search: query.search,
          artists: query.artists,
          albums: query.albums,
          genres: query.genres,
          sourceList: query.sourceList,
          sortBy: query.sortBy,
          sortOrder: query.sortOrder,
          showLoading: false,
        );
        page = res.pagination.page;
        pageSize = res.pagination.limit;
        more = res.pagination.hasNextPage;
        if (res.items.isEmpty) return const <MusicListItem>[];
        return res.items;
      },
    );
  }
}

class MusicPlayServiceController extends GetxController
    with WidgetsBindingObserver {
  static MusicPlayServiceController get instance {
    if (Get.isRegistered<MusicPlayServiceController>()) {
      return Get.find<MusicPlayServiceController>();
    }
    return Get.put(MusicPlayServiceController(), permanent: true);
  }

  static const discAssets = <String>[
    'assets/music/icons/player_disc1.png',
    'assets/music/icons/player_disc2.png',
    'assets/music/icons/player_disc3.png',
  ];

  final RxList<MusicListItem> playlist = <MusicListItem>[].obs;
  final RxInt currentIndex = 0.obs;
  final RxBool isPlaying = false.obs;
  final Rx<Duration> position = Duration.zero.obs;
  final Rx<Duration> duration = Duration.zero.obs;
  final Rx<Duration> buffered = Duration.zero.obs;
  final RxDouble volume = 1.0.obs;
  final Rx<MusicLoopMode> loopMode = MusicLoopMode.sequence.obs;
  final RxBool isReady = false.obs;
  final RxInt discStyleIndex = 0.obs;
  double _volumeBeforeMute = 1.0;
  final RxString currentLyrics = ''.obs;

  final RxBool audioCacheEnabled = true.obs;
  final RxInt audioCacheMaxItems = 300.obs;
  final RxBool isDownloading = false.obs;
  final RxDouble downloadProgress = 0.0.obs;
  final RxInt downloadReceivedBytes = 0.obs;
  final RxInt downloadTotalBytes = 0.obs;
  final RxString downloadingFileHash = ''.obs;

  MusicPlayerAdapter? _player;
  _MusicAudioHandler? _handler;
  Future<void>? _serviceInitFuture;
  final List<MusicProgressListener> _progressListeners = [];
  Timer? _positionPollTimer;
  VoidCallback? _playerListener;
  bool _isCompleted = false;
  Timer? _stallTimer;
  bool _desiredPlaying = false;
  bool _pendingNotificationPermissionGuide = false;
  DateTime? _lastRecoveryAt;
  String? _lastPlaylistAccessToken;
  int _rebuildToken = 0;

  /// 上次通过 mediaItem.add() 推送的 MediaItem 缓存键（index:title:durationSec）
  /// 防止 mediaItem.add() 被高频调用时干扰 playbackState 的通知更新（见 audio_service #1055）
  String? _lastSentMediaItemKey;

  /// audio_session 事件订阅（中断/耳机拔出），在 onClose 时取消
  final List<StreamSubscription<dynamic>> _audioSessionSubs = [];

  /// 正在执行上一首/下一首切歌，避免与「播放完成」逻辑竞态导致锁屏切歌后播放结束
  bool _isSkippingTrack = false;
  bool _isOpeningTrack = false;
  DateTime? _suppressCompletedUntil;

  final Map<String, MusicListItem> _detailCache = {};
  final Map<String, String> _lyricsCache = {};
  final Set<String> _autoLyricTried = <String>{};
  int _detailFetchToken = 0;
  MusicPlaylistPaging? _paging;
  bool _pagingLoading = false;
  int _pagingToken = 0;
  final Random _shuffleRandom = Random();
  final List<int> _shuffleHistory = <int>[];

  final MusicAudioCacheService _audioCache = MusicAudioCacheService(
    options: const MusicAudioCacheOptions(enabled: true, maxItems: 300),
  );

  static const MethodChannel _iosAudioSessionChannel = MethodChannel(
    'nascab.music.audio_session',
  );

  /// iOS/Android 使用 just_audio 以支持后台与锁屏播放
  bool get _useJustAudio =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.android);

  @override
  void onInit() {
    super.onInit();
    WidgetsBinding.instance.addObserver(this);
    _loadDiscStyleIndex();
    _loadLoopMode();
    unawaited(_initAudioCache());
  }

  @override
  void onClose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopPositionPolling();
    _stallTimer?.cancel();
    for (final sub in _audioSessionSubs) {
      sub.cancel();
    }
    _audioSessionSubs.clear();
    unawaited(_audioCache.cancelActiveDownload());
    unawaited(_disposePlayer());
    super.onClose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (kIsWeb) return;
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      switch (state) {
        case AppLifecycleState.paused:
        case AppLifecycleState.inactive:
          if (isPlaying.value || _desiredPlaying) {
            unawaited(_activateIosAudioSessionForPlayback());
          }
          break;
        case AppLifecycleState.resumed:
          if ((_player != null && _desiredPlaying) || isPlaying.value) {
            unawaited(_activateIosAudioSessionForPlayback());
          }
          break;
        default:
          break;
      }
      return;
    }
    if (defaultTargetPlatform == TargetPlatform.android) {
      if (state == AppLifecycleState.resumed &&
          _pendingNotificationPermissionGuide) {
        _pendingNotificationPermissionGuide = false;
        unawaited(_ensureNotificationPermission());
      }
    }
  }

  Future<void> setAudioCacheEnabled(bool enabled) async {
    audioCacheEnabled.value = enabled;
    await CacheManager().setBool(CacheKeys.musicAudioCacheEnabled, enabled);
    _audioCache.updateOptions(
      _audioCache.options.copyWith(
        enabled: enabled,
        maxItems: audioCacheMaxItems.value,
      ),
    );
  }

  Future<void> setAudioCacheMaxItems(int maxItems) async {
    final safe = maxItems < 0 ? 0 : maxItems;
    audioCacheMaxItems.value = safe;
    await CacheManager().setInt(CacheKeys.musicAudioCacheMaxItems, safe);
    _audioCache.updateOptions(
      _audioCache.options.copyWith(
        enabled: audioCacheEnabled.value,
        maxItems: safe,
      ),
    );
  }

  Future<void> clearAudioCache() async {
    await _audioCache.clearAll();
  }

  Future<MusicAudioCacheStats> getAudioCacheStats() async {
    return _audioCache.getStats();
  }

  Future<void> cancelDownload() async {
    await _audioCache.cancelActiveDownload();
    _setDownloadUi(downloading: false, fileHash: '', received: 0, total: 0);
  }

  Future<void> _initAudioCache() async {
    final enabled =
        CacheManager().getBool(CacheKeys.musicAudioCacheEnabled) ?? true;
    final maxItems =
        CacheManager().getInt(CacheKeys.musicAudioCacheMaxItems) ?? 300;
    audioCacheEnabled.value = enabled;
    audioCacheMaxItems.value = maxItems;
    _audioCache.updateOptions(
      MusicAudioCacheOptions(enabled: enabled, maxItems: maxItems),
    );
    await _audioCache.init();
  }

  Future<void> _activateIosAudioSessionForPlayback() async {
    if (kIsWeb) return;
    if (defaultTargetPlatform != TargetPlatform.iOS) return;
    try {
      await _iosAudioSessionChannel.invokeMethod('activatePlayback');
    } catch (_) {}
  }

  Future<void> _deactivateIosAudioSessionForPlayback() async {
    if (kIsWeb) return;
    if (defaultTargetPlatform != TargetPlatform.iOS) return;
    try {
      await _iosAudioSessionChannel.invokeMethod('deactivatePlayback');
    } catch (_) {}
  }

  void _setDownloadUi({
    required bool downloading,
    required String fileHash,
    required int received,
    required int total,
  }) {
    isDownloading.value = downloading;
    downloadingFileHash.value = fileHash;
    downloadReceivedBytes.value = received;
    downloadTotalBytes.value = total;
    downloadProgress.value = total <= 0 ? 0.0 : (received / total).clamp(0, 1);
  }
}
