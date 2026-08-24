import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../../../../../utils/dialog_util.dart';

class VideoOpenSkipFormResult {
  final int startSeconds;
  final int endSeconds;

  const VideoOpenSkipFormResult({
    required this.startSeconds,
    required this.endSeconds,
  });
}

Future<VideoOpenSkipFormResult?> showVideoOpenSkipDialog(
  BuildContext context, {
  required int initialStartSeconds,
  required int initialEndSeconds,
}) {
  Map<String, TextEditingController> buildControllers(int totalSeconds) {
    final safe = totalSeconds < 0 ? 0 : totalSeconds;
    return {
      'minutes': TextEditingController(text: (safe ~/ 60).toString()),
      'seconds': TextEditingController(
        text: (safe % 60).toString().padLeft(2, '0'),
      ),
    };
  }

  int resolveSeconds(Map<String, TextEditingController> controllers) {
    final minutes =
        int.tryParse(controllers['minutes']?.text.trim() ?? '') ?? 0;
    final seconds =
        int.tryParse(controllers['seconds']?.text.trim() ?? '') ?? 0;
    final safeMinutes = minutes < 0 ? 0 : minutes;
    final safeSeconds = seconds.clamp(0, 59);
    return safeMinutes * 60 + safeSeconds;
  }

  void resetControllers(
    Map<String, TextEditingController> controllers,
    int totalSeconds,
  ) {
    final safe = totalSeconds < 0 ? 0 : totalSeconds;
    controllers['minutes']?.text = (safe ~/ 60).toString();
    controllers['seconds']?.text = (safe % 60).toString().padLeft(2, '0');
  }

  Widget buildTimeEditor(
    BuildContext context,
    String title,
    Map<String, TextEditingController> controllers,
  ) {
    final theme = Theme.of(context);
    InputDecoration decoration(String label) {
      return InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        isDense: true,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: controllers['minutes'],
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: decoration('smart_album_unit_min'.tr),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: controllers['seconds'],
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: decoration('comic_reader_seconds'.tr),
              ),
            ),
          ],
        ),
      ],
    );
  }

  final openingControllers = buildControllers(initialStartSeconds);
  final endingControllers = buildControllers(initialEndSeconds);

  return showDialog<VideoOpenSkipFormResult>(
    context: context,
    builder: (dialogContext) {
      return DialogUtil.createAlertDialog(
        title: Text('video_detail_open_skip'.tr),
        content: StatefulBuilder(
          builder: (context, setState) {
            return SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'video_detail_open_skip_tip'.tr,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 16),
                  buildTimeEditor(
                    context,
                    'video_detail_open_skip_opening'.tr,
                    openingControllers,
                  ),
                  const SizedBox(height: 16),
                  buildTimeEditor(
                    context,
                    'video_detail_open_skip_ending'.tr,
                    endingControllers,
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () {
                        setState(() {
                          resetControllers(openingControllers, 0);
                          resetControllers(endingControllers, 0);
                        });
                      },
                      icon: const Icon(Icons.restart_alt),
                      label: Text('video_detail_open_skip_clear'.tr),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text('cancel'.tr),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop(
                VideoOpenSkipFormResult(
                  startSeconds: resolveSeconds(openingControllers),
                  endSeconds: resolveSeconds(endingControllers),
                ),
              );
            },
            child: Text('save'.tr),
          ),
        ],
      );
    },
  ).whenComplete(() {
    for (final controller in openingControllers.values) {
      controller.dispose();
    }
    for (final controller in endingControllers.values) {
      controller.dispose();
    }
  });
}
