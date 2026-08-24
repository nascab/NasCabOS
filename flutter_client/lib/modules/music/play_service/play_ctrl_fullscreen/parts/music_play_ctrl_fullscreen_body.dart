import 'package:NasCabOS/utils/device_utils.dart';
import 'package:flutter/material.dart';

import '../../app_components/music_play_disc_cover.dart';
import '../../../../../utils/cache_manager.dart';
import 'music_play_ctrl_fullscreen_disc_block.dart';
import 'music_play_ctrl_fullscreen_lyric_block.dart';

class MusicPlayCtrlFullScreenBody extends StatefulWidget {
  final bool isPlaying;
  final String coverUrl;
  final String discAsset;
  final String musicPath;
  final Duration trackDuration;
  final VoidCallback? onToggleFavorite;
  final bool favoriteLoading;
  final bool isFavorite;
  final VoidCallback onNextDiscStyle;
  final VoidCallback onShowProperties;
  final VoidCallback onShowPlaylist;
  final String title;
  final String album;
  final String artist;
  final String lyrics;
  final Duration position;
  final Future<void> Function(Duration position) onSeekTo;

  const MusicPlayCtrlFullScreenBody({
    super.key,
    required this.isPlaying,
    required this.coverUrl,
    required this.discAsset,
    required this.musicPath,
    required this.trackDuration,
    required this.onToggleFavorite,
    required this.favoriteLoading,
    required this.isFavorite,
    required this.onNextDiscStyle,
    required this.onShowProperties,
    required this.onShowPlaylist,
    required this.title,
    required this.album,
    required this.artist,
    required this.lyrics,
    required this.position,
    required this.onSeekTo,
  });

  @override
  State<MusicPlayCtrlFullScreenBody> createState() =>
      _MusicPlayCtrlFullScreenBodyState();
}

class _MusicPlayCtrlFullScreenBodyState
    extends State<MusicPlayCtrlFullScreenBody> {
  bool _showLyrics = false;

  @override
  void initState() {
    super.initState();
    _showLyrics =
        CacheManager().getBool(CacheKeys.musicFullScreenShowLyrics) ?? false;
  }

  void _setShowLyrics(bool value) {
    if (_showLyrics == value) return;
    setState(() => _showLyrics = value);
    CacheManager().setBool(CacheKeys.musicFullScreenShowLyrics, value);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (ctx, c) {
        final isNarrow = DeviceUtils.isMobile;
        final discBlock = MusicPlayCtrlFullScreenDiscBlock(
          isPlaying: widget.isPlaying,
          coverUrl: widget.coverUrl,
          discAsset: widget.discAsset,
          onToggleFavorite: widget.onToggleFavorite,
          favoriteLoading: widget.favoriteLoading,
          isFavorite: widget.isFavorite,
          onNextDiscStyle: widget.onNextDiscStyle,
          onShowProperties: widget.onShowProperties,
          onShowPlaylist: widget.onShowPlaylist,
          onTapDisc: isNarrow ? () => _setShowLyrics(true) : null,
        );
        final lyricBlock = MusicPlayCtrlFullScreenLyricBlock(
          musicPath: widget.musicPath,
          title: widget.title,
          album: widget.album,
          artist: widget.artist,
          lyrics: widget.lyrics,
          trackDuration: widget.trackDuration,
          position: widget.position,
          onSeekTo: widget.onSeekTo,
          centerMode: isNarrow,
        );
        if (isNarrow) {
          final current = _showLyrics
              ? Stack(
                  children: [
                    Positioned.fill(child: Center(child: lyricBlock)),
                    Positioned(
                      right: 12,
                      bottom: 12,
                      child: MusicPlayDiscCover(
                        coverUrl: widget.coverUrl,
                        isPlaying: widget.isPlaying,
                        discAsset: widget.discAsset,
                        outerSize: 50,
                        innerSize: 34,
                        onTap: () => _setShowLyrics(false),
                      ),
                    ),
                  ],
                )
              : discBlock;
          return Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              switchInCurve: Curves.easeOut,
              switchOutCurve: Curves.easeIn,
              layoutBuilder: (currentChild, previousChildren) {
                return Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.center,
                  children: [
                    ...previousChildren,
                    if (currentChild != null) currentChild,
                  ],
                );
              },
              child: KeyedSubtree(
                key: ValueKey<bool>(_showLyrics),
                child: Center(child: current),
              ),
            ),
          );
        }
        return Padding(
          padding: const EdgeInsets.fromLTRB(22, 0, 22, 8),
          child: Row(
            children: [
              Expanded(flex: 5, child: discBlock),
              const SizedBox(width: 28),
              Expanded(flex: 6, child: lyricBlock),
            ],
          ),
        );
      },
    );
  }
}
