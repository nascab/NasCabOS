import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

import '../../../../../core/api/api_controller.dart';
import '../../../../../utils/dialog_util.dart';
import '../../../../../utils/file_util.dart';
import '../../../../../utils/http_util.dart';

class MusicPlayCtrlFullScreenFilePropertiesDialog {
  static Future<void> show({
    required BuildContext context,
    required String filePath,
  }) async {
    if (filePath.trim().isEmpty) return;
    try {
      final data = await _getFileProperties(filePath);
      if (data != null) {
        if (!context.mounted) return;
        showDialog(
          context: context,
          builder: (ctx) {
            return DialogUtil.createAlertDialog(
              title: Text('property'.tr),
              content: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildPropertyRow(
                      'location'.tr,
                      data['path']?.toString() ?? '',
                    ),
                    _buildPropertyRow(
                      'file_name'.tr,
                      data['name']?.toString() ?? '',
                    ),
                    _buildPropertyRow(
                      'total_size'.tr,
                      FileUtil.formatSize((data['size'] as num?)?.toInt() ?? 0),
                    ),
                    _buildPropertyRow(
                      'create_time'.tr,
                      data['birthtime'] != null
                          ? _formatDateTime((data['birthtime'] as num).toInt())
                          : '',
                    ),
                    _buildPropertyRow(
                      'modified_at'.tr,
                      data['mtime'] != null
                          ? _formatDateTime((data['mtime'] as num).toInt())
                          : '',
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: Text('confirm'.tr),
                ),
              ],
            );
          },
        );
        return;
      }
    } catch (_) {}

    DialogUtil.showInfoDialog(
      title: 'error'.tr,
      content: 'get_file_property_failed'.tr,
    );
  }

  static Future<Map<String, dynamic>?> _getFileProperties(
    String filePath,
  ) async {
    try {
      final baseUrl = ApiController.instance.baseUrl;
      final token = ApiController.instance.accessToken;
      final res = await HttpUtil.get(
        '$baseUrl/api/file/attributes?path=${Uri.encodeComponent(filePath)}',
        headers: token != null ? {'Authorization': 'Bearer $token'} : null,
      );
      if (res.isOk && res.json != null) {
        return res.json!['data'] as Map<String, dynamic>;
      }
    } catch (_) {}
    return null;
  }

  static String _formatDateTime(int timestampMs) {
    final format = DateFormat('yyyy-MM-dd HH:mm:ss');
    return format.format(DateTime.fromMillisecondsSinceEpoch(timestampMs));
  }

  static Widget _buildPropertyRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}
