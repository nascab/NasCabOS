import 'package:get/get.dart';

abstract class MusicMultiSelectController {
  RxSet<int> get selectedItems;
  bool get isAllCurrentSelected;
  bool get isSelectedAllFavorited;
  bool get isInPlayList;
  void toggleSelectAllCurrent();
  Future<void> toggleFavoriteSelected();
  Future<void> downloadSelected();
  Future<void> deleteSelected();
  Future<void> addToPlayListSelected();
  Future<void> removeFromPlayListSelected();
  void exitMultiSelectMode();
}
