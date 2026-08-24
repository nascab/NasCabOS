import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../../../utils/dialog_util.dart';
import '../../controller/video_detail_controller.dart';

/// 剧情简介区块。
class VideoDetailStorylineSection extends StatelessWidget {
  final VideoDetailController ctrl;

  const VideoDetailStorylineSection({super.key, required this.ctrl});

  void _showDetailDialog(BuildContext context) {
    final theme = Theme.of(context);
    final m = ctrl.item ?? const <String, dynamic>{};

    final title = (m['nfo_name']?.toString().trim().isNotEmpty ?? false)
        ? m['nfo_name'].toString()
        : (m['filename']?.toString() ?? '');
    final year = (m['nfo_year'] as num?)?.toInt() ?? 0;
    final score = (m['nfo_score'] as num?)?.toDouble() ?? 0;
    final regions = (m['nfo_regions']?.toString() ?? '').trim();
    final genres = (m['nfo_genres']?.toString() ?? '').trim();
    final storyline = (m['nfo_storyline']?.toString() ?? '').trim();
    final filename = (m['filename']?.toString() ?? '').trim();
    final fullPath = (m['full_path']?.toString() ?? '').trim();

    String joinPeople(List<Map<String, dynamic>> people) {
      final names = people
          .map((e) => (e['name']?.toString() ?? '').trim())
          .where((s) => s.isNotEmpty)
          .toList(growable: false);
      return names.join('、');
    }

    final directors = joinPeople(ctrl.directors);
    final actors = joinPeople(ctrl.actors);

    Widget row({required String label, required String value}) {
      final v = value.trim().isNotEmpty ? value.trim() : '-';
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: 72,
              child: Text(
                label,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Expanded(
              child: SelectableText(
                v,
                style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
              ),
            ),
          ],
        ),
      );
    }

    final metaParts = <String>[
      if (year > 0) year.toString(),
      if (score > 0) score.toStringAsFixed(1),
    ];
    final meta = metaParts.join(' · ');

    showDialog<void>(
      context: context,
      builder: (ctx) {
        return DialogUtil.createAlertDialog(
          title: Row(
            children: [
              Expanded(
                child: Text(
                  'detail'.tr,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              IconButton(
                onPressed: () => Navigator.of(ctx).pop(),
                icon: const Icon(Icons.close),
                splashRadius: 18,
              ),
            ],
          ),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 520),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (title.trim().isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        title,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  if (meta.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: Text(
                        meta,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.6,
                          ),
                        ),
                      ),
                    ),
                  if (filename.isNotEmpty)
                    row(label: 'name'.tr, value: filename),
                  if (fullPath.isNotEmpty)
                    row(label: 'path'.tr, value: fullPath),
                  row(label: 'video_detail_directors'.tr, value: directors),
                  row(label: 'video_detail_actors'.tr, value: actors),
                  row(label: 'video_detail_genres'.tr, value: genres),
                  row(label: 'video_detail_regions'.tr, value: regions),
                  const SizedBox(height: 4),
                  Text(
                    'video_detail_storyline'.tr,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SelectableText(
                    storyline.isNotEmpty
                        ? storyline
                        : 'video_detail_storyline_empty'.tr,
                    style: theme.textTheme.bodyMedium?.copyWith(height: 1.6),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final m = ctrl.item!;
    final storyline = (m['nfo_storyline']?.toString() ?? '').trim();
    final content = storyline.isNotEmpty
        ? storyline
        : 'video_detail_storyline_empty'.tr;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => _showDetailDialog(context),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: RichText(
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              text: TextSpan(
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.85),
                  height: 1.55,
                ),
                children: [
                  TextSpan(
                    text: "${'video_detail_storyline'.tr}:",
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.9),
                      height: 1.55,
                    ),
                  ),
                  TextSpan(text: content),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
