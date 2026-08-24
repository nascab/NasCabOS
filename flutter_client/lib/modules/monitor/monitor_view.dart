import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../core/bg_task/hw_metrics_controller.dart';
import '../base/components/custom_divider.dart';
import '../../../utils/file_util.dart';

/// 监控页面组件
/// Monitor View Component
class MonitorView extends StatefulWidget {
  const MonitorView({super.key});

  @override
  State<MonitorView> createState() => _MonitorViewState();
}

class _MonitorViewState extends State<MonitorView> {
  final HwMetricsController controller = HwMetricsController.instance;

  @override
  void initState() {
    super.initState();
    HwMetricsController.instance.start();
  }

  @override
  void dispose() {
    super.dispose();
    HwMetricsController.instance.stop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Obx(() {
        final metrics = controller.metrics;

        // 如果没有数据，显示加载中
        // Show loading if no data
        if (metrics == null) {
          return const Center(child: CircularProgressIndicator());
        }

        return SingleChildScrollView(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 第一部分：设备监控
              // Part 1: Device Monitor
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [_buildSectionTitle('monitor_device_monitor'.tr)],
              ),
              const SizedBox(height: 8),
              _buildDeviceMonitorCard(metrics),

              const SizedBox(height: 12),

              // 第二部分：存储设备
              // Part 2: Storage Devices
              _buildSectionTitle('monitor_storage_device'.tr),
              const SizedBox(height: 8),
              _buildStorageDevicesList(metrics),
            ],
          ),
        );
      }),
    );
  }

  /// 构建分节标题
  /// Build section title
  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
    );
  }

  /// 构建设备监控卡片
  /// Build device monitor card
  Widget _buildDeviceMonitorCard(Map<String, dynamic> metrics) {
    var theme = Theme.of(context);
    return Card(
      color: theme.cardColor,
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: LayoutBuilder(
          builder: (context, constraints) {
            // 响应式布局：如果宽度足够，使用横向排列，否则纵向
            // Responsive layout: Row if width is enough, otherwise Column
            final isWide = constraints.maxWidth > 600;

            final cpuWidget = _buildCpuInfo(
              metrics['cpu'],
              metrics['cpuInfo'],
              metrics['gpu'],
            );
            final memWidget = _buildMemoryInfo(metrics['memory']);
            final netWidget = _buildNetworkInfo(metrics['network']);

            if (isWide) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: cpuWidget),
                  _buildDivider(vertical: true),
                  Expanded(child: memWidget),
                  _buildDivider(vertical: true),
                  Expanded(child: netWidget),
                ],
              );
            } else {
              return Column(
                children: [
                  cpuWidget,
                  _buildDivider(vertical: false),
                  memWidget,
                  _buildDivider(vertical: false),
                  netWidget,
                ],
              );
            }
          },
        ),
      ),
    );
  }

  Widget _buildDivider({required bool vertical}) {
    return vertical
        ? const SizedBox(
            height: 60,
            child: VerticalDivider(width: 24, thickness: 1),
          )
        : const CustomDivider(height: 24, thickness: 1);
  }

  /// 构建CPU信息区域
  /// Build CPU info section
  Widget _buildCpuInfo(
    Map<String, dynamic>? cpu,
    Map<String, dynamic>? cpuInfo,
    Map<String, dynamic>? gpu,
  ) {
    if (cpu == null) return const SizedBox.shrink();

    final usage = cpu['usage'] ?? 0.0;
    final temp = cpu['temperature'];
    final showTemp = temp != null && temp > 0;
    final gpuInfo = gpu != null ? gpu['controllers'] : null;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.computer, size: 24, color: Colors.blue),
        const SizedBox(height: 4),
        if (gpuInfo != null && gpuInfo is List) ...[
          const SizedBox(height: 4),
          ...gpuInfo.asMap().entries.map((entry) {
            final index = entry.key + 1;
            final g = entry.value;
            final model = g['model'] ?? '';
            return Text(
              'GPU$index: $model',
              style: const TextStyle(fontSize: 10, color: Colors.grey),
            );
          }),
        ],
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('CPU:', style: const TextStyle(fontSize: 12)),

            if (cpuInfo != null) ...[
              const SizedBox(width: 8),
              Flexible(
                child: Tooltip(
                  message: _formatCpuInfo(cpuInfo),
                  child: Text(
                    _formatCpuInfo(cpuInfo),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ),
            ],
          ],
        ),

        const SizedBox(height: 4),
        Text(
          '${'monitor_used'.tr}: ${usage.toStringAsFixed(1)}%',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        if (showTemp) ...[
          const SizedBox(height: 2),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.thermostat, size: 12, color: Colors.orange),
              const SizedBox(width: 2),
              Text(
                '${temp.toStringAsFixed(1)}°C',
                style: const TextStyle(fontSize: 12),
              ),
            ],
          ),
        ],
      ],
    );
  }

  /// 构建内存信息区域
  /// Build Memory info section
  Widget _buildMemoryInfo(Map<String, dynamic>? memory) {
    if (memory == null) return const SizedBox.shrink();

    final usage = memory['usage'] ?? 0.0; // percentage
    final used = memory['usedFormatted'] ?? '';
    final total = memory['totalFormatted'] ?? '';

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Stack(
          alignment: Alignment.center,
          children: [
            SizedBox(
              width: 50,
              height: 50,
              child: CircularProgressIndicator(
                value: usage / 100,
                backgroundColor: Colors.grey.withValues(alpha: 0.2),
                color: Colors.purple,
                strokeWidth: 5,
              ),
            ),
            Text(
              '${usage.toStringAsFixed(1)}%',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'monitor_memory'.tr,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 2),
        Text(
          '${'monitor_used'.tr}: $used / ${'monitor_total'.tr}: $total',
          style: const TextStyle(fontSize: 12),
        ),
      ],
    );
  }

  /// 构建网络信息区域
  /// Build Network info section
  Widget _buildNetworkInfo(Map<String, dynamic>? network) {
    if (network == null) return const SizedBox.shrink();

    final upload = network['uploadSpeed'] ?? '0 B/s';
    final download = network['downloadSpeed'] ?? '0 B/s';

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.network_check, size: 24, color: Colors.green),
        const SizedBox(height: 4),
        Text(
          'monitor_network'.tr,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.arrow_upward, size: 14, color: Colors.orange),
            const SizedBox(width: 2),
            Text(
              '${'upload'.tr}: $upload',
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.arrow_downward, size: 14, color: Colors.blue),
            const SizedBox(width: 2),
            Text(
              '${'download'.tr}: $download',
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
      ],
    );
  }

  /// 构建存储设备列表
  /// Build storage devices list
  Widget _buildStorageDevicesList(Map<String, dynamic> metrics) {
    final disks = metrics['disks']?['usage'] as List?;
    if (disks == null || disks.isEmpty) {
      return Center(child: Text('no_data'.tr));
    }

    return Column(
      children: disks.map<Widget>((disk) {
        return _buildDiskCard(disk);
      }).toList(),
    );
  }

  /// 构建单个磁盘卡片
  /// Build single disk card
  Widget _buildDiskCard(Map<String, dynamic> disk) {
    final mount = disk['mount'] ?? '';
    final fs = disk['fs'] ?? ''; // e.g. /dev/disk3s1s1
    final type = disk['type'] ?? 'Unknown';
    final sizeFormatted = disk['sizeFormatted'] ?? '';
    final availableFormatted = disk['availableFormatted'] ?? '';

    double? usagePercent;
    double? totalBytes;

    if (disk['size'] != null) {
      totalBytes = (disk['size'] as num).toDouble();
    } else {
      totalBytes = FileUtil.parseSizeToBytes(sizeFormatted);
    }

    double? availableBytes = (disk['available'] as num?)?.toDouble();

    if (totalBytes != null && availableBytes != null && totalBytes > 0) {
      usagePercent = 1.0 - (availableBytes / totalBytes);
      if (usagePercent < 0) usagePercent = 0;
      if (usagePercent > 1) usagePercent = 1;
    }
    var theme = Theme.of(context);
    return Card(
      color: theme.cardColor,
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Row(
          children: [
            // 图标
            // Icon
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.blue.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.storage, color: Colors.blue, size: 20),
            ),
            const SizedBox(width: 12),

            // 详情
            // Details
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    mount,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${'type'.tr}: $type',
                    style: const TextStyle(fontSize: 12),
                  ),
                  Text(
                    '${'path'.tr}: $fs',
                    style: const TextStyle(fontSize: 12),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),

            const SizedBox(width: 12),

            // 使用率环形图
            // Usage Ring Chart
            if (usagePercent != null)
              Column(
                children: [
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox(
                        width: 40,
                        height: 40,
                        child: CircularProgressIndicator(
                          value: usagePercent,
                          backgroundColor: Colors.grey.withValues(alpha: 0.2),
                          color: _getUsageColor(usagePercent),
                          strokeWidth: 4,
                        ),
                      ),
                      Text(
                        '${(usagePercent * 100).toStringAsFixed(0)}%',
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        availableFormatted,
                        style: const TextStyle(fontSize: 10),
                      ),
                      if (sizeFormatted.isNotEmpty)
                        Text(
                          ' / $sizeFormatted',
                          style: const TextStyle(fontSize: 10),
                        ),
                    ],
                  ),
                ],
              )
            else
              Text(availableFormatted),
          ],
        ),
      ),
    );
  }

  Color _getUsageColor(double percent) {
    if (percent > 0.9) return Colors.red;
    if (percent > 0.7) return Colors.orange;
    return Colors.blue;
  }

  /// 格式化CPU信息
  /// Format CPU info
  String _formatCpuInfo(Map<String, dynamic> info) {
    final manufacturer = info['manufacturer'] ?? '';
    final brand = info['brand'] ?? '';
    final cores = info['cores'] ?? 0;
    final pCores = info['performanceCores'];
    final eCores = info['efficiencyCores'];

    final buffer = StringBuffer();
    if (manufacturer.isNotEmpty) buffer.write('$manufacturer ');
    if (brand.isNotEmpty) buffer.write('$brand ');
    if (cores > 0) {
      buffer.write('$cores');
      if (pCores != null && eCores != null) {
        buffer.write('($pCores+$eCores)');
      }
      buffer.write(' Cores');
    }

    return buffer.toString();
  }
}
