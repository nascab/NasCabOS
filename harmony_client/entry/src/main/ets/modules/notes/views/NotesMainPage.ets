import { window } from '@kit.ArkUI';
import { L10n } from '../../../core/localization/L10n';
import { AppTheme, ThemePalette } from '../../../core/theme/AppTheme';
import { ThemeManager } from '../../../core/theme/ThemeManager';
import { AppEventBus } from '../../../common/AppEventBus';
import { WindowStore } from '../../../common/WindowStore';
import { NavUtil } from '../../../common/NavUtil';
import { AppRouter } from '../../../router/AppRouter';
import { BorderedIconButton } from '../../../common/components/BorderedIconButton';
import { SearchInputBar } from '../../../common/components/SearchInputBar';
import { EmptyState } from '../../../common/components/EmptyState';
import { BottomTabBar, BottomTabItem } from '../../../common/components/BottomTabBar';
import {
  NotesController, displayNotesGroupName, displayNotesTitle, formatNotesTime,
  parseNotesHexColor, tagColorLabel
} from '../controllers/NotesController';
import {
  NotesGroup, NotesNote, NOTES_ALL_TAG_FILTER, NOTES_PRESET_COLORS
} from '../models/NotesModels';
import { NotesActionItem, showNotesActionSheet } from '../components/NotesActionSheet';
import { pickTargetFolderViaSheet } from '../../../files/views/FolderPickerSheet';
import { NotesFileUtils } from '../services/NotesFileUtils';
import { NotesMainPageParam } from '../router/NotesRoutes';

/**
 * 笔记主页（对齐 Flutter NotesMobileView）：底部 3 标签（笔记/最近删除/设置），
 * 顶栏 主页按钮 + 搜索框（设置页为标题）+ 标签筛选 + 新建笔记，笔记页顶栏下方分组 chips 行。
 */
@ComponentV2
export struct NotesMainPage {
  @Param param: NotesMainPageParam = new NotesMainPageParam();
  @Param popPage: () => void = (): void => {
  };
  @Local ctrl: NotesController = NotesController.getInstance();
  /** 底部标签：0 笔记 1 最近删除 2 设置 */
  @Local activeTab: number = 0;
  @Local searchText: string = '';
  /** 主题变化刷新计数（AppTheme.current() 非响应式，依赖它触发整页重渲染） */
  @Local themeTick: number = 0;
  /** 状态栏高度（vp）：全屏布局后顶栏用它避让 */
  @Local statusBarHeight: number = 0;
  /** 底部导航条高度（vp）：全屏布局后底部标签栏用它避让 */
  @Local navigationBarHeight: number = 0;
  /** 切到删除页前记忆的普通分组（对齐 _lastNormalGroupId） */
  private lastNormalGroupId: string = 'all';
  /** 避让布局重试定时器（纠正 push 转场对窗口布局写入的回滚） */
  private retryTimer: number = -1;
  private themeListener: (data: string) => void = (_data: string): void => {
    this.themeTick++;
    this.applyStatusBar();
  };

  aboutToAppear(): void {
    this.applyStatusBar();
    AppEventBus.on(ThemeManager.EVENT_THEME_CHANGED, this.themeListener);
    // 沉浸全屏布局（对齐影音/音乐主页）：页面自管安全区避让
    this.setFullScreen(true);
    this.fetchSafeAreas();
    void this.initSession();
  }

  aboutToDisappear(): void {
    AppEventBus.off(ThemeManager.EVENT_THEME_CHANGED, this.themeListener);
    this.clearRetryTimer();
    this.applyStatusBar();
  }

  /** 会话初始化（对齐 initState：若停在删除页则回到普通分组） */
  private async initSession(): Promise<void> {
    await this.ctrl.ensureSessionFresh();
    if (this.ctrl.showingTrash) {
      await this.ctrl.changeGroup('all');
    }
    this.lastNormalGroupId = this.ctrl.selectedGroupId;
  }

