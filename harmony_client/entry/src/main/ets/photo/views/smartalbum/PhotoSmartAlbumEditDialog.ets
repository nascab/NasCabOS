import { L10n } from '../../../core/localization/L10n';
import { AppTheme } from '../../../core/theme/AppTheme';
import { PickOption, showOptionPickSheet } from '../../../common/components/OptionPickSheet';
import { PhotoSmartAlbumItem } from '../../models/PhotoAlbumModels';
import { showPhotoDatePickerSheet } from './PhotoDatePickerSheet';

/**
 * 新建/编辑智能相册弹窗（对齐 Flutter app_photo_smart_album_list_page.dart 的
 * _showCreateDialog/_showEditDialog/_buildSmartAlbumCreateEditDialogContent）：
 * 全屏遮罩 + 居中卡片 + 可滚动表单。album 为 undefined 时是创建模式；
 * 提交回调由列表页注入（走控制器 createSmartAlbum/updateSmartAlbum）。
 */

// ===== 条件行数据（@ObservedV2 + @Trace：字段/操作符/值变更可触发 UI 刷新） =====

@ObservedV2
export class SmartConditionItem {
  @Trace field: string = 'filename';
  @Trace operator: string = 'contains';
  @Trace value: string = '';

  constructor(field: string, operator: string, value: string) {
    this.field = field;
    this.operator = operator;
    this.value = value;
  }
}

// ===== 字段类型与解析工具（对齐 Flutter _conditionFieldMeta/_parse* 辅助函数） =====

/** 文本字段（操作符固定 contains） */
function isTextField(field: string): boolean {
  return field === 'filename' || field === 'path' || field === 'camera';
}

/** 数值字段（操作符 gt/eq/lt） */
function isNumberField(field: string): boolean {
  return field === 'size_mb' || field === 'duration_min' || field === 'width' || field === 'height';
}

/** 字段是否合法 */
function isValidField(field: string): boolean {
  return isTextField(field) || isNumberField(field);
}

/** 字段展示名（对齐 Flutter 下拉项文案） */
function conditionFieldLabel(field: string): string {
  if (field === 'filename') {
    return L10n.t('filename', '文件名');
  }
  if (field === 'path') {
    return L10n.t('path', '路径');
  }
  if (field === 'camera') {
    return L10n.t('smart_album_field_camera', '相机');
  }
  if (field === 'size_mb') {
    return `${L10n.t('size', '大小')}(${L10n.t('smart_album_unit_mb', 'MB')})`;
  }
  if (field === 'duration_min') {
    return `${L10n.t('smart_album_field_duration', '时长')}(${L10n.t('smart_album_unit_min', '分钟')})`;
  }
  if (field === 'width') {
    return `${L10n.t('smart_album_field_width', '宽度')}(${L10n.t('smart_album_unit_px', 'px')})`;
  }
  if (field === 'height') {
    return `${L10n.t('smart_album_field_height', '高度')}(${L10n.t('smart_album_unit_px', 'px')})`;
  }
  return field;
}

function smartStr(v: Object | undefined | null): string {
  if (v === undefined || v === null) {
    return '';
  }
  return `${v}`;
}

function smartInt(v: Object | undefined | null, fallback: number): number {
  if (v === undefined || v === null) {
    return fallback;
  }
  const n = parseInt(`${v}`, 10);
  return isNaN(n) ? fallback : n;
}

/** 解析条件逻辑（对齐 Flutter _parseConditionLogic） */
function parseConditionLogic(fc: Record<string, Object>): string {
  return smartStr(fc['logic']).trim().toLowerCase() === 'or' ? 'or' : 'and';
}

