part of '../video_player_controller.dart';

extension PlayerAutosave on PlayerController {
  void startAutoSave() {
    _autoSaveTimer?.cancel();
    _autoSaveTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (isPlaying.value && isInitialized.value) {
        saveProgress();
      }
    });
  }

  void stopAutoSave() {
    _autoSaveTimer?.cancel();
  }
}
