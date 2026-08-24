class WorkerProcessItem {
  final int pid;
  final String workerPath;
  final String role;
  final String nameKey;
  final String purposeKey;
  final int startedAt;

  const WorkerProcessItem({
    required this.pid,
    required this.workerPath,
    required this.role,
    required this.nameKey,
    required this.purposeKey,
    required this.startedAt,
  });

  factory WorkerProcessItem.fromJson(Map<String, dynamic> json) {
    final started = json['startedAt'];
    return WorkerProcessItem(
      pid: (json['pid'] as num?)?.toInt() ?? 0,
      workerPath: (json['workerPath'] ?? '').toString(),
      role: (json['role'] ?? '').toString(),
      nameKey: (json['nameKey'] ?? 'process.worker.unknown.name').toString(),
      purposeKey:
          (json['purposeKey'] ?? 'process.worker.unknown.purpose').toString(),
      startedAt: started is num ? started.toInt() : 0,
    );
  }
}