/** 解析条件行列表，过滤非法字段/操作符（对齐 Flutter _parseConditionItems） */
function parseConditionItems(fc: Record<string, Object>): SmartConditionItem[] {
  const out: SmartConditionItem[] = [];
  const raw = fc['conditions'];
  if (raw === undefined || raw === null || !Array.isArray(raw)) {
    return out;
  }
  for (const e of raw as Object[]) {
    if (e === null || e === undefined || typeof e !== 'object') {
      continue;
    }
    const m = e as Record<string, Object>;
    const field = smartStr(m['field']);
    if (!isValidField(field)) {
      continue;
    }
    const op = smartStr(m['operator']);
    if (isTextField(field)) {
      if (op !== 'contains') {
        continue;
      }
      out.push(new SmartConditionItem(field, 'contains', smartStr(m['value'])));
    } else if (isNumberField(field)) {
      if (op !== 'gt' && op !== 'eq' && op !== 'lt') {
        continue;
      }
      out.push(new SmartConditionItem(field, op, smartStr(m['value'])));
    }
  }
  return out;
}

/** 解析日期模式（对齐 Flutter _parseDateMode，默认 fixed） */
function parseDateMode(fc: Record<string, Object>): string {
  const m = smartStr(fc['mode']);
  if (m === 'anniversary' || m === 'fixed' || m === 'range') {
    return m;
  }
  return 'fixed';
}

/** 解析固定日期操作符（对齐 Flutter _parseFixedOperator，默认 on） */
function parseFixedOperator(fc: Record<string, Object>): string {
  const v = smartStr(fc['operator']);
  if (v === 'before' || v === 'after' || v === 'on') {
    return v;
  }
  return 'on';
}

/** 解析纪念日重复（对齐 Flutter _parseAnniversaryRepeat，默认 year） */
function parseAnniversaryRepeat(fc: Record<string, Object>): string {
  const v = smartStr(fc['repeat']);
  if (v === 'month' || v === 'year') {
    return v;
  }
  return 'year';
}

/** 解析纪念日月份（1-12，默认 1，对齐 Flutter _parseAnniversaryMonth） */
function parseAnniversaryMonth(fc: Record<string, Object>): number {
  return Math.min(12, Math.max(1, smartInt(fc['month'], 1)));
}

/** 解析纪念日日（1-31，默认 1，对齐 Flutter _parseAnniversaryDay） */
function parseAnniversaryDay(fc: Record<string, Object>): number {
  return Math.min(31, Math.max(1, smartInt(fc['day'], 1)));
}

/** 解析 yyyy-MM-dd 日期字符串，非法返回空串（对齐 Flutter _parseDate） */
function parseDateStr(v: Object | undefined | null): string {
  const s = smartStr(v).trim();
  if (!/^\d{4}-\d{2}-\d{2}$/.test(s)) {
    return '';
  }
  return s;
}

/** 'yyyy-MM-dd' 格式化 */
function formatDateYmd(year: number, month: number, day: number): string {
  const mm = month < 10 ? `0${month}` : `${month}`;
  const dd = day < 10 ? `0${day}` : `${day}`;
  return `${year}-${mm}-${dd}`;
}

@ComponentV2
export struct PhotoSmartAlbumEditDialog {
  /** 编辑目标；undefined 表示创建模式 */
  @Param album: PhotoSmartAlbumItem | undefined = undefined;
  /** 提交回调：返回 true 表示成功（列表页注入控制器 create/update 包装） */
  @Param onSubmit: (name: string, type: string, filterContent: Record<string, Object>) =>
    Promise<boolean> =
    (_name: string, _type: string, _filterContent: Record<string, Object>): Promise<boolean> =>
      Promise.resolve(false);
  @Param onDismiss: () => void = (): void => {
  };
  @Local name: string = '';
  /** smart_date | condition */
  @Local type: string = 'smart_date';
  /** fixed | range | anniversary */
  @Local dateMode: string = 'anniversary';
  /** on | before | after */
  @Local fixedOperator: string = 'on';
  /** 'yyyy-MM-dd'，空串表示未选择 */
  @Local fixedDate: string = '';
  @Local rangeStart: string = '';
  @Local rangeEnd: string = '';
  /** year | month */
  @Local anniversaryRepeat: string = 'year';
  @Local anniversaryMonth: number = 1;
  @Local anniversaryDay: number = 1;
  /** and | or */
  @Local conditionLogic: string = 'and';
  @Local conditionItems: SmartConditionItem[] = [];
  @Local saving: boolean = false;

