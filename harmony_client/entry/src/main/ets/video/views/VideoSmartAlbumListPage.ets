import { L10n } from '../../core/localization/L10n';
import { AppTheme } from '../../core/theme/AppTheme';
import { DialogUtil, DialogParamsBase, DialogResult } from '../../common/DialogUtil';
import { PageScaffold } from '../../common/PageScaffold';
import { SheetHandle, SheetListItem, SheetParamsBase, SheetUtil } from '../../common/SheetUtil';
import { BorderedIconButton } from '../../common/components/BorderedIconButton';
import { EmptyState } from '../../common/components/EmptyState';
import { PickOption, showOptionPickSheet } from '../../common/components/OptionPickSheet';
import { NavUtil } from '../../common/NavUtil';
import { AppRouter } from '../../router/AppRouter';
import { VideoSmartAlbumItem } from '../models/VideoModels';
import { VideoAlbumVideosPageParam, VideoSmartAlbumListPageParam } from '../router/VideoRoutes';
import { VideoSmartAlbumListController } from '../controllers/VideoAlbumListControllers';
import { VideoAlbumCard } from '../components/VideoAlbumCard';
import { VideoSmartAlbumTooltipUtil } from '../utils/VideoItemUtils';

/**
 * 智能相册列表页（对齐 Flutter AppVideoSmartAlbumListPage 移动端版式）：
 * 顶栏（搜索/排序/创建）+ 自适应网格卡片（左上信息角标查看筛选条件）+
 * 底部加载更多；创建/编辑弹窗含条件编辑器（字段/比较符/值，and-or 组合）。
 */

// ===== 条件编辑器辅助（对齐 Flutter _conditionFieldMeta / _buildFilterContent / _parseCondition*） =====

const COND_FIELDS: string[] = [
  'name', 'nfo_actor', 'nfo_director', 'nfo_genres', 'nfo_regions',
  'path', 'year', 'score', 'duration_min'
];
const COND_TEXT_FIELDS: string[] = ['name', 'nfo_actor', 'nfo_director', 'nfo_genres', 'nfo_regions', 'path'];

function isTextField(field: string): boolean {
  return COND_TEXT_FIELDS.includes(field.trim());
}

function fieldLabel(field: string): string {
  switch (field.trim()) {
    case 'name':
      return L10n.t('smart_album_field_name', '名称');
    case 'nfo_actor':
      return L10n.t('smart_album_field_nfo_actor', '演员');
    case 'nfo_director':
      return L10n.t('smart_album_field_nfo_director', '导演');
    case 'nfo_genres':
      return L10n.t('smart_album_field_nfo_genres', '类型');
    case 'nfo_regions':
      return L10n.t('smart_album_field_nfo_regions', '地区');
    case 'path':
      return L10n.t('path', '路径');
    case 'year':
      return L10n.t('smart_album_field_year', '年份');
    case 'score':
      return L10n.t('smart_album_field_score', '评分');
    case 'duration_min':
      return L10n.t('smart_album_field_duration', '时长（分钟）');
    default:
      return field.trim();
  }
}

/** 单条筛选条件（对齐 Flutter _SmartConditionItem） */
export class SmartConditionItem {
  field: string = 'name';
  operator: string = 'contains';
  value: string = '';

  constructor(field: string, operator: string, value: string) {
    this.field = field;
    this.operator = operator;
    this.value = value;
  }
}

function newEmptyCondition(): SmartConditionItem {
  return new SmartConditionItem('name', 'contains', '');
}

/** filterContent.logic（and/or） */
function parseConditionLogic(filterContent: Record<string, Object>): string {
  const v = `${filterContent['logic'] ?? ''}`.trim().toLowerCase();
  return v === 'or' ? 'or' : 'and';
}

