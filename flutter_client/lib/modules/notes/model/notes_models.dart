class NotesNotebookInfo {
  final bool selected;
  final String folderPath;
  final String name;
  final int groupCount;
  final int noteCount;
  final int deletedCount;

  const NotesNotebookInfo({
    required this.selected,
    required this.folderPath,
    required this.name,
    required this.groupCount,
    required this.noteCount,
    required this.deletedCount,
  });

  factory NotesNotebookInfo.fromJson(Map<String, dynamic>? json) {
    final data = json ?? const <String, dynamic>{};
    return NotesNotebookInfo(
      selected: data['selected'] == true,
      folderPath: data['folderPath']?.toString() ?? '',
      name: data['name']?.toString() ?? '',
      groupCount: (data['groupCount'] as num?)?.toInt() ?? 0,
      noteCount: (data['noteCount'] as num?)?.toInt() ?? 0,
      deletedCount: (data['deletedCount'] as num?)?.toInt() ?? 0,
    );
  }

  NotesNotebookInfo copyWith({
    bool? selected,
    String? folderPath,
    String? name,
    int? groupCount,
    int? noteCount,
    int? deletedCount,
  }) {
    return NotesNotebookInfo(
      selected: selected ?? this.selected,
      folderPath: folderPath ?? this.folderPath,
      name: name ?? this.name,
      groupCount: groupCount ?? this.groupCount,
      noteCount: noteCount ?? this.noteCount,
      deletedCount: deletedCount ?? this.deletedCount,
    );
  }
}

class NotesGroup {
  final String id;
  final String name;
  final bool isSystem;
  final int noteCount;
  final int deletedCount;

  const NotesGroup({
    required this.id,
    required this.name,
    required this.isSystem,
    required this.noteCount,
    required this.deletedCount,
  });

  factory NotesGroup.fromJson(Map<String, dynamic> json) {
    return NotesGroup(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      isSystem: json['isSystem'] == true,
      noteCount: (json['noteCount'] as num?)?.toInt() ?? 0,
      deletedCount: (json['deletedCount'] as num?)?.toInt() ?? 0,
    );
  }
}

class NotesNote {
  final String id;
  final String title;
  final String preview;
  final String groupId;
  final String groupName;
  final String tagColor;
  final bool isPinned;
  final bool isDeleted;
  final String updateTime;
  final String createTime;
  final String deletedAt;
  final int assetCount;

  const NotesNote({
    required this.id,
    required this.title,
    required this.preview,
    required this.groupId,
    required this.groupName,
    required this.tagColor,
    required this.isPinned,
    required this.isDeleted,
    required this.updateTime,
    required this.createTime,
    required this.deletedAt,
    required this.assetCount,
  });

  factory NotesNote.fromJson(Map<String, dynamic> json) {
    return NotesNote(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      preview: json['preview']?.toString() ?? '',
      groupId: json['groupId']?.toString() ?? '',
      groupName: json['groupName']?.toString() ?? '',
      tagColor: json['tagColor']?.toString() ?? '',
      isPinned: json['isPinned'] == true,
      isDeleted: json['isDeleted'] == true,
      updateTime: json['updateTime']?.toString() ?? '',
      createTime: json['createTime']?.toString() ?? '',
      deletedAt: json['deletedAt']?.toString() ?? '',
      assetCount: (json['assetCount'] as num?)?.toInt() ?? 0,
    );
  }

  NotesNote copyWith({
    String? title,
    String? preview,
    String? groupId,
    String? groupName,
    String? tagColor,
    bool? isPinned,
    bool? isDeleted,
    String? updateTime,
    String? createTime,
    String? deletedAt,
    int? assetCount,
  }) {
    return NotesNote(
      id: id,
      title: title ?? this.title,
      preview: preview ?? this.preview,
      groupId: groupId ?? this.groupId,
      groupName: groupName ?? this.groupName,
      tagColor: tagColor ?? this.tagColor,
      isPinned: isPinned ?? this.isPinned,
      isDeleted: isDeleted ?? this.isDeleted,
      updateTime: updateTime ?? this.updateTime,
      createTime: createTime ?? this.createTime,
      deletedAt: deletedAt ?? this.deletedAt,
      assetCount: assetCount ?? this.assetCount,
    );
  }
}
