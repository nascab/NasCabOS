import '../../ai_faces/models/ai_faces_models.dart';
import '../../ai_scenes/models/ai_scenes_models.dart';

class AppPhotoAiOverviewResult {
  final AiFaceListResult faces;
  final AiSceneListResult scenes;
  final bool similarEnable;

  AppPhotoAiOverviewResult({
    required this.faces,
    required this.scenes,
    required this.similarEnable,
  });

  factory AppPhotoAiOverviewResult.fromJson(Map<String, dynamic> json) {
    bool parseEnable(dynamic v) {
      if (v is bool) return v;
      if (v is num) return v.toInt() == 1;
      if (v is String) return v == '1' || v.toLowerCase() == 'true';
      return true;
    }

    final facesRaw = (json['faces'] as Map?)?.cast<String, dynamic>() ?? {};
    final scenesRaw = (json['scenes'] as Map?)?.cast<String, dynamic>() ?? {};

    return AppPhotoAiOverviewResult(
      faces: AiFaceListResult.fromJson(facesRaw),
      scenes: AiSceneListResult.fromJson(scenesRaw),
      similarEnable: parseEnable(
        json['similarEnable'] ?? json['similar_enable'] ?? json['similar'],
      ),
    );
  }
}