/** filterContent.conditions → 有效条件列表（无效字段/操作符丢弃，对齐 Flutter） */
function parseConditionItems(filterContent: Record<string, Object>): SmartConditionItem[] {
  const out: SmartConditionItem[] = [];
  const raw = filterContent['conditions'];
  if (!Array.isArray(raw)) {
    return out;
  }
  for (const e of raw as Object[]) {
    if (e === null || e === undefined || typeof e !== 'object') {
      continue;
    }
    const m = e as Record<string, Object>;
    const field = `${m['field'] ?? ''}`.trim();
    if (!COND_FIELDS.includes(field)) {
      continue;
    }
    const op = `${m['operator'] ?? ''}`.trim();
    const value = m['value'];
    if (isTextField(field)) {
      if (op !== 'contains') {
        continue;
      }
      out.push(new SmartConditionItem(field, 'contains', `${value ?? ''}`));
      continue;
    }
    if (op === 'gt' || op === 'eq' || op === 'lt') {
      out.push(new SmartConditionItem(field, op, `${value ?? ''}`));
    }
  }
  return out;
}

/** 条件列表 → filterContent（无有效条件时返回 undefined，对齐 Flutter _buildFilterContent） */
function buildFilterContent(logic: string, items: SmartConditionItem[]): Record<string, Object> | undefined {
  const mapped: Record<string, Object>[] = [];
  for (const item of items) {
    if (!COND_FIELDS.includes(item.field.trim())) {
      continue;
    }
    if (isTextField(item.field)) {
      const v = item.value.trim();
      if (v.length === 0) {
        continue;
      }
      const row: Record<string, Object> = { 'field': item.field, 'operator': 'contains', 'value': v };
      mapped.push(row);
      continue;
    }
    const n = Number(item.value.trim());
    if (item.value.trim().length === 0 || isNaN(n)) {
      continue;
    }
    if (item.operator !== 'gt' && item.operator !== 'eq' && item.operator !== 'lt') {
      continue;
    }
    const row: Record<string, Object> = { 'field': item.field, 'operator': item.operator, 'value': n };
    mapped.push(row);
  }
  if (mapped.length === 0) {
    return undefined;
  }
  const content: Record<string, Object> = {
    'logic': logic.toLowerCase() === 'or' ? 'or' : 'and',
    'conditions': mapped as Object[]
  };
  return content;
}

// ===== 创建/编辑弹窗（对齐 Flutter _showCreateDialog/_showEditDialog 的条件编辑器） =====

class SmartAlbumEditDialogParams extends DialogParamsBase {
  title: string = '';
  initialName: string = '';
  initialLogic: string = 'and';
  initialConditions: SmartConditionItem[] = [];
  confirmText: string = '';
  onConfirm: (name: string, filterContent: Record<string, Object>) => void = (_n: string,
    _f: Record<string, Object>): void => {
  };
}

@Builder
function SmartAlbumEditDialogContent(p: SmartAlbumEditDialogParams) {
  SmartAlbumEditDialogInner({ p: p })
}

@ComponentV2
struct SmartAlbumEditDialogInner {
  @Param p: SmartAlbumEditDialogParams = new SmartAlbumEditDialogParams();
  @Local name: string = '';
  @Local logic: string = 'and';
  @Local conds: SmartConditionItem[] = [];
  @Local canSubmit: boolean = false;
  @Local structTick: number = 0;

  aboutToAppear(): void {
    this.name = this.p.initialName;
    this.logic = this.p.initialLogic;
    this.conds = this.p.initialConditions.length > 0
      ? this.p.initialConditions.slice() : [newEmptyCondition()];
    this.recomputeCanSubmit();
  }

  private recomputeCanSubmit(): void {
    let valid = this.name.trim().length > 0;
    if (valid) {
      valid = buildFilterContent(this.logic, this.conds) !== undefined;
    }
    this.canSubmit = valid;
  }

  /** 条件结构变化（增删/改字段）后强制刷新列表 */
  private refreshStruct(): void {
    this.conds = this.conds.slice();
    this.structTick++;
    this.recomputeCanSubmit();
  }

  private addCondition(): void {
    this.conds.push(newEmptyCondition());
    this.refreshStruct();
  }

  private removeCondition(idx: number): void {
    if (idx < 0 || idx >= this.conds.length) {
      return;
    }
    this.conds.splice(idx, 1);
    if (this.conds.length === 0) {
      this.conds.push(newEmptyCondition());
    }
    this.refreshStruct();
  }