  aboutToAppear(): void {
    if (this.album !== undefined) {
      // 编辑模式预填（对齐 Flutter _showEditDialog 的 _parse* 系列）
      const fc = this.album.filterContent;
      this.name = this.album.name;
      this.type = this.album.type.trim().length > 0 ? this.album.type : 'condition';
      this.conditionLogic = parseConditionLogic(fc);
      this.conditionItems = parseConditionItems(fc);
      this.dateMode = parseDateMode(fc);
      this.fixedOperator = parseFixedOperator(fc);
      this.fixedDate = parseDateStr(fc['date']);
      this.rangeStart = parseDateStr(fc['start']);
      this.rangeEnd = parseDateStr(fc['end']);
      this.anniversaryRepeat = parseAnniversaryRepeat(fc);
      this.anniversaryMonth = parseAnniversaryMonth(fc);
      this.anniversaryDay = parseAnniversaryDay(fc);
    } else {
      // 创建模式默认值（对齐 Flutter _showCreateDialog）
      const now = new Date();
      this.type = 'smart_date';
      this.dateMode = 'anniversary';
      this.fixedOperator = 'on';
      this.fixedDate = formatDateYmd(now.getFullYear(), now.getMonth() + 1, now.getDate());
      this.anniversaryRepeat = 'year';
      this.anniversaryMonth = now.getMonth() + 1;
      this.anniversaryDay = now.getDate();
    }
  }

  // ===== filter_content 构建（对齐 Flutter _buildFilterContent，逐字段精确一致） =====

  private buildFilterContent(): Record<string, Object> | undefined {
    if (this.type === 'smart_date') {
      if (this.dateMode === 'fixed') {
        if (this.fixedDate.length === 0) {
          return undefined;
        }
        const m: Record<string, Object> = {
          'mode': 'fixed',
          'operator': this.fixedOperator,
          'date': this.fixedDate
        };
        return m;
      }
      if (this.dateMode === 'range') {
        if (this.rangeStart.length === 0 || this.rangeEnd.length === 0) {
          return undefined;
        }
        const m: Record<string, Object> = {
          'mode': 'range',
          'start': this.rangeStart,
          'end': this.rangeEnd
        };
        return m;
      }
      if (this.dateMode === 'anniversary') {
        if (this.anniversaryRepeat === 'year') {
          const m: Record<string, Object> = {
            'mode': 'anniversary',
            'repeat': 'year',
            'month': this.anniversaryMonth,
            'day': this.anniversaryDay
          };
          return m;
        }
        const m: Record<string, Object> = {
          'mode': 'anniversary',
          'repeat': 'month',
          'day': this.anniversaryDay
        };
        return m;
      }
      return undefined;
    }

    // 条件相册：文本 → contains + 字符串；数值 → gt/eq/lt + 数字；空值行跳过
    const conds: Array<Record<string, Object>> = [];
    for (const item of this.conditionItems) {
      if (isTextField(item.field)) {
        const v = item.value.trim();
        if (v.length === 0) {
          continue;
        }
        const c: Record<string, Object> = { 'field': item.field, 'operator': 'contains', 'value': v };
        conds.push(c);
        continue;
      }
      if (isNumberField(item.field)) {
        const raw = item.value.trim();
        const n = parseFloat(raw);
        if (raw.length === 0 || isNaN(n)) {
          continue;
        }
        if (item.operator !== 'gt' && item.operator !== 'eq' && item.operator !== 'lt') {
          continue;
        }
        const c: Record<string, Object> = { 'field': item.field, 'operator': item.operator, 'value': n };
        conds.push(c);
      }
    }
    if (conds.length === 0) {
      return undefined;
    }
    const logic = this.conditionLogic.toLowerCase() === 'or' ? 'or' : 'and';
    const m: Record<string, Object> = { 'logic': logic, 'conditions': conds };
    return m;
  }

  /** 校验：名称非空且 filter_content 可构建（对齐 Flutter canSubmit） */
  private canSubmit(): boolean {
    return this.name.trim().length > 0 && this.buildFilterContent() !== undefined;
  }

  private dialogTitle(): string {
    return this.album === undefined ? L10n.t('create', '创建') : L10n.t('edit', '编辑');
  }

  private confirmLabel(): string {
    return this.album === undefined ? L10n.t('create', '创建') : L10n.t('ok', '确定');
  }

