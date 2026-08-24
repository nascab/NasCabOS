import '../../files/controllers/app_file_controller.dart';
import '../folder_view_module_type.dart';

class AppFolderViewController extends AppFileController {
  AppFolderViewController({
    required this.moduleType,
    bool autoLoadRoot = true,
  }) : super(
        initialSourceType: moduleType.sourceType,
        listApiPath: moduleType.listApiPath,
        searchApiPath: moduleType.searchApiPath,
        showRootCustomPathEntry: false,
        autoLoadRoot: autoLoadRoot,
      );

  final FolderViewModuleType moduleType;
}