  private changeField(idx: number, field: string): void {
    const item = this.conds[idx];
    if (item === undefined) {
      return;
    }
    item.field = field;
    if (!isTextField(field) && item.operator !== 'gt' && item.operator !== 'eq' && item.operator !== 'lt') {
      item.operator = 'gt';
    }
    if (isTextField(field)) {
      item.operator = 'contains';
    }
    this.refreshStruct();
  }

  private changeOperator(idx: number, op: string): void {
    const item = this.conds[idx];
    if (item === undefined) {
      return;
    }
    item.operator = op;
    this.refreshStruct();
  }

  private changeValue(idx: number, value: string): void {
    const item = this.conds[idx];
    if (item === undefined) {
      return;
    }
    item.value = value;
    this.recomputeCanSubmit();
  }

  private submit(): void {
    const content = buildFilterContent(this.logic, this.conds);
    if (content === undefined || this.name.trim().length === 0) {
      return;
    }
    this.p.onConfirm(this.name.trim(), content);
    this.p.onResult(undefined);
  }

  /** 条件行：字段下拉 + 值输入（文本）/比较符下拉（数值）+ 删除 */
  @Builder
  ConditionRow(item: SmartConditionItem, idx: number) {
    Column() {
      Row({ space: 10 }) {
        Select(this.fieldOptions()) {
          Text(fieldLabel(item.field))
        }
        .selected(this.fieldSelectedIndex(item.field))
        .value(fieldLabel(item.field))
        .font({ size: 14 })
        .fontColor(AppTheme.current().onSurface)
        .backgroundColor(AppTheme.withAlpha(AppTheme.current().onSurface, 0.05))
        .onSelect((index: number): void => {
          if (index >= 0 && index < COND_FIELDS.length) {
            this.changeField(idx, COND_FIELDS[index]);
          }
        })
        .layoutWeight(5)

        if (isTextField(item.field)) {
          TextInput({ text: item.value })
            .fontSize(14)
            .fontColor(AppTheme.current().onSurface)
            .placeholderFont({ size: 14 })
            .placeholderColor(AppTheme.current().hint)
            .backgroundColor(AppTheme.withAlpha(AppTheme.current().onSurface, 0.05))
            .borderRadius(8)
            .border({ width: 1, color: AppTheme.current().inputBorder })
            .height(40)
            .layoutWeight(4)
            .onChange((v: string): void => {
              this.changeValue(idx, v);
            })
        } else {
          Select(this.operatorOptions()) {
            Text(this.operatorLabel(item.operator))
          }
          .selected(this.operatorSelectedIndex(item.operator))
          .value(this.operatorLabel(item.operator))
          .font({ size: 14 })
          .fontColor(AppTheme.current().onSurface)
          .backgroundColor(AppTheme.withAlpha(AppTheme.current().onSurface, 0.05))
          .onSelect((index: number): void => {
            const ops: string[] = ['gt', 'eq', 'lt'];
            if (index >= 0 && index < ops.length) {
              this.changeOperator(idx, ops[index]);
            }
          })
          .layoutWeight(4)
        }

        SymbolGlyph($r('sys.symbol.xmark'))
          .fontSize(16)
          .fontColor([AppTheme.current().hint])
          .onClick(() => {
            this.removeCondition(idx);
          })
      }
      .alignItems(VerticalAlign.Center)
      .width('100%')

      if (!isTextField(item.field)) {
        TextInput({ text: item.value })
          .fontSize(14)
          .fontColor(AppTheme.current().onSurface)
          .placeholderFont({ size: 14 })
          .placeholderColor(AppTheme.current().hint)
          .backgroundColor(AppTheme.withAlpha(AppTheme.current().onSurface, 0.05))
          .borderRadius(8)
          .border({ width: 1, color: AppTheme.current().inputBorder })
          .height(40)
          .width('100%')
          .margin({ top: 10 })
          .type(InputType.NUMBER_DECIMAL)
          .onChange((v: string): void => {
            this.changeValue(idx, v);
          })
      }
    }
    .padding(10)
    .borderRadius(10)
    .border({ width: 1, color: AppTheme.withAlpha(AppTheme.current().onSurface, 0.15) })
    .width('100%')
  }

  private fieldOptions(): SelectOption[] {
    const out: SelectOption[] = [];
    for (const f of COND_FIELDS) {
      out.push({ value: fieldLabel(f) } as SelectOption);
    }
    return out;
  }

