part of '../file_share_server_view.dart';

class _ConfigDialog extends StatefulWidget {
  final FileShareServerController ctrl;
  final String serverType;
  final List<dynamic> existingUids;
  final Map<String, dynamic>? initialItem;

  const _ConfigDialog({
    required this.ctrl,
    required this.serverType,
    required this.existingUids,
    this.initialItem,
  });

  @override
  State<_ConfigDialog> createState() => _ConfigDialogState();
}
