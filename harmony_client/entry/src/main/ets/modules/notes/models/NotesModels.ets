/**
 * 笔记模块模型（对齐 Flutter modules/notes/model/notes_models.dart）。
 */

export function bStr(v: Object | undefined | null): string {
  if (v === undefined || v === null) {
    return '';
  }
  return `${v}`;
}

export function bNum(v: Object | undefined | null): number {
  if (v === undefined || v === null) {
    return 0;
  }
  if (typeof v === 'number') {
    return Math.trunc(v);
  }
  const n = Number(`${v}`);
  return Number.isFinite(n) ? Math.trunc(n) : 0;
}

export function bBool(v: Object | undefined | null): boolean {
  return v === true;
}

export class NotesNotebookInfo {
  selected: boolean = false;
  folderPath: string = '';
  name: string = '';
  groupCount: number = 0;
  noteCount: number = 0;
  deletedCount: number = 0;

  static fromJson(data: Record<string, Object> | undefined | null): NotesNotebookInfo {
    const info = new NotesNotebookInfo();
    const d = data ?? {};
    info.selected = bBool(d['selected']);
    info.folderPath = bStr(d['folderPath']);
    info.name = bStr(d['name']);
    info.groupCount = bNum(d['groupCount']);
    info.noteCount = bNum(d['noteCount']);
    info.deletedCount = bNum(d['deletedCount']);
    return info;
  }
}

export class NotesGroup {
  id: string = '';
  name: string = '';
  isSystem: boolean = false;
  noteCount: number = 0;
  deletedCount: number = 0;

  static fromJson(data: Record<string, Object> | undefined | null): NotesGroup {
    const g = new NotesGroup();
    const d = data ?? {};
    g.id = bStr(d['id']);
    g.name = bStr(d['name']);
    g.isSystem = bBool(d['isSystem']);
    g.noteCount = bNum(d['noteCount']);
    g.deletedCount = bNum(d['deletedCount']);
    return g;
  }
}

export class NotesNote {
  id: string = '';
  title: string = '';
  preview: string = '';
  groupId: string = '';
  groupName: string = '';
  tagColor: string = '';
  isPinned: boolean = false;
  isDeleted: boolean = false;
  updateTime: string = '';
  createTime: string = '';
  deletedAt: string = '';
  assetCount: number = 0;

  static fromJson(data: Record<string, Object> | undefined | null): NotesNote {
    const n = new NotesNote();
    const d = data ?? {};
    n.id = bStr(d['id']);
    n.title = bStr(d['title']);
    n.preview = bStr(d['preview']);
    n.groupId = bStr(d['groupId']);
    n.groupName = bStr(d['groupName']);
    n.tagColor = bStr(d['tagColor']);
    n.isPinned = bBool(d['isPinned']);
    n.isDeleted = bBool(d['isDeleted']);
    n.updateTime = bStr(d['updateTime']);
    n.createTime = bStr(d['createTime']);
    n.deletedAt = bStr(d['deletedAt']);
    n.assetCount = bNum(d['assetCount']);
    return n;
  }
}

/** 预设标签色（对齐 Flutter NotesController.presetColors） */
export const NOTES_PRESET_COLORS: string[] = [
  '',
  '#EF4444',
  '#F59E0B',
  '#10B981',
  '#3B82F6',
  '#8B5CF6',
  '#EC4899',
];

/** 标签过滤"全部"值（对齐 Flutter allTagFilterValue） */
export const NOTES_ALL_TAG_FILTER: string = '__all__';

/** 布局常量（对齐 Flutter NotesLayout，供未来宽屏复用） */
export class NotesLayoutSpec {
  static readonly sidebarExpandedWidth: number = 188;
  static readonly sidebarCollapsedWidth: number = 68;
  static readonly noteListWidth: number = 268;
  static readonly minDesktopWidth: number = 1080;
  static readonly minDesktopHeight: number = 640;
}