  private fieldSelectedIndex(current: string): number {
    const idx = COND_FIELDS.indexOf(current);
    return idx >= 0 ? idx : 0;
  }

  private operatorOptions(): SelectOption[] {
    const out: SelectOption[] = [];
    for (const op of ['gt', 'eq', 'lt']) {
      out.push({ value: this.operatorLabel(op) } as SelectOption);
    }
    return out;
  }

  private operatorSelectedIndex(current: string): number {
    if (current === 'eq') {
      return 1;
    }
    if (current === 'lt') {
      return 2;
    }
    return 0;
  }

  private operatorLabel(op: string): string {
    if (op === 'gt') {
      return L10n.t('smart_album_cmp_gt', '大于');
    }
    if (op === 'eq') {
      return L10n.t('smart_album_cmp_eq', '等于');
    }
    if (op === 'lt') {
      return L10n.t('smart_album_cmp_lt', '小于');
    }
    return op;
  }

  build() {
    Column() {
      Row() {
        Text(this.p.title)
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppTheme.current().onSurface)
          .layoutWeight(1)
        SymbolGlyph($r('sys.symbol.xmark'))
          .fontSize(18)
          .fontColor([AppTheme.current().hint])
          .onClick(() => {
            this.p.onResult(undefined);
          })
      }
      .width('100%')

      TextInput({ text: this.name })
        .fontSize(14)
        .fontColor(AppTheme.current().onSurface)
        .placeholderFont({ size: 14 })
        .placeholderColor(AppTheme.current().hint)
        .backgroundColor(AppTheme.withAlpha(AppTheme.current().onSurface, 0.05))
        .borderRadius(8)
        .border({ width: 1, color: AppTheme.current().inputBorder })
        .height(42)
        .margin({ top: 16 })
        .width('100%')
        .onChange((v: string): void => {
          this.name = v;
          this.recomputeCanSubmit();
        })

      // 逻辑关系 + 添加条件
      Row({ space: 10 }) {
        Select(this.logicOptions()) {
          Text(this.logicText())
        }
        .selected(this.logic === 'or' ? 1 : 0)
        .value(this.logicText())
        .font({ size: 14 })
        .fontColor(AppTheme.current().onSurface)
        .backgroundColor(AppTheme.withAlpha(AppTheme.current().onSurface, 0.05))
        .onSelect((index: number): void => {
          this.logic = index === 1 ? 'or' : 'and';
          this.recomputeCanSubmit();
        })
        .layoutWeight(1)

        Button() {
          Row({ space: 6 }) {
            SymbolGlyph($r('sys.symbol.plus'))
              .fontSize(16)
              .fontColor([AppTheme.current().buttonText])
            Text(L10n.t('smart_album_add_condition', '添加条件'))
              .fontSize(14)
              .fontColor(AppTheme.current().buttonText)
          }
        }
        .backgroundColor(AppTheme.current().buttonBg)
        .height(40)
        .onClick(() => {
          this.addCondition();
        })
      }
      .alignItems(VerticalAlign.Center)
      .margin({ top: 12 })
      .width('100%')

      // 条件列表（最高 320，可滚动，对齐 Flutter ConstrainedBox）
      Scroll() {
        Column() {
          ForEach(this.conds, (item: SmartConditionItem, idx: number) => {
            Column() {
              this.ConditionRow(item, idx)
            }
            .margin({ top: idx > 0 ? 10 : 0 })
          }, (item: SmartConditionItem, idx: number): string =>
            `${this.structTick}_${idx}_${item.field}_${item.operator}`)
        }
        .width('100%')
      }
      .constraintSize({ maxHeight: 320 })
      .scrollBar(BarState.Auto)
      .align(Alignment.Top)
      .margin({ top: 12 })
      .width('100%')

      // 操作按钮
      Row({ space: 8 }) {
        Button(L10n.t('cancel', '取消'))
          .fontSize(14)
          .fontColor(AppTheme.current().primary)
          .backgroundColor(Color.Transparent)
          .height(36)
          .onClick(() => {
            this.p.onResult(undefined);
          })
        Button(this.p.confirmText.length > 0 ? this.p.confirmText : L10n.t('create', '创建'))
          .fontSize(14)
          .fontColor(AppTheme.current().buttonText)
          .backgroundColor(this.canSubmit ? AppTheme.current().buttonBg
            : AppTheme.withAlpha(AppTheme.current().onSurface, 0.2))
          .opacity(this.canSubmit ? 1 : 0.6)
          .height(36)
          .onClick(() => {
            this.submit();
          })
      }
      .justifyContent(FlexAlign.End)
      .margin({ top: 16 })
      .width('100%')
    }
    .alignItems(HorizontalAlign.Start)
    .padding(20)
    .width('100%')
    .borderRadius(16)
    .backgroundColor(AppTheme.current().surfaceBg)
  }

  private logicOptions(): SelectOption[] {
    const out: SelectOption[] = [];
    out.push({ value: L10n.t('smart_album_condition_relation_and', '满足全部条件') } as SelectOption);
    out.push({ value: L10n.t('smart_album_condition_relation_or', '满足任一条件') } as SelectOption);
    return out;
  }

  private logicText(): string {
    return this.logic === 'or'
      ? L10n.t('smart_album_condition_relation_or', '满足任一条件')
      : L10n.t('smart_album_condition_relation_and', '满足全部条件');
  }
}

