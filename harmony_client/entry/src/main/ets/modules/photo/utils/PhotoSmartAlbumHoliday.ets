import { L10n } from '../../../core/localization/L10n';
import { APIClient } from '../../../core/network/APIClient';
import { ServerVersionUtil } from '../../media_tool/models/MediaToolModels';

/**
 * 智能相册「节假日」模式（对齐 Flutter photo_smart_album_holiday.dart）：
 * key 与服务端 photoSmartAlbumHolidayUtil.js 中 HOLIDAY_DEFS 的 key 保持一致。
 */

/** 节假日模式所需的最低服务端版本（对齐 Flutter kSmartAlbumHolidayMinServerVersion） */
export const SMART_ALBUM_HOLIDAY_MIN_SERVER_VERSION: number = 12;

export class PhotoSmartAlbumHoliday {
  readonly key: string;

  constructor(key: string) {
    this.key = key;
  }

  get name(): string {
    return L10n.t(`smart_album_holiday_${this.key}`);
  }
}

export class PhotoSmartAlbumHolidays {
  /** 预设节假日（展示顺序即选择器顺序） */
  static readonly items: PhotoSmartAlbumHoliday[] = [
    new PhotoSmartAlbumHoliday('new_year'),
    new PhotoSmartAlbumHoliday('spring_festival'),
    new PhotoSmartAlbumHoliday('qingming'),
    new PhotoSmartAlbumHoliday('labor_day'),
    new PhotoSmartAlbumHoliday('dragon_boat'),
    new PhotoSmartAlbumHoliday('mid_autumn'),
    new PhotoSmartAlbumHoliday('national_day'),
    new PhotoSmartAlbumHoliday('women_day'),
    new PhotoSmartAlbumHoliday('youth_day'),
    new PhotoSmartAlbumHoliday('children_day'),
    new PhotoSmartAlbumHoliday('army_day'),
    new PhotoSmartAlbumHoliday('christmas'),
    new PhotoSmartAlbumHoliday('easter')
  ];

  /** 默认选中项（对齐 Flutter kPhotoSmartAlbumHolidays.first） */
  static get defaultKey(): string {
    return PhotoSmartAlbumHolidays.items[0].key;
  }

  /** 服务端版本是否支持节假日模式 */
  static isSupported(): boolean {
    return ServerVersionUtil.isAtLeast(APIClient.getInstance().state.serverVersion,
      SMART_ALBUM_HOLIDAY_MIN_SERVER_VERSION);
  }

  static isValidKey(key: string | undefined): boolean {
    if (key === undefined || key.length === 0) {
      return false;
    }
    return PhotoSmartAlbumHolidays.items.some((h: PhotoSmartAlbumHoliday) => h.key === key);
  }

  /** 节假日展示名；未识别的 key 原样返回（对齐 Flutter smartAlbumHolidayName） */
  static nameOf(key: string | undefined): string {
    if (key === undefined) {
      return '';
    }
    for (const h of PhotoSmartAlbumHolidays.items) {
      if (h.key === key) {
        return h.name;
      }
    }
    return key;
  }

  /** 节假日说明文案；语言包缺失该描述时返回 undefined（对齐 Flutter description） */
  static descriptionOf(key: string | undefined): string | undefined {
    if (key === undefined) {
      return undefined;
    }
    const k = `smart_album_holiday_${key}_desc`;
    const text = L10n.t(k);
    return text === k ? undefined : text;
  }
}