  private async confirm(): Promise<void> {
    if (this.saving) {
      return;
    }
    const payload = this.buildFilterContent();
    if (payload === undefined || this.name.trim().length === 0) {
      return;
    }
    this.saving = true;
    try {
      const ok = await this.onSubmit(this.name.trim(), this.type, payload);
      if (ok) {
        this.onDismiss();
      }
    } finally {
      this.saving = false;
    }
  }

  // ===== 下拉/日期选择（对齐 Flutter DropdownButtonFormField / showDatePicker） =====

  private pickType(): void {
    const opts: PickOption[] = [
      new PickOption('smart_date', L10n.t('smart_date_album', '智能日期相册')),
      new PickOption('condition', L10n.t('condition_album', '条件相册'))
    ];
    showOptionPickSheet(L10n.t('type', '类型'), opts, this.type, (k: string): void => {
      this.type = k;
    });
  }

  private pickDateMode(): void {
    const opts: PickOption[] = [
      new PickOption('fixed', L10n.t('smart_album_date_mode_fixed', '指定日期')),
      new PickOption('range', L10n.t('smart_album_date_mode_range', '日期范围')),
      new PickOption('anniversary', L10n.t('smart_album_date_mode_anniversary', '纪念日'))
    ];
    showOptionPickSheet(L10n.t('smart_album_date_mode', '模式'), opts, this.dateMode, (k: string): void => {
      this.dateMode = k;
    });
  }

  private pickFixedOperator(): void {
    const opts: PickOption[] = [
      new PickOption('on', L10n.t('smart_album_date_op_on', '等于')),
      new PickOption('before', L10n.t('smart_album_date_op_before_inclusive', '早于（含）')),
      new PickOption('after', L10n.t('smart_album_date_op_after_inclusive', '晚于（含）'))
    ];
    showOptionPickSheet(L10n.t('smart_album_date_condition', '条件'), opts, this.fixedOperator,
      (k: string): void => {
        this.fixedOperator = k;
      });
  }

  private pickFixedDate(): void {
    showPhotoDatePickerSheet(this.fixedDate, (d: string): void => {
      this.fixedDate = d;
    });
  }

  private pickRangeStart(): void {
    showPhotoDatePickerSheet(this.rangeStart, (d: string): void => {
      this.rangeStart = d;
    });
  }

  private pickRangeEnd(): void {
    showPhotoDatePickerSheet(this.rangeEnd, (d: string): void => {
      this.rangeEnd = d;
    });
  }

  private pickAnniversaryRepeat(): void {
    const opts: PickOption[] = [
      new PickOption('year', L10n.t('smart_album_repeat_year', '每年')),
      new PickOption('month', L10n.t('smart_album_repeat_month', '每月'))
    ];
    showOptionPickSheet(L10n.t('smart_album_repeat', '重复'), opts, this.anniversaryRepeat,
      (k: string): void => {
        this.anniversaryRepeat = k;
      });
  }

  private pickAnniversaryMonth(): void {
    const opts: PickOption[] = [];
    for (let m = 1; m <= 12; m++) {
      opts.push(new PickOption(`${m}`, `${m}`));
    }
    showOptionPickSheet(L10n.t('smart_album_month', '月份'), opts, `${this.anniversaryMonth}`,
      (k: string): void => {
        const n = parseInt(k, 10);
        if (!isNaN(n)) {
          this.anniversaryMonth = n;
        }
      });
  }

  private pickAnniversaryDay(): void {
    const opts: PickOption[] = [];
    for (let d = 1; d <= 31; d++) {
      opts.push(new PickOption(`${d}`, `${d}`));
    }
    showOptionPickSheet(L10n.t('smart_album_day', '日期'), opts, `${this.anniversaryDay}`,
      (k: string): void => {
        const n = parseInt(k, 10);
        if (!isNaN(n)) {
          this.anniversaryDay = n;
        }
      });
  }

  private pickConditionLogic(): void {
    const opts: PickOption[] = [
      new PickOption('and', L10n.t('smart_album_condition_relation_and', '满足全部（AND）')),
      new PickOption('or', L10n.t('smart_album_condition_relation_or', '满足任一（OR）'))
    ];
    showOptionPickSheet(L10n.t('smart_album_condition_relation', '条件关系'), opts, this.conditionLogic,
      (k: string): void => {
        this.conditionLogic = k;
      });
  }