// ===== 页面本体 =====

class SmartAlbumActionSheetParams extends SheetParamsBase {
  onOpen: () => void = (): void => {
  };
  onEdit: () => void = (): void => {
  };
  onDelete: () => void = (): void => {
  };
}

@Builder
function SmartAlbumActionSheetContent(p: SmartAlbumActionSheetParams) {
  Column() {
    SheetHandle()
    SheetListItem({
      icon: $r('sys.symbol.plus_square_on_square'),
      title: L10n.t('open', '打开'),
      onSelect: (): void => {
        p.close();
        p.onOpen();
      }
    })
    SheetListItem({
      icon: $r('sys.symbol.square_and_pencil'),
      title: L10n.t('edit', '编辑'),
      onSelect: (): void => {
        p.close();
        p.onEdit();
      }
    })
    SheetListItem({
      icon: $r('sys.symbol.trash'),
      title: L10n.t('delete', '删除'),
      onSelect: (): void => {
        p.close();
        p.onDelete();
      }
    })
  }
  .width('100%')
  .padding({ bottom: 24 })
  .borderRadius({ topLeft: 16, topRight: 16 })
  .backgroundColor(AppTheme.current().surfaceBg)
}

@ComponentV2
export struct VideoSmartAlbumListPage {
  @Param param: VideoSmartAlbumListPageParam = new VideoSmartAlbumListPageParam();
  @Param popPage: () => void = (): void => {
  };
  ctrl: VideoSmartAlbumListController = new VideoSmartAlbumListController();
  @Local gridWidth: number = 0;
  @Local columns: number = 1;
  @Local itemHeight: number = 200;
  private didAutoEdit: boolean = false;
  private didAutoOpenCreate: boolean = false;

  aboutToAppear(): void {
    this.ctrl.init();
    if (this.param.autoOpenCreate && !this.didAutoOpenCreate) {
      this.didAutoOpenCreate = true;
      this.showCreateDialog();
    }
    this.tryAutoEdit(0);
  }

  /** 自适应列数与卡片高度（对齐 Flutter crossAxisCount + childAspectRatio） */
  private updateGridMetrics(): void {
    if (this.gridWidth <= 0) {
      return;
    }
    const count = this.gridWidth <= 750 ? 1
      : Math.min(Math.max(Math.floor(this.gridWidth / 240), 2), 6);
    this.columns = count;
    const gaps = 10 * (count - 1) + 24;
    const cardWidth = (this.gridWidth - gaps) / count;
    const ratio = count === 1 ? 2.3 : 1.25;
    this.itemHeight = cardWidth / ratio;
  }

  private openAlbumVideos(album: VideoSmartAlbumItem): void {
    const p = new VideoAlbumVideosPageParam();
    p.smartAlbumId = album.id;
    p.title = album.name;
    NavUtil.push(AppRouter.VIDEO_ALBUM_VIDEOS, p);
  }

