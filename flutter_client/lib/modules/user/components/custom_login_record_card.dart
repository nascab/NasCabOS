import 'package:flutter/material.dart';

class CustomLoginRecordCard extends StatelessWidget {
  final Map<String, dynamic> record;
  const CustomLoginRecordCard({super.key, required this.record});

  IconData _iconForRecord() {
    final os = (record['os']?.toString() ?? '').toLowerCase();
    final device = (record['device_info']?.toString() ?? '').toLowerCase();
    if (os.contains('android') ||
        os.contains('ios') ||
        device.contains('mobile')) {
      return Icons.smartphone;
    }
    return Icons.computer;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    String formatLocalTime(dynamic v) {
      DateTime? dt;
      if (v is DateTime) {
        dt = v;
      } else if (v is int) {
        final isMs = v > 10000000000; // > ~2001-09-09 in seconds
        dt = DateTime.fromMillisecondsSinceEpoch(isMs ? v : v * 1000);
      } else if (v is String) {
        final n = int.tryParse(v);
        if (n != null) {
          final isMs = n > 10000000000;
          dt = DateTime.fromMillisecondsSinceEpoch(isMs ? n : n * 1000);
        } else {
          try {
            dt = DateTime.parse(v);
          } catch (_) {}
        }
      }
      if (dt == null) return (v?.toString() ?? '');
      final local = dt.toLocal();
      String two(int x) => x.toString().padLeft(2, '0');
      return '${local.year}-${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
    }

    return Card(
      color: theme.cardColor,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: theme.colorScheme.onSurface.withValues(
                alpha: 0.1,
              ),
              child: Icon(
                _iconForRecord(),
                color: theme.colorScheme.primary.withValues(alpha: 0.8),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${record['browser']?.toString()} - ${record['device_info']?.toString()}',
                    // (record['browser']?.toString() ??
                    //     record['device_info']?.toString() ??
                    //     ''),
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    formatLocalTime(record['create_time']),
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