  /** 切换字段：重置操作符与值（对齐 Flutter onChanged 的 field 分支逻辑） */
  private changeField(item: SmartConditionItem, field: string): void {
    item.field = field;
    if (isTextField(field)) {
      item.operator = 'contains';
    } else if (isNumberField(field)) {
      if (item.operator !== 'gt' && item.operator !== 'eq' && item.operator !== 'lt') {
        item.operator = 'gt';
      }
    }
    item.value = '';
  }

  private pickConditionField(item: SmartConditionItem): void {
    const opts: PickOption[] = [
      new PickOption('filename', conditionFieldLabel('filename')),
      new PickOption('path', conditionFieldLabel('path')),
      new PickOption('camera', conditionFieldLabel('camera')),
      new PickOption('size_mb', conditionFieldLabel('size_mb')),
      new PickOption('duration_min', conditionFieldLabel('duration_min')),
      new PickOption('width', conditionFieldLabel('width')),
      new PickOption('height', conditionFieldLabel('height'))
    ];
    showOptionPickSheet(L10n.t('smart_album_condition_field', '字段'), opts, item.field,
      (k: string): void => {
        this.changeField(item, k);
      });
  }

  private pickConditionOperator(item: SmartConditionItem): void {
    const opts: PickOption[] = [
      new PickOption('gt', L10n.t('smart_album_cmp_gt', '大于')),
      new PickOption('eq', L10n.t('smart_album_cmp_eq', '等于')),
      new PickOption('lt', L10n.t('smart_album_cmp_lt', '小于'))
    ];
    showOptionPickSheet(L10n.t('smart_album_operator_compare', '比较'), opts, item.operator,
      (k: string): void => {
        item.operator = k;
      });
  }

  /** 新增条件行（数组整体替换触发刷新） */
  private addCondition(): void {
    const next = this.conditionItems.slice();
    next.push(new SmartConditionItem('filename', 'contains', ''));
    this.conditionItems = next;
  }

  private removeCondition(idx: number): void {
    if (idx < 0 || idx >= this.conditionItems.length) {
      return;
    }
    const next = this.conditionItems.slice();
    next.splice(idx, 1);
    this.conditionItems = next;
  }

  // ===== UI =====

