import { L10n } from '../../core/localization/L10n';
import { PhotoSmartAlbumItem } from '../models/PhotoAlbumModels';

/**
 * 智能相册筛选条件描述文本（对齐 Flutter PhotoSmartAlbumController.buildAlbumTooltipText）
 */
export class SmartAlbumTooltip {
  /** 生成 tooltip 文本，无法描述时返回空串 */
  static build(album: PhotoSmartAlbumItem): string {
    const type = album.type.trim();
    const filter = album.filterContent;
    const keys = Object.keys(filter);
    if (keys.length === 0) {
      return '';
    }

    if (type === 'smart_date') {
      const mode = SmartAlbumTooltip.strOr(filter['mode'], '');
      if (mode === 'anniversary') {
        const repeat = SmartAlbumTooltip.strOr(filter['repeat'], 'year');
        const hasDay = filter['day'] !== undefined && filter['day'] !== null;
        const hasMonth = filter['month'] !== undefined && filter['month'] !== null;
        const day = SmartAlbumTooltip.intOr(filter['day'], -1);
        const month = SmartAlbumTooltip.intOr(filter['month'], -1);
        if (repeat === 'month') {
          if (!hasDay) {
            return '';
          }
          const p = new Map<string, string>();
          p.set('day', `${day}`);
          return L10n.t('smart_album_tooltip_every_month_day', `每月 ${day} 日`, p);
        }
        if (!hasDay || !hasMonth) {
          return '';
        }
        const p = new Map<string, string>();
        p.set('month', `${month}`);
        p.set('day', `${day}`);
        return L10n.t('smart_album_tooltip_every_year_month_day', `每年 ${month} 月 ${day} 日`, p);
      }
      if (mode === 'fixed') {
        const op = SmartAlbumTooltip.strOr(filter['operator'], 'on');
        const date = SmartAlbumTooltip.formatDateText(filter['date']);
        if (date.length === 0) {
          return '';
        }
        const p = new Map<string, string>();
        p.set('date', date);
        if (op === 'before') {
          return L10n.t('smart_album_tooltip_before_date', '日期早于 @date', p);
        }
        if (op === 'after') {
          return L10n.t('smart_album_tooltip_after_date', '日期晚于 @date', p);
        }
        return L10n.t('smart_album_tooltip_on_date', '日期为 @date', p);
      }
      if (mode === 'range') {
        const start = SmartAlbumTooltip.formatDateText(filter['start']);
        const end = SmartAlbumTooltip.formatDateText(filter['end']);
        if (start.length === 0 || end.length === 0) {
          return '';
        }
        const p = new Map<string, string>();
        p.set('start', start);
        p.set('end', end);
        return L10n.t('smart_album_tooltip_between_dates', '日期介于 @start 至 @end', p);
      }
      return '';
    }

    // 条件相册：logic + conditions
    const logic = SmartAlbumTooltip.strOr(filter['logic'], 'and').toLowerCase();
    const joiner = logic === 'or' ? L10n.t('smart_album_join_or', '或')
      : L10n.t('smart_album_join_and', '且');
    const raw = filter['conditions'];
    if (raw === undefined || raw === null || !Array.isArray(raw)) {
      return '';
    }
    const parts: string[] = [];
    for (const e of raw as Object[]) {
      if (e === null || e === undefined || typeof e !== 'object') {
        continue;
      }
      const m = e as Record<string, Object>;
      const field = SmartAlbumTooltip.strOr(m['field'], '');
      const op = SmartAlbumTooltip.strOr(m['operator'], '');
      const value = m['value'];
      const text = SmartAlbumTooltip.formatConditionItem(field, op, value);
      if (text.trim().length > 0) {
        parts.push(text);
      }
    }
    if (parts.length === 0) {
      return '';
    }
    return parts.join(joiner);
  }

  private static strOr(v: Object | undefined | null, fallback: string): string {
    if (v === undefined || v === null) {
      return fallback;
    }
    const s = `${v}`.trim();
    return s.length > 0 ? s : fallback;
  }

  private static intOr(v: Object | undefined | null, fallback: number): number {
    if (v === undefined || v === null) {
      return fallback;
    }
    const n = parseInt(`${v}`, 10);
    return isNaN(n) ? fallback : n;
  }

  private static formatDateText(v: Object | undefined | null): string {
    if (v === undefined || v === null) {
      return '';
    }
    const s = `${v}`.trim();
    if (s.length === 0) {
      return '';
    }
    const m = s.match(/^(\d{4})-(\d{2})-(\d{2})$/);
    if (m === null) {
      return s;
    }
    const y = parseInt(m[1], 10);
    const mm = parseInt(m[2], 10);
    const dd = parseInt(m[3], 10);
    if (isNaN(y) || isNaN(mm) || isNaN(dd)) {
      return s;
    }
    const p = new Map<string, string>();
    p.set('year', `${y}`);
    p.set('month', `${mm}`);
    p.set('day', `${dd}`);
    p.set('month2', m[2]);
    p.set('day2', m[3]);
    return L10n.t('smart_album_date_format_ymd', `${y} 年 ${mm} 月 ${dd} 日`, p);
  }

  private static fieldLabel(field: string): string {
    switch (field.trim()) {
      case 'filename':
        return L10n.t('filename', '文件名');
      case 'path':
        return L10n.t('path', '路径');
      case 'camera':
        return L10n.t('smart_album_field_camera', '相机');
      case 'size_mb':
        return L10n.t('size', '大小');
      case 'duration_min':
        return L10n.t('smart_album_field_duration', '时长');
      case 'width':
        return L10n.t('smart_album_field_width', '宽度');
      case 'height':
        return L10n.t('smart_album_field_height', '高度');
      default:
        return field.trim();
    }
  }

  private static formatConditionItem(field: string, operator: string, value: Object | undefined):
    string {
    const f = field.trim();
    if (f.length === 0) {
      return '';
    }
    const op = operator.trim();
    if (op.length === 0) {
      return '';
    }

    if (op === 'contains') {
      const s = value === undefined || value === null ? '' : `${value}`;
      if (s.trim().length === 0) {
        return '';
      }
      const p = new Map<string, string>();
      p.set('field', SmartAlbumTooltip.fieldLabel(f));
      p.set('value', s);
      return L10n.t('smart_album_tooltip_contains', '@field 包含 @value', p);
    }

    if (op !== 'gt' && op !== 'eq' && op !== 'lt') {
      return '';
    }
    const n = parseFloat(`${value ?? ''}`);
    if (isNaN(n)) {
      return '';
    }

    const opText = op === 'gt' ? L10n.t('smart_album_cmp_gt', '大于')
      : (op === 'lt' ? L10n.t('smart_album_cmp_lt', '小于') : L10n.t('smart_album_cmp_eq', '等于'));

    const v = n % 1 === 0 ? `${Math.trunc(n)}` : `${n}`;

    const p = new Map<string, string>();
    p.set('field', SmartAlbumTooltip.fieldLabel(f));
    p.set('op', opText);
    p.set('value', v);
    if (f === 'size_mb') {
      p.set('unit', L10n.t('smart_album_unit_mb', 'MB'));
      return L10n.t('smart_album_tooltip_compare', '@field @op @value @unit', p);
    }
    if (f === 'duration_min') {
      p.set('unit', L10n.t('smart_album_unit_min', '分钟'));
      return L10n.t('smart_album_tooltip_compare', '@field @op @value @unit', p);
    }
    return L10n.t('smart_album_tooltip_compare_no_unit', '@field @op @value', p);
  }
}
