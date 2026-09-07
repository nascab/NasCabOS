import { L10n } from '../../../core/localization/L10n';
import { AppTheme } from '../../../core/theme/AppTheme';
import { SheetHandle, SheetParamsBase, SheetUtil } from '../../../common/SheetUtil';

/**
 * 日期选择底部弹层（对齐 Flutter showDatePicker firstDate=1970 / lastDate=2100）：
 * 三列滚轮（年 1970-2100 / 月 1-12 / 日 1-31），默认今天；确认回调 'yyyy-MM-dd'。
 * ArkTS 端无既有 DatePicker 用法，复用 SheetUtil 实现。
 */
class PhotoDatePickerSheetParams extends SheetParamsBase {
  /** 初始日期 'yyyy-MM-dd'，空串取今天 */
  initialDate: string = '';
  onPicked: (date: string) => void = (_d: string): void => {
  };
}

@Builder
function PhotoDatePickerSheetContent(p: PhotoDatePickerSheetParams) {
  PhotoDatePickerSheetInner({ p: p })
}

@ComponentV2
struct PhotoDatePickerSheetInner {
  @Param p: PhotoDatePickerSheetParams = new PhotoDatePickerSheetParams();
  /** 选中下标（yearOptions/monthOptions/dayOptions 内的序号） */
  @Local selYear: number = 0;
  @Local selMonth: number = 0;
  @Local selDay: number = 0;
  private yearOptions: string[] = [];
  private monthOptions: string[] = [];
  private dayOptions: string[] = [];

  aboutToAppear(): void {
    for (let y = 1970; y <= 2100; y++) {
      this.yearOptions.push(`${y}`);
    }
    for (let m = 1; m <= 12; m++) {
      this.monthOptions.push(`${m}`);
    }
    for (let d = 1; d <= 31; d++) {
      this.dayOptions.push(`${d}`);
    }
    // 初始日期：非法/为空时取今天（对齐 Flutter initialDate ?? today）
    const now = new Date();
    let year = now.getFullYear();
    let month = now.getMonth() + 1;
    let day = now.getDate();
    const m = this.p.initialDate.trim().match(/^(\d{4})-(\d{2})-(\d{2})$/);
    if (m !== null) {
      year = parseInt(m[1], 10);
      month = parseInt(m[2], 10);
      day = parseInt(m[3], 10);
      if (isNaN(year) || isNaN(month) || isNaN(day)) {
        year = now.getFullYear();
        month = now.getMonth() + 1;
        day = now.getDate();
      }
    }
    if (year < 1970 || year > 2100) {
      year = Math.min(2100, Math.max(1970, year));
    }
    this.selYear = year - 1970;
    this.selMonth = month - 1;
    this.selDay = day - 1;
  }

  private pad2(n: number): string {
    return n < 10 ? `0${n}` : `${n}`;
  }

  private confirm(): void {
    const date = `${this.yearOptions[this.selYear]}-${this.pad2(this.selMonth + 1)}-${this.pad2(this.selDay + 1)}`;
    this.p.close();
    this.p.onPicked(date);
  }

  build() {
    Column() {
      SheetHandle()
      Text(L10n.t('smart_album_date_label_date', '日期'))
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppTheme.current().onSurface)
        .width('100%')
        .padding({ left: 20, right: 20, top: 4, bottom: 8 })

      Row({ space: 8 }) {
        TextPicker({ range: this.yearOptions, selected: this.selYear })
          .layoutWeight(2)
          .onChange((value: string | string[], index: number | number[]) => {
            this.selYear = PhotoDatePickerSheetInner.indexOf(index);
          })
        TextPicker({ range: this.monthOptions, selected: this.selMonth })
          .layoutWeight(1)
          .onChange((value: string | string[], index: number | number[]) => {
            this.selMonth = PhotoDatePickerSheetInner.indexOf(index);
          })
        TextPicker({ range: this.dayOptions, selected: this.selDay })
          .layoutWeight(1)
          .onChange((value: string | string[], index: number | number[]) => {
            this.selDay = PhotoDatePickerSheetInner.indexOf(index);
          })
      }
      .width('100%')
      .height(160)

      Divider()
        .color(AppTheme.current().divider)

      Row() {
        Button(L10n.cancel)
          .fontSize(14)
          .fontColor(AppTheme.current().primary)
          .backgroundColor(Color.Transparent)
          .height(40)
          .layoutWeight(1)
          .onClick((): void => {
            this.p.close();
          })
        Button(L10n.confirm)
          .fontSize(14)
          .fontColor(AppTheme.current().buttonText)
          .backgroundColor(AppTheme.current().buttonBg)
          .height(40)
          .layoutWeight(1)
          .onClick((): void => {
            this.confirm();
          })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 8, bottom: 28 })
    }
    .borderRadius({ topLeft: 16, topRight: 16 })
    .backgroundColor(AppTheme.current().surfaceBg)
  }

  /** onChange 回调 index 可能是单值或数组（单列恒为单值），统一取首个 */
  private static indexOf(index: number | number[]): number {
    if (Array.isArray(index)) {
      return index.length > 0 ? index[0] : 0;
    }
    return index;
  }
}

/**
 * 打开日期选择弹层；确认时回调 'yyyy-MM-dd'，取消不回调。
 */
export function showPhotoDatePickerSheet(initialDate: string, onPicked: (date: string) => void): void {
  const p = new PhotoDatePickerSheetParams();
  p.initialDate = initialDate;
  p.onPicked = onPicked;
  SheetUtil.present(p, wrapBuilder(PhotoDatePickerSheetContent));
}