  build() {
    Stack() {
      // 遮罩（Flutter barrierDismissible: false，这里点遮罩仅提示不可提交时关闭语义一致，仍允许关闭）
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#80000000')
        .onClick(() => {
          this.onDismiss();
        })

      Column() {
        Text(this.dialogTitle())
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppTheme.current().onSurface)

        Scroll() {
          Column() {
            // 名称输入（对齐 Flutter TextFormField labelText: photo_album_name）
            TextInput({ text: this.name, placeholder: L10n.t('photo_album_name', '相册名称') })
              .fontSize(14)
              .fontColor(AppTheme.current().onSurface)
              .placeholderColor(AppTheme.current().hint)
              .backgroundColor(AppTheme.current().inputFill)
              .borderRadius(8)
              .border({ width: 1, color: AppTheme.current().inputBorder })
              .height(42)
              .width('100%')
              .onChange((v: string) => {
                this.name = v;
              })

            // 类型下拉（smart_date_album / condition_album）
            this.SelectRow(L10n.t('type', '类型'), this.typeValue(), (): void => {
              this.pickType();
            })

            if (this.type === 'smart_date') {
              this.SmartDateEditor()
            } else {
              this.ConditionEditor()
            }
          }
          .width('100%')
        }
        .scrollBar(BarState.Auto)
        .width('100%')
        .align(Alignment.Top)
        .margin({ top: 14 })
        .constraintSize({ maxHeight: 440 })

        // 取消 + 确认
        Row({ space: 8 }) {
          Button(L10n.cancel)
            .fontSize(14)
            .fontColor(AppTheme.current().primary)
            .backgroundColor(Color.Transparent)
            .height(36)
            .onClick(() => {
              this.onDismiss();
            })
          Button(this.confirmLabel())
            .fontSize(14)
            .fontColor(AppTheme.current().buttonText)
            .backgroundColor(AppTheme.current().buttonBg)
            .height(36)
            .enabled(this.canSubmit() && !this.saving)
            .opacity(this.canSubmit() && !this.saving ? 1 : 0.45)
            .onClick(() => {
              void this.confirm();
            })
        }
        .justifyContent(FlexAlign.End)
        .margin({ top: 14 })
        .width('100%')
      }
      .alignItems(HorizontalAlign.Start)
      .padding(20)
      .borderRadius(24)
      .backgroundColor(AppTheme.current().surfaceBg)
      .width('86%')
      .constraintSize({ minWidth: 300, maxWidth: 560 })
    }
    .width('100%')
    .height('100%')
    .alignContent(Alignment.Center)
  }

  private typeValue(): string {
    return this.type === 'smart_date'
      ? L10n.t('smart_date_album', '智能日期相册')
      : L10n.t('condition_album', '条件相册');
  }

  private fixedOperatorValue(): string {
    if (this.fixedOperator === 'before') {
      return L10n.t('smart_album_date_op_before_inclusive', '早于（含）');
    }
    if (this.fixedOperator === 'after') {
      return L10n.t('smart_album_date_op_after_inclusive', '晚于（含）');
    }
    return L10n.t('smart_album_date_op_on', '等于');
  }

  private repeatValue(): string {
    return this.anniversaryRepeat === 'month'
      ? L10n.t('smart_album_repeat_month', '每月')
      : L10n.t('smart_album_repeat_year', '每年');
  }

  private logicValue(): string {
    return this.conditionLogic === 'or'
      ? L10n.t('smart_album_condition_relation_or', '满足任一（OR）')
      : L10n.t('smart_album_condition_relation_and', '满足全部（AND）');
  }

  private operatorValue(op: string): string {
    if (op === 'gt') {
      return L10n.t('smart_album_cmp_gt', '大于');
    }
    if (op === 'lt') {
      return L10n.t('smart_album_cmp_lt', '小于');
    }
    return L10n.t('smart_album_cmp_eq', '等于');
  }

  /** 下拉选择行（对齐 Flutter DropdownButtonFormField 外观：标签 + 当前值 + 下拉箭头） */
  @Builder
  SelectRow(label: string, value: string, onTap: () => void) {
    Column() {
      Text(label)
        .fontSize(11)
        .fontColor(AppTheme.current().hint)
        .width('100%')
      Row({ space: 6 }) {
        Text(value)
          .fontSize(14)
          .fontColor(AppTheme.current().onSurface)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        SymbolGlyph($r('sys.symbol.chevron_down'))
          .fontSize(13)
          .fontColor([AppTheme.current().hint])
      }
      .width('100%')
      .padding({ top: 3 })
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding({ left: 12, right: 12, top: 7, bottom: 7 })
    .borderRadius(8)
    .border({ width: 1, color: AppTheme.current().inputBorder })
    .backgroundColor(AppTheme.current().inputFill)
    .margin({ top: 12 })
    .onClick(() => {
      onTap();
    })
  }

  /** 日期选择行（对齐 Flutter rowLabel + InputDecorator + suffix event 图标） */
  @Builder
  DateRow(label: string, value: string, placeholder: string, onTap: () => void) {
    Column() {
      Text(label)
        .fontSize(13)
        .fontColor(AppTheme.current().onSurface)
        .width('100%')
        .padding({ bottom: 6 })
      Row({ space: 6 }) {
        Text(value.length > 0 ? value : placeholder)
          .fontSize(14)
          .fontColor(value.length > 0 ? AppTheme.current().onSurface : AppTheme.current().hint)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        SymbolGlyph($r('sys.symbol.calendar'))
          .fontSize(15)
          .fontColor([AppTheme.current().hint])
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 11, bottom: 11 })
      .borderRadius(8)
      .border({ width: 1, color: AppTheme.current().inputBorder })
      .backgroundColor(AppTheme.current().inputFill)
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .margin({ top: 12 })
    .onClick(() => {
      onTap();
    })
  }

  /** 智能日期编辑器（对齐 Flutter _buildSmartDateEditor） */
  @Builder
  SmartDateEditor() {
    Column() {
      this.SelectRow(L10n.t('smart_album_date_mode', '模式'),
        this.dateMode === 'fixed' ? L10n.t('smart_album_date_mode_fixed', '指定日期')
          : (this.dateMode === 'range' ? L10n.t('smart_album_date_mode_range', '日期范围')
            : L10n.t('smart_album_date_mode_anniversary', '纪念日')), (): void => {
          this.pickDateMode();
        })

      if (this.dateMode === 'fixed') {
        this.SelectRow(L10n.t('smart_album_date_condition', '条件'), this.fixedOperatorValue(),
          (): void => {
            this.pickFixedOperator();
          })
        this.DateRow(L10n.t('smart_album_date_label_date', '日期'), this.fixedDate,
          L10n.t('smart_album_date_pick', '请选择日期'), (): void => {
            this.pickFixedDate();
          })
      }

      if (this.dateMode === 'range') {
        this.DateRow(L10n.t('smart_album_date_label_start', '开始日期'), this.rangeStart,
          L10n.t('smart_album_date_pick_start', '请选择开始日期'), (): void => {
            this.pickRangeStart();
          })
        this.DateRow(L10n.t('smart_album_date_label_end', '结束日期'), this.rangeEnd,
          L10n.t('smart_album_date_pick_end', '请选择结束日期'), (): void => {
            this.pickRangeEnd();
          })
      }

      if (this.dateMode === 'anniversary') {
        this.SelectRow(L10n.t('smart_album_repeat', '重复'), this.repeatValue(), (): void => {
          this.pickAnniversaryRepeat();
        })
        if (this.anniversaryRepeat === 'year') {
          this.SelectRow(L10n.t('smart_album_month', '月份'), `${this.anniversaryMonth}`, (): void => {
            this.pickAnniversaryMonth();
          })
        }
        this.SelectRow(L10n.t('smart_album_day', '日期'), `${this.anniversaryDay}`, (): void => {
          this.pickAnniversaryDay();
        })
      }
    }
    .width('100%')
  }

  /** 条件编辑器（对齐 Flutter _buildConditionEditor） */
  @Builder
  ConditionEditor() {
    Column() {
      Row({ space: 10 }) {
        Column() {
          Text(L10n.t('smart_album_condition_relation', '条件关系'))
            .fontSize(11)
            .fontColor(AppTheme.current().hint)
            .width('100%')
          Row({ space: 6 }) {
            Text(this.logicValue())
              .fontSize(14)
              .fontColor(AppTheme.current().onSurface)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
            SymbolGlyph($r('sys.symbol.chevron_down'))
              .fontSize(13)
              .fontColor([AppTheme.current().hint])
          }
          .width('100%')
          .padding({ top: 3 })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        .padding({ left: 12, right: 12, top: 7, bottom: 7 })
        .borderRadius(8)
        .border({ width: 1, color: AppTheme.current().inputBorder })
        .backgroundColor(AppTheme.current().inputFill)
        .margin({ top: 12 })
        .onClick(() => {
          this.pickConditionLogic();
        })

        // 添加条件按钮
        Button() {
          Row({ space: 4 }) {
            SymbolGlyph($r('sys.symbol.plus'))
              .fontSize(14)
              .fontColor([AppTheme.current().buttonText])
            Text(L10n.t('smart_album_add_condition', '添加条件'))
              .fontSize(13)
              .fontColor(AppTheme.current().buttonText)
          }
        }
        .height(40)
        .borderRadius(8)
        .backgroundColor(AppTheme.current().buttonBg)
        .margin({ top: 12 })
        .onClick(() => {
          this.addCondition();
        })
      }
      .alignItems(VerticalAlign.Bottom)
      .width('100%')

      if (this.conditionItems.length === 0) {
        Text(L10n.t('smart_album_condition_min_one', '请添加至少一条条件'))
          .fontSize(13)
          .fontColor(AppTheme.current().hint)
          .width('100%')
          .padding(12)
          .borderRadius(8)
          .border({ width: 1, color: AppTheme.current().divider })
          .margin({ top: 12 })
      } else {
        Column({ space: 10 }) {
          ForEach(this.conditionItems, (item: SmartConditionItem, idx: number) => {
            this.ConditionRow(item, idx)
          }, (item: SmartConditionItem, idx: number) => `cond_${idx}_${item.field}`)
        }
        .width('100%')
        .margin({ top: 12 })
      }
    }
    .width('100%')
  }

  /** 单条条件行（对齐 Flutter _buildConditionRow） */
  @Builder
  ConditionRow(item: SmartConditionItem, idx: number) {
    Column({ space: 10 }) {
      Row({ space: 8 }) {
        Column() {
          Text(L10n.t('smart_album_condition_field', '字段'))
            .fontSize(11)
            .fontColor(AppTheme.current().hint)
            .width('100%')
          Row({ space: 6 }) {
            Text(conditionFieldLabel(item.field))
              .fontSize(14)
              .fontColor(AppTheme.current().onSurface)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
            SymbolGlyph($r('sys.symbol.chevron_down'))
              .fontSize(13)
              .fontColor([AppTheme.current().hint])
          }
          .width('100%')
          .padding({ top: 3 })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        .padding({ left: 12, right: 12, top: 7, bottom: 7 })
        .borderRadius(8)
        .border({ width: 1, color: AppTheme.current().inputBorder })
        .backgroundColor(AppTheme.current().inputFill)
        .onClick(() => {
          this.pickConditionField(item);
        })

        SymbolGlyph($r('sys.symbol.xmark'))
          .fontSize(15)
          .fontColor([AppTheme.current().hint])
          .onClick(() => {
            this.removeCondition(idx);
          })
      }
      .alignItems(VerticalAlign.Center)
      .width('100%')

      // 文本字段：操作符固定 contains，仅一个值输入
      if (isTextField(item.field)) {
        TextInput({ text: item.value, placeholder: L10n.t('smart_album_operator_contains', '包含') })
          .fontSize(14)
          .fontColor(AppTheme.current().onSurface)
          .placeholderColor(AppTheme.current().hint)
          .backgroundColor(AppTheme.current().inputFill)
          .borderRadius(8)
          .border({ width: 1, color: AppTheme.current().inputBorder })
          .height(42)
          .width('100%')
          .onChange((v: string) => {
            item.value = v;
          })
      } else if (isNumberField(item.field)) {
        // 数值字段：操作符下拉 + 数字值输入
        Row({ space: 8 }) {
          Column() {
            Text(L10n.t('smart_album_operator_compare', '比较'))
              .fontSize(11)
              .fontColor(AppTheme.current().hint)
              .width('100%')
            Row({ space: 6 }) {
              Text(this.operatorValue(item.operator))
                .fontSize(14)
                .fontColor(AppTheme.current().onSurface)
                .maxLines(1)
                .layoutWeight(1)
              SymbolGlyph($r('sys.symbol.chevron_down'))
                .fontSize(13)
                .fontColor([AppTheme.current().hint])
            }
            .width('100%')
            .padding({ top: 3 })
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(2)
          .padding({ left: 12, right: 12, top: 7, bottom: 7 })
          .borderRadius(8)
          .border({ width: 1, color: AppTheme.current().inputBorder })
          .backgroundColor(AppTheme.current().inputFill)
          .onClick(() => {
            this.pickConditionOperator(item);
          })

          TextInput({ text: item.value, placeholder: L10n.t('smart_album_value', '值') })
            .type(InputType.NUMBER_DECIMAL)
            .fontSize(14)
            .fontColor(AppTheme.current().onSurface)
            .placeholderColor(AppTheme.current().hint)
            .backgroundColor(AppTheme.current().inputFill)
            .borderRadius(8)
            .border({ width: 1, color: AppTheme.current().inputBorder })
            .height(42)
            .layoutWeight(3)
            .onChange((v: string) => {
              item.value = v;
            })
        }
        .alignItems(VerticalAlign.Bottom)
        .width('100%')
      }
    }
    .padding(10)
    .borderRadius(8)
    .border({ width: 1, color: AppTheme.current().divider })
    .width('100%')
  }
}