  private openSearch(): void {
    DialogUtil.showInputDialog(L10n.t('search', '搜索'), '', this.ctrl.keyword)
      .then((r: DialogResult | undefined) => {
        if (typeof r === 'string') {
          this.ctrl.onSearchChanged(r.trim());
        }
      });
  }

  private showSortSheet(): void {
    const options: PickOption[] = [
      new PickOption('name_asc', L10n.t('name_asc', '名称升序')),
      new PickOption('name_desc', L10n.t('name_desc', '名称降序')),
      new PickOption('create_time_asc', L10n.t('create_time_asc', '创建时间升序')),
      new PickOption('create_time_desc', L10n.t('create_time_desc', '创建时间降序'))
    ];
    const selected = `${this.ctrl.sortField}_${this.ctrl.sortOrder}`;
    showOptionPickSheet(L10n.t('sort', '排序'), options, selected, (key: string): void => {
      const idx = key.lastIndexOf('_');
      if (idx <= 0) {
        return;
      }
      this.ctrl.setSort(key.substring(0, idx), key.substring(idx + 1));
    });
  }

  private showCreateDialog(): void {
    const p = new SmartAlbumEditDialogParams();
    p.title = L10n.t('video_smart_album_title', '智能相册');
    p.initialName = '';
    p.initialLogic = 'and';
    p.initialConditions = [newEmptyCondition()];
    p.confirmText = L10n.t('create', '创建');
    p.onConfirm = (name: string, filterContent: Record<string, Object>): void => {
      void this.ctrl.createSmartAlbum(name, filterContent);
    };
    DialogUtil.openCustom(p, wrapBuilder(SmartAlbumEditDialogContent));
  }

  private showEditDialog(album: VideoSmartAlbumItem): void {
    const p = new SmartAlbumEditDialogParams();
    p.title = L10n.t('edit', '编辑');
    p.initialName = album.name;
    p.initialLogic = parseConditionLogic(album.filterContent);
    p.initialConditions = parseConditionItems(album.filterContent);
    if (p.initialConditions.length === 0) {
      p.initialConditions = [newEmptyCondition()];
    }
    p.confirmText = L10n.t('save', '保存');
    p.onConfirm = (name: string, filterContent: Record<string, Object>): void => {
      void this.ctrl.updateSmartAlbum(album.id, name, filterContent);
    };
    DialogUtil.openCustom(p, wrapBuilder(SmartAlbumEditDialogContent));
  }

  private confirmDelete(album: VideoSmartAlbumItem): void {
    DialogUtil.showConfirmDialog(L10n.t('tip', '提示'),
      `${L10n.t('delete', '删除')} "${album.name}" ?`, (): void => {
        void this.ctrl.deleteSmartAlbum(album.id);
      });
  }

  private showActions(album: VideoSmartAlbumItem): void {
    const p = new SmartAlbumActionSheetParams();
    p.onOpen = (): void => {
      this.openAlbumVideos(album);
    };
    p.onEdit = (): void => {
      this.showEditDialog(album);
    };
    p.onDelete = (): void => {
      this.confirmDelete(album);
    };
    SheetUtil.present(p, wrapBuilder(SmartAlbumActionSheetContent));
  }

  /** 左上信息角标：展示筛选条件提示（对齐 Flutter onTopLeftTap） */
  private showConditionTip(album: VideoSmartAlbumItem): void {
    const tip = VideoSmartAlbumTooltipUtil.buildTooltip(album.filterContent);
    DialogUtil.showInfoDialog(album.name,
      tip.trim().length > 0 ? tip : L10n.t('no_data', '暂无数据'));
  }

  /** 轮询等待列表加载后自动打开编辑弹窗（最多 10 次） */
  private tryAutoEdit(retries: number): void {
    if (this.didAutoEdit || this.param.initialEditId <= 0) {
      return;
    }
    for (const album of this.ctrl.items) {
      if (album.id === this.param.initialEditId) {
        this.didAutoEdit = true;
        this.showEditDialog(album);
        return;
      }
    }
    if (retries < 10) {
      setTimeout((): void => {
        this.tryAutoEdit(retries + 1);
      }, 300);
    }
  }

