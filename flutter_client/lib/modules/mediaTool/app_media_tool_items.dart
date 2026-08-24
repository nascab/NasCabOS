import 'package:flutter/material.dart';

class AppMediaToolItem {
  final String key;
  final String groupTitleKey;
  final String titleKey;
  final String subtitleKey;
  final IconData icon;

  const AppMediaToolItem({
    required this.key,
    required this.groupTitleKey,
    required this.titleKey,
    required this.subtitleKey,
    required this.icon,
  });
}

const appMediaToolItems = <AppMediaToolItem>[
  AppMediaToolItem(
    key: 'image.compress',
    groupTitleKey: 'media_tool_menu_image',
    titleKey: 'media_tool_menu_image_compress',
    subtitleKey: 'media_tool_menu_image_compress_help',
    icon: Icons.compress_outlined,
  ),
  AppMediaToolItem(
    key: 'image.batch_compress',
    groupTitleKey: 'media_tool_menu_image',
    titleKey: 'media_tool_menu_image_batch_compress',
    subtitleKey: 'media_tool_menu_image_batch_compress_help',
    icon: Icons.batch_prediction_outlined,
  ),
  AppMediaToolItem(
    key: 'video.trans',
    groupTitleKey: 'media_tool_menu_video',
    titleKey: 'media_tool_menu_video_trans',
    subtitleKey: 'media_tool_menu_video_trans_help',
    icon: Icons.transform_outlined,
  ),
  AppMediaToolItem(
    key: 'audio.trans',
    groupTitleKey: 'media_tool_menu_audio',
    titleKey: 'media_tool_menu_audio_trans',
    subtitleKey: 'media_tool_menu_audio_trans_help',
    icon: Icons.graphic_eq_outlined,
  ),
  AppMediaToolItem(
    key: 'other.media_arrange',
    groupTitleKey: 'media_tool_menu_other',
    titleKey: 'media_tool_menu_media_arrange',
    subtitleKey: 'media_tool_arrange_help',
    icon: Icons.folder_copy_outlined,
  ),
];