  /** 全屏布局开关（窗口主窗口同步单例，写顺序=调用顺序） */
  private setFullScreen(full: boolean): void {
    const w = WindowStore.getMainWindow();
    if (w !== undefined) {
      w.setWindowLayoutFullScreen(full);
    }
  }

  /** push 转场会回滚窗口布局写入（实测）：延迟重设纠正 */
  private scheduleFullScreenRetry(): void {
    this.clearRetryTimer();
    this.retryTimer = setTimeout((): void => {
      this.retryTimer = -1;
      this.setFullScreen(true);
    }, 120);
  }

  private clearRetryTimer(): void {
    if (this.retryTimer >= 0) {
      clearTimeout(this.retryTimer);
      this.retryTimer = -1;
    }
  }

  private fetchSafeAreas(): void {
    const w = WindowStore.getMainWindow();
    if (w === undefined) {
      return;
    }
    const top = w.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
    this.statusBarHeight = Math.min(Math.max(px2vp(top.topRect.height), 0), 140);
    const bottom = w.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);
    this.navigationBarHeight = Math.min(Math.max(px2vp(bottom.bottomRect.height), 0), 60);
  }

  private static setStatusBar(ctx: Context, contentColor: string, bgColor: string): void {
    try {
      window.getLastWindow(ctx).then((w: window.Window) => {
        w.setWindowSystemBarProperties({
          statusBarContentColor: contentColor,
          statusBarColor: bgColor
        });
      });
    } catch (_e) {
      // 状态栏设置失败不阻塞页面
    }
  }

  private applyStatusBar(): void {
    const p = AppTheme.current();
    NotesMainPage.setStatusBar(getContext(this), p.statusBarContent, p.surfaceBg);
  }

  // ===== 交互（对齐 _selectBottomTab / _selectGroup / _handleCreateNote / _handleOpenNote） =====

  private async selectBottomTab(next: number): Promise<void> {
    if (this.activeTab === next) {
      return;
    }
    this.activeTab = next;
    if (next === 0) {
      await this.ctrl.changeGroup(this.lastNormalGroupId);
      return;
    }
    if (next === 1) {
      if (!this.ctrl.showingTrash) {
        this.lastNormalGroupId = this.ctrl.selectedGroupId;
      }
      await this.ctrl.changeGroup('all', true);
    }
  }

  private async selectGroup(groupId: string): Promise<void> {
    this.lastNormalGroupId = groupId;
    await this.ctrl.changeGroup(groupId);
  }

  private async handleCreateNote(): Promise<void> {
    await this.ctrl.createNote();
    if (this.ctrl.currentNote === undefined) {
      return;
    }
    this.openCurrentNoteEditor();
  }

  private async handleOpenNote(note: NotesNote): Promise<void> {
    await this.ctrl.selectNote(note.id);
    if (this.ctrl.currentNote === undefined) {
      return;
    }
    this.openCurrentNoteEditor();
  }

  private openCurrentNoteEditor(): void {
    NavUtil.push(AppRouter.NOTES_EDITOR, new Object());
  }

  /** 笔记卡片菜单（对齐 _showNoteContextMenu） */
  private async showNoteMenu(note: NotesNote): Promise<void> {
    const items: NotesActionItem[] = [];
    if (!note.isDeleted) {
      items.push(new NotesActionItem('pin',
        L10n.t(note.isPinned ? 'notes_unpin' : 'notes_pin')));
      items.push(new NotesActionItem('tag_picker', L10n.t('notes_tag')));
      const canMove = this.ctrl.hasBatchSelection && this.ctrl.isNoteSelected(note.id)
        || this.ctrl.groups.some((g) => g.id !== note.groupId);
      if (canMove) {
        items.push(new NotesActionItem('move_picker', L10n.t('move')));
      }
      items.push(new NotesActionItem('export_pdf', L10n.t('notes_export_pdf')));
      items.push(new NotesActionItem('export_markdown', L10n.t('notes_export_markdown')));
      items.push(new NotesActionItem('export_txt', L10n.t('notes_export_txt')));
    } else {
      items.push(new NotesActionItem('restore', L10n.t('notes_restore')));
    }
    items.push(new NotesActionItem(note.isDeleted ? 'permanent_delete' : 'delete',
      note.isDeleted ? L10n.t('notes_delete_forever') : L10n.t('notes_move_to_trash'), true));
    const key = await showNotesActionSheet(displayNotesTitle(note.title), items);
    await this.handleNoteMenuAction(key, note);
  }

  private async handleNoteMenuAction(key: string, note: NotesNote): Promise<void> {
    if (key === 'pin') {
      await this.ctrl.togglePinned(note);
      return;
    }
    if (key === 'tag_picker') {
      await this.showTagColorPicker(note);
      return;
    }
    if (key === 'move_picker') {
      if (this.ctrl.hasBatchSelection && this.ctrl.isNoteSelected(note.id)) {
        await this.ctrl.moveSelectedNotes();
      } else {
        const target = await this.ctrl.pickTargetGroup(note.groupId);
        if (target.length > 0) {
          await this.ctrl.moveNoteTo(note.id, target);
        }
      }
      return;
    }
    if (key === 'export_pdf' || key === 'export_markdown' || key === 'export_txt') {
      await this.exportNoteAs(note, key === 'export_pdf' ? 'pdf'
        : (key === 'export_markdown' ? 'markdown' : 'txt'));
      return;
    }
    if (key === 'delete') {
      if (this.ctrl.hasBatchSelection && this.ctrl.isNoteSelected(note.id)) {
        await this.ctrl.deleteSelectedNotes();
      } else {
        this.ctrl.currentNote = note;
        await this.ctrl.deleteCurrentNote();
      }
      return;
    }
    if (key === 'restore') {
      if (this.ctrl.hasBatchSelection && this.ctrl.isNoteSelected(note.id)) {
        await this.ctrl.restoreSelectedNotes();
      } else {
        await this.ctrl.restoreNote(note);
      }
      return;
    }
    if (key === 'permanent_delete') {
      if (this.ctrl.hasBatchSelection && this.ctrl.isNoteSelected(note.id)) {
        await this.ctrl.deleteSelectedNotes();
      } else {
        await this.ctrl.permanentlyDeleteNote(note);
      }
      return;
    }
  }

  /** 标签颜色选择（对齐 _showTagColorMenu） */
  private async showTagColorPicker(note: NotesNote): Promise<void> {
    const items: NotesActionItem[] = NOTES_PRESET_COLORS.map((color: string): NotesActionItem => {
      const item = new NotesActionItem(color, tagColorLabel(color));
      item.color = parseNotesHexColor(color);
      return item;
    });
    const selected = await showNotesActionSheet(L10n.t('notes_tag'), items);
    if (selected.length > 0 || selected === '') {
      if (selected.length === 0) {
        return;
      }
    }
    await this.ctrl.setTagColor(note, selected);
  }

  /** 导出笔记（先强制保存当前笔记，再下载另存） */
  private async exportNoteAs(note: NotesNote, format: string): Promise<void> {
    const url = await this.ctrl.prepareExport(note, format);
    if (url.length === 0) {
      return;
    }
    await NotesFileUtils.exportNote(url, this.ctrl.buildExportFileName(note,
      NotesFileUtils.exportExt(format)));
  }

  /** 标签筛选弹层（对齐 _showTagFilterSheet） */
  private async showTagFilterSheet(): Promise<void> {
    const items: NotesActionItem[] = [];
    const allItem = new NotesActionItem(NOTES_ALL_TAG_FILTER, L10n.t('notes_filter_all_tags'),
      false, this.ctrl.tagColorFilter === NOTES_ALL_TAG_FILTER);
    items.push(allItem);
    NOTES_PRESET_COLORS.forEach((color: string): void => {
      const item = new NotesActionItem(color, tagColorLabel(color), false,
        this.ctrl.tagColorFilter === color);
      item.color = parseNotesHexColor(color);
      items.push(item);
    });
    const key = await showNotesActionSheet(L10n.t('notes_filter_tag'), items);
    if (key.length === 0) {
      return;
    }
    if (key === NOTES_ALL_TAG_FILTER) {
      this.ctrl.clearTagColorFilter();
    } else {
      this.ctrl.setTagColorFilter(key);
    }
  }

  // ===== 导航栏图标 =====

  private tabItems(): BottomTabItem[] {
    return [
      new BottomTabItem($r('sys.symbol.square_and_pencil'), L10n.t('app_note', '笔记')),
      new BottomTabItem($r('sys.symbol.trash'), L10n.t('notes_recent_deleted', '最近删除')),
      new BottomTabItem($r('sys.symbol.gearshape'), L10n.t('setting', '设置'))
    ];
  }

  private palette(): ThemePalette {
    return AppTheme.current();
  }

  build() {
    NavDestination() {
      Stack() {
        // 底部安全区背景层：与底部标签栏同底色
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(this.palette().surfaceBg)
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])

        Column() {
          this.Header()
          Column() {
            this.Body()
          }
          .width('100%')
          .layoutWeight(1)

          BottomTabBar({
            items: this.tabItems(),
            selectedIndex: this.activeTab,
            bottomInset: this.navigationBarHeight,
            onSelect: (index: number): void => {
              void this.selectBottomTab(index);
            }
          })
        }
        .width('100%')
        .height('100%')
        .backgroundColor(this.palette().pageBg)
        .opacity(this.themeTick >= 0 ? 1 : 1)
      }
      .width('100%')
      .height('100%')
    }
    .hideTitleBar(true)
    .onShown((): void => {
      this.setFullScreen(true);
      this.scheduleFullScreenRetry();
      this.fetchSafeAreas();
      this.applyStatusBar();
    })
    .onHidden((): void => {
      this.clearRetryTimer();
    })
    .onBackPressed((): boolean => {
      this.popPage();
      return true;
    })
  }

  /** 顶栏（对齐 _buildHeader）：主页按钮 + 搜索/标题 + 标签筛选 + 新建 */
  @Builder
  Header() {
    Column() {
      Row() {
        BorderedIconButton({
          icon: $r('sys.symbol.house'),
          onTap: (): void => {
            this.popPage();
          }
        })

        if (this.activeTab !== 2) {
          SearchInputBar({
            hintText: L10n.t('search', '搜索'),
            text: this.searchText,
            onChanged: (v: string): void => {
              this.searchText = v;
              this.ctrl.onSearchChanged(v);
            },
            onClear: (): void => {
              this.searchText = '';
              this.ctrl.onSearchChanged('');
            }
          })
            .layoutWeight(1)
            .margin({ left: 8, right: 8 })
        } else {
          Text(L10n.t('setting', '设置'))
            .fontSize(17)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.palette().onSurface)
            .maxLines(1)
            .layoutWeight(1)
            .margin({ left: 8 })
        }

        if (this.activeTab === 0 && this.ctrl.notebookSelected) {
          Row({ space: 8 }) {
            BorderedIconButton({
              icon: this.ctrl.tagColorFilter !== NOTES_ALL_TAG_FILTER
                ? $r('sys.symbol.paintbrush_fill') : $r('sys.symbol.paintbrush'),
              active: this.ctrl.tagColorFilter !== NOTES_ALL_TAG_FILTER,
              onTap: (): void => {
                void this.showTagFilterSheet();
              }
            })
            BorderedIconButton({
              icon: $r('sys.symbol.plus'),
              onTap: (): void => {
                void this.handleCreateNote();
              }
            })
          }
        }
      }
      .width('100%')
      .height(56)
      .padding({ left: 10, right: 10 })

      // 分组 chips 行（对齐 _buildNotesActionBar）
      if (this.activeTab === 0 && this.ctrl.notebookSelected) {
        this.GroupChipsBar()
      }
    }
    .width('100%')
    .padding({ top: this.statusBarHeight })
    .backgroundColor(this.palette().surfaceBg)
  }

  /** 分组 chips 行：全部 + 自定义分组 + 新建分组 */
  @Builder
  GroupChipsBar() {
    Scroll() {
      Row({ space: 8 }) {
        this.GroupChip(L10n.t('all', '全部'), 'all')
        ForEach(this.ctrl.groups.filter((g: NotesGroup): boolean => g.id !== 'all'),
          (group: NotesGroup) => {
            this.GroupChip(displayNotesGroupName(group.id, group.name), group.id)
          }, (group: NotesGroup): string => group.id)
        this.ActionChip(L10n.t('notes_new_group', '新建分组'), (): void => {
          void this.ctrl.createGroup();
        })
      }
      .padding({ left: 12, right: 12 })
    }
    .width('100%')
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .padding({ bottom: 12, top: 2 })
  }

  /** 分组 ChoiceChip（选中主色浅底） */
  @Builder
  GroupChip(title: string, groupId: string) {
    Text(title)
      .fontSize(13)
      .fontColor(!this.ctrl.showingTrash && this.ctrl.selectedGroupId === groupId
        ? this.palette().primary : this.palette().onSurface)
      .padding({ left: 14, right: 14, top: 6, bottom: 6 })
      .borderRadius(18)
      .border({
        width: 1,
        color: !this.ctrl.showingTrash && this.ctrl.selectedGroupId === groupId
          ? this.palette().primary : this.palette().divider
      })
      .backgroundColor(!this.ctrl.showingTrash && this.ctrl.selectedGroupId === groupId
        ? AppTheme.withAlpha(this.palette().primary, 0.12)
        : AppTheme.withAlpha(this.palette().onSurface, 0.05))
      .maxLines(1)
      .onClick((): void => {
        void this.selectGroup(groupId);
      })
  }

  /** 动作 chip（新建分组，对齐 ActionChip） */
  @Builder
  ActionChip(label: string, onTap: () => void) {
    Row({ space: 5 }) {
      SymbolGlyph($r('sys.symbol.plus'))
        .fontSize(14)
        .fontColor([this.palette().hint])
      Text(label)
        .fontSize(13)
        .fontColor(this.palette().onSurface)
        .maxLines(1)
    }
    .padding({ left: 12, right: 14, top: 6, bottom: 6 })
    .borderRadius(18)
    .border({ width: 1, color: this.palette().divider })
    .backgroundColor(AppTheme.withAlpha(this.palette().onSurface, 0.05))
    .onClick((): void => {
      onTap();
    })
  }

  /** 主体（对齐 _buildBody） */
  @Builder
  Body() {
    if (this.activeTab === 2) {
      this.SettingsBody()
    } else if (!this.ctrl.notebookSelected) {
      this.NotebookChooser()
    } else {
      this.NoteList()
    }
  }

  /** 笔记列表（对齐 NotesNoteList 无工具栏形态） */
  @Builder
  NoteList() {
    Stack() {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(AppTheme.withAlpha(this.palette().primary, 0.02) === '#00000000'
          ? this.palette().pageBg : this.palette().pageBg)

      Column() {
        if (this.ctrl.loadingState) {
          // 细加载条（对齐 LinearProgressIndicator）
          Row() {
            LoadingProgress()
              .width(18)
              .height(18)
              .color(this.palette().primary)
          }
          .width('100%')
          .height(24)
          .justifyContent(FlexAlign.Center)
        }

        if (this.ctrl.visibleNotes.length === 0) {
          Column() {
            EmptyState({
              message: this.ctrl.notes.length > 0 && this.ctrl.tagColorFilter !== NOTES_ALL_TAG_FILTER
                ? L10n.t('notes_filter_empty', '没有符合当前标记筛选的笔记')
                : (this.ctrl.showingTrash
                  ? L10n.t('notes_trash_empty', '回收站为空')
                  : L10n.t('notes_list_empty', '暂无笔记')),
              imagePath: $rawfile('icons/nodata_note.png')
            })
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else {
          List({ space: 6 }) {
            ForEach(this.ctrl.visibleNotes, (note: NotesNote, index: number) => {
              ListItem() {
                this.NoteCard(note)
              }
              .margin({ bottom: index === this.ctrl.visibleNotes.length - 1 ? 0 : 0 })
            }, (note: NotesNote) =>
              `${note.id}_${note.updateTime}_${note.isPinned}_${note.tagColor}_${note.title}`)
          }
          .width('100%')
          .height('100%')
          .padding({ left: 10, right: 10, top: 4, bottom: 12 })
          .scrollBar(BarState.Off)
          .edgeEffect(EdgeEffect.Spring)
        }
      }
      .width('100%')
      .height('100%')
    }
    .width('100%')
    .height('100%')
  }

  /** 笔记卡片（对齐 _item） */
  @Builder
  NoteCard(note: NotesNote) {
    Column() {
      // 行 1：标签色点 + 标题 + 置顶 + 更多
      Row() {
        if (parseNotesHexColor(note.tagColor).length > 0) {
          Circle({ width: 8, height: 8 })
            .fill(parseNotesHexColor(note.tagColor))
            .margin({ right: 6 })
        }
        Text(displayNotesTitle(note.title))
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.palette().onSurface)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)

        if (note.isPinned) {
          SymbolGlyph($r('sys.symbol.pin_fill'))
            .fontSize(14)
            .fontColor([this.palette().primary])
            .padding(4)
            .onClick((): void => {
              void this.ctrl.togglePinned(note);
            })
        }
        SymbolGlyph($r('sys.symbol.ellipsis_circle'))
          .fontSize(17)
          .fontColor([this.palette().hint])
          .margin({ left: 2 })
          .onClick((): void => {
            void this.showNoteMenu(note);
          })
      }
      .width('100%')

      // 行 2：更新时间
      Text(formatNotesTime(note.updateTime))
        .fontSize(11.5)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.palette().subText)
        .margin({ top: 4 })

      // 行 3：预览
      Text(note.preview.length > 0 ? note.preview : L10n.t('notes_editor_placeholder', '请输入正文'))
        .fontSize(12.5)
        .fontColor(AppTheme.withAlpha(this.palette().onSurface, 0.78))
        .lineHeight(17)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ top: 5 })

      // 行 4：所属分组
      Row({ space: 4 }) {
        SymbolGlyph($r('sys.symbol.folder'))
          .fontSize(12)
          .fontColor([this.palette().subText])
        Text(displayNotesGroupName(note.groupId, note.groupName))
          .fontSize(11.5)
          .fontColor(AppTheme.withAlpha(this.palette().subText, 0.92))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
      }
      .width('100%')
      .margin({ top: 5 })
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding({ left: 12, right: 8, top: 10, bottom: 10 })
    .borderRadius(10)
    .backgroundColor(this.palette().cardBg)
    .border({ width: 1, color: AppTheme.withAlpha(this.palette().divider, 0.16) })
    .onClick((): void => {
      void this.handleOpenNote(note);
    })
    .gesture(LongPressGesture({ repeat: false }).onAction((): void => {
      void this.showNoteMenu(note);
    }))
  }

  /** 笔记本选择卡片（对齐 NotesNotebookChooser） */
  @Builder
  NotebookChooser() {
    Column() {
      Column({ space: 0 }) {
        SymbolGlyph($r('sys.symbol.book'))
          .fontSize(56)
          .fontColor([this.palette().primary])
        Text(L10n.t('notes_notebook_choose_title', '选择或创建笔记本'))
          .fontSize(21)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.palette().onSurface)
          .margin({ top: 16 })
        Text(L10n.t('notes_notebook_choose_desc', '首次打开请选择一个空文件夹'))
          .fontSize(14)
          .fontColor(this.palette().subText)
          .textAlign(TextAlign.Center)
          .lineHeight(21)
          .margin({ top: 10 })
        Button(L10n.t('notes_choose_folder', '选择笔记本文件夹'), { type: ButtonType.Capsule })
          .width('100%')
          .height(44)
          .fontSize(14)
          .backgroundColor(this.palette().buttonBg)
          .fontColor(this.palette().buttonText)
          .margin({ top: 22 })
          .onClick((): void => {
            this.pickNotebookFolder();
          })
        if (this.ctrl.notebook !== undefined && this.ctrl.notebook.folderPath.trim().length > 0) {
          Text(`${L10n.t('notes_original_path_missing', '原笔记本路径已不存在：')}`
            + `${this.ctrl.notebook.folderPath}`)
            .fontSize(12)
            .fontColor(this.palette().subText)
            .textAlign(TextAlign.Center)
            .lineHeight(18)
            .margin({ top: 18 })
        }
      }
      .width('90%')
      .constraintSize({ maxWidth: 420 })
      .padding(28)
      .borderRadius(20)
      .backgroundColor(this.palette().cardBg)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .padding(16)
  }

  /** 打开笔记本文件夹选择（对齐 controller.pickNotebook） */
  private pickNotebookFolder(): void {
    pickTargetFolderViaSheet('', (paths: string[]): void => {
      void this.ctrl.pickNotebook(paths);
    });
  }

  /** 设置页（对齐 _buildSettingsBody） */
  @Builder
  SettingsBody() {
    Scroll() {
      Column() {
        // 笔记本信息卡
        Column() {
          Text(this.ctrl.notebook !== undefined && this.ctrl.notebook.name.trim().length > 0
            ? this.ctrl.notebook.name : L10n.t('app_note', '笔记'))
            .fontSize(17)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.palette().onSurface)
            .maxLines(1)
          Text(L10n.t('path', '路径'))
            .fontSize(12)
            .fontColor(this.palette().subText)
            .margin({ top: 10 })
          Text(this.ctrl.notebook !== undefined && this.ctrl.notebook.folderPath.trim().length > 0
            ? this.ctrl.notebook.folderPath
            : L10n.t('notes_notebook_choose_desc', '首次打开请选择一个空文件夹'))
            .fontSize(14)
            .fontColor(this.palette().onSurface)
            .lineHeight(20)
            .margin({ top: 6 })
          Row({ space: 8 }) {
            SymbolGlyph($r('sys.symbol.folder'))
              .fontSize(18)
              .fontColor([this.palette().buttonText])
            Text(L10n.t('notes_switch_notebook', '切换笔记本'))
              .fontSize(14)
              .fontColor(this.palette().buttonText)
          }
          .justifyContent(FlexAlign.Center)
          .width('100%')
          .height(44)
          .borderRadius(22)
          .backgroundColor(this.palette().buttonBg)
          .margin({ top: 16 })
          .onClick((): void => {
            this.pickNotebookFolder();
          })
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')
        .padding(16)
        .borderRadius(18)
        .backgroundColor(this.palette().surfaceBg)
        .border({ width: 1, color: AppTheme.withAlpha(this.palette().divider, 0.4) })

        // 统计卡
        if (this.ctrl.notebookSelected && this.ctrl.notebook !== undefined) {
          Row({ space: 12 }) {
            this.StatCard($r('sys.symbol.square_and_pencil'),
              `${this.ctrl.notebook.noteCount}`, L10n.t('app_note', '笔记'))
            this.StatCard($r('sys.symbol.trash'),
              `${this.ctrl.notebook.deletedCount}`, L10n.t('notes_recent_deleted', '最近删除'))
          }
          .width('100%')
          .padding(16)
          .borderRadius(18)
          .backgroundColor(AppTheme.withAlpha(this.palette().onSurface, 0.05))
          .margin({ top: 16 })
        }
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 16, bottom: 24 })
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
  }

  /** 统计小卡（对齐 _buildStatCard） */
  @Builder
  StatCard(icon: Resource, value: string, label: string) {
    Column() {
      SymbolGlyph(icon)
        .fontSize(22)
        .fontColor([this.palette().primary])
      Text(value)
        .fontSize(22)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.palette().onSurface)
        .margin({ top: 10 })
      Text(label)
        .fontSize(13)
        .fontColor(this.palette().subText)
        .maxLines(2)
        .margin({ top: 4 })
    }
    .alignItems(HorizontalAlign.Start)
    .layoutWeight(1)
    .padding(14)
    .borderRadius(14)
    .backgroundColor(this.palette().surfaceBg)
  }
}
