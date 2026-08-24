import 'dart:async';

class VideoItemSyncService {
  static final StreamController<int> _deletedController =
      StreamController<int>.broadcast();

  static Stream<int> get deletedStream => _deletedController.stream;

  static void notifyDeleted(int indexId) {
    if (indexId <= 0 || _deletedController.isClosed) return;
    _deletedController.add(indexId);
  }
}
