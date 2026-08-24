import '../../files/controllers/pc_file_explorer_controller.dart';
import '../folder_view_module_type.dart';

class PcFolderViewController extends PcFileExplorerController {
  PcFolderViewController({required this.moduleType})
    : super(
        initialSourceType: moduleType.sourceType,
        listApiPath: moduleType.listApiPath,
        searchApiPath: moduleType.searchApiPath,
        showRootCustomPathEntry: false,
      );

  final FolderViewModuleType moduleType;

  @override
  bool get allowExternalUploadDrop {
    final atRoot = (currentPath.value?.trim() ?? '').isEmpty;
    return !atRoot;
  }
}