  /** 底部加载区 */
  @Builder
  FooterView() {
    Row() {
      if (this.ctrl.isLoading) {
        LoadingProgress()
          .width(22)
          .height(22)
          .color(AppTheme.current().subText)
      } else if (!this.ctrl.hasMore) {
        Text(L10n.t('no_more', '没有更多了'))
          .fontSize(13)
          .fontColor(AppTheme.current().subText)
      } else {
        Button(L10n.t('load_more', '加载更多'))
          .fontSize(14)
          .fontColor(AppTheme.current().primary)
          .backgroundColor(Color.Transparent)
          .borderRadius(18)
          .border({ width: 1, color: AppTheme.withAlpha(AppTheme.current().onSurface, 0.25) })
          .onClick(() => {
            void this.ctrl.loadMore();
          })
      }
    }
    .justifyContent(FlexAlign.Center)
    .width('100%')
    .padding({ top: 4, bottom: 16 })
  }

  build() {
    PageScaffold({
      title: L10n.t('video_smart_album_title', '智能相册'),
      showBack: true,
      onBack: (): void => {
        this.popPage();
      },
      actions: (): void => {
        this.TitleActions()
      },
      content: (): void => {
        this.ListContent()
      }
    })
  }

  @Builder
  TitleActions() {
    Row({ space: 8 }) {
      BorderedIconButton({
        icon: $r('sys.symbol.magnifyingglass'),
        onTap: (): void => {
          this.openSearch();
        }
      })
      BorderedIconButton({
        icon: $r('sys.symbol.slider_horizontal_2'),
        onTap: (): void => {
          this.showSortSheet();
        }
      })
      BorderedIconButton({
        icon: $r('sys.symbol.plus'),
        onTap: (): void => {
          this.showCreateDialog();
        }
      })
    }
  }

  @Builder
  ListContent() {
    Column() {
      if (this.ctrl.isLoading && this.ctrl.items.length === 0) {
        Column() {
          LoadingProgress()
            .width(36)
            .height(36)
            .color(AppTheme.current().primary)
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
      } else if (this.ctrl.items.length === 0) {
        EmptyState({ message: L10n.t('no_data', '暂无数据') })
      } else {
        Scroll() {
          Column() {
            Grid() {
              ForEach(this.ctrl.items, (album: VideoSmartAlbumItem) => {
                GridItem() {
                  Column() {
                    VideoAlbumCard({
                      title: album.name,
                      titleIcon: $r('sys.symbol.funnel'),
                      showTopLeftIcon: true,
                      previews: album.previews,
                      onTopLeftTap: (): void => {
                        this.showConditionTip(album);
                      },
                      onTap: (): void => {
                        this.openAlbumVideos(album);
                      },
                      onMore: (): void => {
                        this.showActions(album);
                      }
                    })
                  }
                  .width('100%')
                  .height(this.itemHeight)
                }
              }, (album: VideoSmartAlbumItem): string => `${album.id}`)
            }
            .columnsTemplate(this.columns > 1 ? this.columnsTemplate() : '1fr')
            .columnsGap(10)
            .rowsGap(10)
            .width('100%')
            .height(this.calcGridHeight())
            .padding({ left: 12, right: 12, top: 12 })

            this.FooterView()
          }
          .width('100%')
        }
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
        .width('100%')
        .height('100%')
        .align(Alignment.Top)
      }
    }
    .width('100%')
    .height('100%')
    .onAreaChange((_o: Area, n: Area): void => {
      this.gridWidth = Number(n.width);
      this.updateGridMetrics();
    })
    .backgroundColor(AppTheme.current().cardBg)
  }

  /** 生成 columnsTemplate（如 '1fr 1fr 1fr'） */
  private columnsTemplate(): string {
    const parts: string[] = [];
    for (let i = 0; i < this.columns; i++) {
      parts.push('1fr');
    }
    return parts.join(' ');
  }

  /** 网格高度 = 行数 × 行高 + 行间距（对齐 SliverGrid 布局） */
  private calcGridHeight(): number {
    const rows = Math.ceil(this.ctrl.items.length / this.columns);
    return rows * this.itemHeight + Math.max(rows - 1, 0) * 10;
  }
}
