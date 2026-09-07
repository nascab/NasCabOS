import { L10n } from '../../core/localization/L10n';

/** 各语言星期几全称（周一为起始索引 0），对齐 Flutter DateFormat.EEEE(locale) */
const WEEKDAYS_BY_LOCALE: Map<string, string[]> = new Map<string, string[]>([
  ['zh_cn', ['星期一', '星期二', '星期三', '星期四', '星期五', '星期六', '星期日']],
  ['en_us', ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday']],
  ['fr_fr', ['lundi', 'mardi', 'mercredi', 'jeudi', 'vendredi', 'samedi', 'dimanche']],
  ['de_de', ['Montag', 'Dienstag', 'Mittwoch', 'Donnerstag', 'Freitag', 'Samstag', 'Sonntag']],
  ['pt_br', ['segunda-feira', 'terça-feira', 'quarta-feira', 'quinta-feira', 'sexta-feira', 'sábado', 'domingo']],
  ['ja_jp', ['月曜日', '火曜日', '水曜日', '木曜日', '金曜日', '土曜日', '日曜日']],
  ['ru_ru', ['понедельник', 'вторник', 'среда', 'четверг', 'пятница', 'суббота', 'воскресенье']],
  ['th_th', ['วันจันทร์', 'วันอังคาร', 'วันพุธ', 'วันพฤหัสบดี', 'วันศุกร์', 'วันเสาร์', 'วันอาทิตย์']],
  ['ko_kr', ['월요일', '화요일', '수요일', '목요일', '금요일', '토요일', '일요일']],
  ['es_es', ['lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábado', 'domingo']],
  ['ar_ar', ['الإثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت', 'الأحد']],
  ['vi_vn', ['Thứ Hai', 'Thứ Ba', 'Thứ Tư', 'Thứ Năm', 'Thứ Sáu', 'Thứ Bảy', 'Chủ Nhật']],
  ['id_id', ['Senin', 'Selasa', 'Rabu', 'Kamis', 'Jumat', 'Sabtu', 'Minggu']],
]);

/**
 * 照片模块日期工具（对齐 Flutter photo_timeline_item_date / photo_timeline_item 中的格式化逻辑）
 */
export class PhotoDateUtil {
  /** 根据日期字符串（yyyy-MM-dd…）返回本地化星期几；解析失败返回空串 */
  static weekdayFromDate(dateStr: string): string {
    const m = dateStr.trim().match(/^(\d+)-(\d+)-(\d+)/);
    if (m === null) {
      return '';
    }
    const year = parseInt(m[1], 10);
    const month = parseInt(m[2], 10);
    const day = parseInt(m[3], 10);
    if (isNaN(year) || isNaN(month) || isNaN(day)) {
      return '';
    }
    // JS getDay(): 0=周日 → 转为周一为 0 的索引
    const dayIdx = (new Date(year, month - 1, day, 12).getDay() + 6) % 7;
    const names = WEEKDAYS_BY_LOCALE.get(L10n.locale.toLowerCase());
    if (names === undefined) {
      return WEEKDAYS_BY_LOCALE.get('en_us')![dayIdx];
    }
    return names[dayIdx];
  }

  /** 视频时长（秒）→ mm:ss / h:mm:ss（对齐 _formatDuration） */
  static formatDuration(duration: number): string {
    const total = Math.max(0, Math.floor(duration));
    const hours = Math.floor(total / 3600);
    const minutes = Math.floor((total % 3600) / 60);
    const seconds = total % 60;
    const minStr = `${minutes}`.padStart(2, '0');
    const secStr = `${seconds}`.padStart(2, '0');
    if (hours > 0) {
      return `${hours}:${minStr}:${secStr}`;
    }
    return `${minStr}:${secStr}`;
  }
}
