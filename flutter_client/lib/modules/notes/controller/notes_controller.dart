import 'dart:async';
import 'package:NasCabOS/core/api/api_controller.dart';
import 'package:NasCabOS/modules/base/components/custom_extended_image.dart';
import 'package:NasCabOS/core/api/base_api_service.dart';
import 'package:NasCabOS/core/user/current_user_controller.dart';
import 'package:NasCabOS/modules/files/views/folder_picker_dialog.dart';
import 'package:NasCabOS/modules/notes/model/notes_models.dart';
import 'package:NasCabOS/modules/notes/service/notes_api_service.dart';
import 'package:NasCabOS/modules/notes/view/parts/notes_network_image_provider.dart';
import 'package:NasCabOS/modules/notes/view/parts/notes_quill_image_embed.dart';
import 'package:NasCabOS/modules/notes/view/parts/notes_view_utils.dart';
import 'package:NasCabOS/modules/transfer/controllers/download_controller.dart';
import 'package:NasCabOS/utils/dialog_util.dart';
import 'package:NasCabOS/utils/toast_util.dart';
import 'package:dart_quill_delta/dart_quill_delta.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_quill_extensions/flutter_quill_extensions.dart';
import 'package:flutter_quill_to_pdf/flutter_quill_to_pdf.dart';
import 'package:get/get.dart';
import 'package:pdf/widgets.dart' as pw;

class NotesController extends GetxController {
  static NotesController get instance => Get.find<NotesController>();
  static const String allTagFilterValue = '__all__';
  static const String _defaultImageEmbedStyle = 'width: 300px;';
  static Future<List<pw.Font>>? _pdfFallbackFontsFuture;
  static final PDFPageFormat _pdfPageFormat = PDFPageFormat.a4;
  static final double _pdfImageMaxWidth =
      _pdfPageFormat.width -
      _pdfPageFormat.marginLeft -
      _pdfPageFormat.marginRight;
  static final double _pdfImageMaxHeight =
      _pdfPageFormat.height -
      _pdfPageFormat.marginTop -
      _pdfPageFormat.marginBottom;

  static const List<String> presetColors = <String>[
    '',
    '#EF4444',
    '#F59E0B',
    '#10B981',
    '#3B82F6',
    '#8B5CF6',
    '#EC4899',
  ];

  final NotesApiService _api = NotesApiService.instance;

  final RxBool loadingNotebook = false.obs;
  final RxBool loadingState = false.obs;
  final RxBool loadingNoteDetail = false.obs;
  final RxBool savingNote = false.obs;
  final RxBool notebookSelected = false.obs;

  final RxString selectedGroupId = 'all'.obs;
  final RxString selectedNoteId = ''.obs;
  final RxList<String> selectedNoteIds = <String>[].obs;
  final RxBool showingTrash = false.obs;
  final RxString keyword = ''.obs;
  final RxString tagColorFilter = allTagFilterValue.obs;
  final RxInt editorVersion = 0.obs;
  final RxString statusText = ''.obs;
  final RxBool showSaveFailureWarning = false.obs;
  final RxBool sidebarCollapsed = false.obs;

  final Rxn<NotesNotebookInfo> notebook = Rxn<NotesNotebookInfo>();
  final RxList<NotesGroup> groups = <NotesGroup>[].obs;
  final RxList<NotesNote> notes = <NotesNote>[].obs;
  final Rxn<NotesNote> currentNote = Rxn<NotesNote>();

  final TextEditingController searchController = TextEditingController();
  final TextEditingController titleController = TextEditingController();

  Timer? _searchDebounce;
  Timer? _saveDebounce;
  StreamSubscription? _docSub;
  bool _ignoreEditorEvents = false;
  String _lastSavedTitle = '';
  int _contentRevision = 0;
  Delta _pendingChangeDelta = Delta();
  bool _saveInFlight = false;
  Completer<void>? _saveCompleter;
  String _selectionAnchorNoteId = '';
  String _sessionKey = '';
  bool _sessionSyncInFlight = false;

  QuillController quillController = QuillController.basic();

  List<NotesNote> get visibleNotes {
    final filter = tagColorFilter.value;
    if (filter == allTagFilterValue) {
      return notes.toList(growable: false);
    }
    return notes
        .where((item) => item.tagColor == filter)
        .toList(growable: false);
  }

  int get selectedNoteCount => selectedNoteIds.length;

  bool get hasBatchSelection => selectedNoteCount > 1;

  bool isNoteSelected(String noteId) => selectedNoteIds.contains(noteId.trim());

  bool get isShiftSelectionActive {
    final keys = HardwareKeyboard.instance.logicalKeysPressed;
    return keys.contains(LogicalKeyboardKey.shiftLeft) ||
        keys.contains(LogicalKeyboardKey.shiftRight) ||
        keys.contains(LogicalKeyboardKey.shift);
  }

  void _setSelectedNoteIds(Iterable<String> ids, {String? anchorId}) {
    final next = <String>[];
    final seen = <String>{};
    for (final rawId in ids) {
      final id = rawId.trim();
      if (id.isEmpty || !seen.add(id)) continue;
      next.add(id);
    }
    selectedNoteIds.assignAll(next);
    if (anchorId != null) {
      _selectionAnchorNoteId = anchorId.trim();
    }
  }

  void clearNoteSelection({bool keepActive = true}) {
    final activeId = selectedNoteId.value.trim().isNotEmpty
        ? selectedNoteId.value.trim()
        : currentNote.value?.id ?? '';
    if (keepActive && activeId.isNotEmpty) {
      _setSelectedNoteIds([activeId], anchorId: activeId);
      return;
    }
    selectedNoteIds.clear();
    _selectionAnchorNoteId = '';
  }

  @override
  void onInit() {
    super.onInit();
    searchController.addListener(_handleSearchChanged);
    titleController.addListener(_handleEditorChanged);
    _bindEditorController(QuillController.basic());
    unawaited(ensureSessionFresh());
  }

  @override
  void onClose() {
    _searchDebounce?.cancel();
    _saveDebounce?.cancel();
    _docSub?.cancel();
    searchController.dispose();
    titleController.dispose();
    quillController.dispose();
    super.onClose();
  }

  void _bindEditorController(QuillController next) {
    _docSub?.cancel();
    quillController.dispose();
    quillController = next;
    _docSub = quillController.document.changes.listen((event) {
      final dynamic change = event;
      final dynamic delta = change.change;
      if (!_ignoreEditorEvents && delta is Delta && delta.isNotEmpty) {
        _pendingChangeDelta = _pendingChangeDelta.compose(delta);
      }
      _handleEditorChanged();
    });
    editorVersion.value += 1;
  }

  void _handleSearchChanged() {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 260), () {
      keyword.value = searchController.text.trim();
      refreshState();
    });
  }

  void _handleEditorChanged() {
    if (_ignoreEditorEvents) return;
    if (currentNote.value == null || currentNote.value!.isDeleted) return;
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 800), () async {
      await saveCurrentNote();
    });
  }

  bool get _hasPendingSave {
    final note = currentNote.value;
    if (note == null || note.isDeleted) return false;
    return _pendingChangeDelta.isNotEmpty ||
        titleController.text.trim() != _lastSavedTitle;
  }

  void _resetPendingSaveState({String title = '', int revision = 0}) {
    _saveDebounce?.cancel();
    _lastSavedTitle = title;
    _contentRevision = revision;
    _pendingChangeDelta = Delta();
    showSaveFailureWarning.value = false;
  }

  bool get canRetrySave {
    final note = currentNote.value;
    return note != null && !note.isDeleted && !savingNote.value;
  }

  Future<void> retryFailedSave() async {
    await saveCurrentNote(force: true);
  }

  Future<void> _waitForSaveCycle() {
    final completer = _saveCompleter;
    if (completer == null) return Future<void>.value();
    return completer.future;
  }

  Future<void> _flushPendingNoteSaves() async {
    if (_saveInFlight) {
      await _waitForSaveCycle();
    }
    if (_hasPendingSave) {
      await saveCurrentNote(force: true);
      if (_saveInFlight) {
        await _waitForSaveCycle();
      }
    }
  }

  String _buildSessionKey() {
    final serverId = ApiController.instance.state.serverId.trim();
    final currentUser = CurrentUserController.instance.current;
    final userId = currentUser?.id?.toString() ?? '';
    final username = (currentUser?.username ?? '').trim();
    return '$serverId::$userId::$username';
  }

  void _resetSessionState() {
    loadingNotebook.value = false;
    loadingState.value = false;
    loadingNoteDetail.value = false;
    savingNote.value = false;
    notebookSelected.value = false;
    notebook.value = null;
    groups.clear();
    notes.clear();
    currentNote.value = null;
    selectedGroupId.value = 'all';
    selectedNoteId.value = '';
    selectedNoteIds.clear();
    showingTrash.value = false;
    keyword.value = '';
    tagColorFilter.value = allTagFilterValue;
    statusText.value = '';
    _selectionAnchorNoteId = '';
    searchController.clear();
    _resetEditor();
  }

  Future<void> ensureSessionFresh() async {
    if (_sessionSyncInFlight) return;
    final currentUser = CurrentUserController.instance.current;
    final token = (ApiController.instance.accessToken ?? '').trim();
    final nextSessionKey = currentUser == null || token.isEmpty
        ? ''
        : _buildSessionKey();
    if (nextSessionKey == _sessionKey) return;
    _sessionSyncInFlight = true;
    try {
      _sessionKey = nextSessionKey;
      _resetSessionState();
      if (nextSessionKey.isEmpty) {
        return;
      }
      await loadNotebookStatus();
    } finally {
      _sessionSyncInFlight = false;
    }
  }

  Future<void> loadNotebookStatus() async {
    loadingNotebook.value = true;
    final res = await _api.getNotebookStatus();
    if (!res.success) {
      notebookSelected.value = false;
      notebook.value = null;
      loadingNotebook.value = false;
      return;
    }
    final info = NotesNotebookInfo.fromJson(res.data);
    notebook.value = info;
    notebookSelected.value = info.selected;
    loadingNotebook.value = false;
    if (info.selected) {
      await refreshState();
    }
  }

  Future<void> pickNotebook(BuildContext context) async {
    final picked = await showFolderPickerBottomSheet(
      context,
      multiSelect: false,
      allowFileSelect: false,
    );
    if (picked == null || picked.isEmpty) return;
    final folderPath = picked.first.trim();
    if (folderPath.isEmpty) return;
    final res = await _api.selectNotebook(folderPath);
    if (!res.success) {
      ToastUtil.show(res.message ?? 'notes_open_notebook_failed'.tr);
      return;
    }
    notebook.value = NotesNotebookInfo.fromJson(
      res.data?['notebook'] as Map<String, dynamic>?,
    );
    notebookSelected.value = notebook.value?.selected == true;
    selectedGroupId.value = 'all';
    showingTrash.value = false;
    await refreshState();
  }

  Future<void> refreshState({String? keepNoteId}) async {
    if (!notebookSelected.value) return;
    loadingState.value = true;
    final res = await _api.getState(
      groupId: selectedGroupId.value,
      keyword: keyword.value,
      includeDeleted: showingTrash.value,
    );
    loadingState.value = false;
    if (!res.success) {
      ToastUtil.show(res.message ?? 'notes_load_failed'.tr);
      return;
    }
    final data = res.data ?? const <String, dynamic>{};
    notebook.value = NotesNotebookInfo.fromJson(
      data['notebook'] as Map<String, dynamic>?,
    );
    groups.assignAll(
      ((data['groups'] as List?) ?? const [])
          .whereType<Map>()
          .map((item) => NotesGroup.fromJson(Map<String, dynamic>.from(item)))
          .toList(),
    );
    notes.assignAll(
      ((data['notes'] as List?) ?? const [])
          .whereType<Map>()
          .map((item) => NotesNote.fromJson(Map<String, dynamic>.from(item)))
          .toList(),
    );
    final availableIds = notes.map((item) => item.id).toSet();
    final retainedSelection = selectedNoteIds
        .where((id) => availableIds.contains(id))
        .toList(growable: false);
    selectedNoteIds.assignAll(retainedSelection);
    if (_selectionAnchorNoteId.isNotEmpty &&
        !availableIds.contains(_selectionAnchorNoteId)) {
      _selectionAnchorNoteId = retainedSelection.isNotEmpty
          ? retainedSelection.first
          : '';
    }
    final currentSelectedId = selectedNoteId.value.trim();
    final targetId =
        (keepNoteId ??
                (currentSelectedId.isNotEmpty
                    ? currentSelectedId
                    : currentNote.value?.id ?? ''))
            .trim();
    if (targetId.isNotEmpty) {
      final hit = notes.firstWhereOrNull((item) => item.id == targetId);
      if (hit != null) {
        selectedNoteId.value = hit.id;
        currentNote.value = hit;
      }
    }
    if (notes.isEmpty) {
      selectedNoteId.value = '';
      selectedNoteIds.clear();
      currentNote.value = null;
      _selectionAnchorNoteId = '';
      _resetEditor();
      return;
    }
    if (currentNote.value == null ||
        !notes.any((item) => item.id == currentNote.value!.id)) {
      selectedNoteId.value = notes.first.id;
      await selectNote(notes.first.id);
      return;
    }
    currentNote.value = notes.firstWhereOrNull(
      (item) => item.id == currentNote.value!.id,
    );
    selectedNoteId.value = currentNote.value?.id ?? '';
    if (selectedNoteIds.isEmpty && selectedNoteId.value.isNotEmpty) {
      _setSelectedNoteIds([
        selectedNoteId.value,
      ], anchorId: selectedNoteId.value);
    }
  }

  void _resetEditor() {
    _ignoreEditorEvents = true;
    titleController.text = '';
    _bindEditorController(QuillController.basic());
    _resetPendingSaveState();
    _ignoreEditorEvents = false;
  }

  void _applyGroupsPayload(dynamic rawGroups) {
    groups.assignAll(
      ((rawGroups as List?) ?? const [])
          .whereType<Map>()
          .map((item) => NotesGroup.fromJson(Map<String, dynamic>.from(item)))
          .toList(),
    );
  }

  void _sortLocalNotes() {
    final next = notes.toList(growable: true);
    next.sort(_compareLocalNotes);
    notes.assignAll(next);
  }

  int _compareLocalNotes(NotesNote a, NotesNote b) {
    final pinDelta = (b.isPinned ? 1 : 0) - (a.isPinned ? 1 : 0);
    if (pinDelta != 0) return pinDelta;
    return b.updateTime.compareTo(a.updateTime);
  }

  void _applyServerNoteDetail(
    Map<String, dynamic> data, {
    bool syncSelection = true,
    bool updateAnchor = true,
    TextSelection selection = const TextSelection.collapsed(offset: 0),
  }) {
    final note = NotesNote.fromJson(
      Map<String, dynamic>.from(data['note'] as Map? ?? const {}),
    );
    final rawDelta = ((data['delta'] as List?) ?? const <dynamic>[])
        .map((item) => item)
        .toList();
    final editorDelta = _expandEmbedsForEditor(note.id, rawDelta);
    _ignoreEditorEvents = true;
    selectedNoteId.value = note.id;
    currentNote.value = note;
    if (syncSelection) {
      _setSelectedNoteIds([note.id], anchorId: updateAnchor ? note.id : null);
    } else if (updateAnchor) {
      _selectionAnchorNoteId = note.id;
    }
    titleController.text = note.title;
    _bindEditorController(
      QuillController(
        document: Document.fromJson(editorDelta),
        selection: selection,
      ),
    );
    _resetPendingSaveState(
      title: note.title,
      revision: (data['revision'] as num?)?.toInt() ?? 0,
    );
    _ignoreEditorEvents = false;
    _replaceLocalNote(note);
  }

  Future<bool> _recoverFromSaveConflict({
    required String noteId,
    required String localTitle,
    required Delta localPatchDelta,
  }) async {
    final res = await _api.getNoteDetail(noteId);
    if (!res.success) {
      return false;
    }
    final selection = quillController.selection;
    final data = res.data ?? const <String, dynamic>{};
    _applyServerNoteDetail(
      data,
      syncSelection: false,
      updateAnchor: false,
      selection: selection,
    );
    if (localPatchDelta.isNotEmpty) {
      quillController.compose(
        Delta.from(localPatchDelta),
        selection,
        ChangeSource.local,
      );
    }
    final trimmedLocalTitle = localTitle.trim();
    if (trimmedLocalTitle != titleController.text.trim()) {
      titleController.text = trimmedLocalTitle;
    }
    return true;
  }

  Future<void> selectNote(
    String noteId, {
    bool syncSelection = true,
    bool updateAnchor = true,
  }) async {
    final trimmedId = noteId.trim();
    if (trimmedId.isEmpty) return;
    if (currentNote.value?.id != trimmedId) {
      await _flushPendingNoteSaves();
    }
    selectedNoteId.value = trimmedId;
    if (syncSelection) {
      _setSelectedNoteIds([
        trimmedId,
      ], anchorId: updateAnchor ? trimmedId : null);
    } else if (updateAnchor) {
      _selectionAnchorNoteId = trimmedId;
    }
    loadingNoteDetail.value = true;
    final res = await _api.getNoteDetail(trimmedId);
    loadingNoteDetail.value = false;
    if (!res.success) {
      ToastUtil.show(res.message ?? 'notes_load_failed'.tr);
      return;
    }
    _applyServerNoteDetail(
      res.data ?? const <String, dynamic>{},
      syncSelection: syncSelection,
      updateAnchor: updateAnchor,
    );
  }

  Future<void> handleNoteTap(
    NotesNote note, {
    required bool shiftPressed,
  }) async {
    if (!shiftPressed || visibleNotes.length <= 1) {
      await selectNote(note.id);
      return;
    }
    final notesInView = visibleNotes;
    var anchorId = _selectionAnchorNoteId.trim();
    if (anchorId.isEmpty || !notesInView.any((item) => item.id == anchorId)) {
      anchorId = selectedNoteId.value.trim();
    }
    if (anchorId.isEmpty || !notesInView.any((item) => item.id == anchorId)) {
      await selectNote(note.id);
      return;
    }
    final anchorIndex = notesInView.indexWhere((item) => item.id == anchorId);
    final targetIndex = notesInView.indexWhere((item) => item.id == note.id);
    if (anchorIndex < 0 || targetIndex < 0) {
      await selectNote(note.id);
      return;
    }
    final start = anchorIndex <= targetIndex ? anchorIndex : targetIndex;
    final end = anchorIndex <= targetIndex ? targetIndex : anchorIndex;
    final rangeIds = notesInView
        .sublist(start, end + 1)
        .map((item) => item.id)
        .toList(growable: false);
    await selectNote(note.id, syncSelection: false, updateAnchor: false);
    _setSelectedNoteIds(rangeIds, anchorId: anchorId);
  }

  List<dynamic> _expandEmbedsForEditor(String noteId, List<dynamic> rawOps) {
    return rawOps.map((item) {
      if (item is! Map) return item;
      final op = Map<String, dynamic>.from(item);
      final insert = op['insert'];
      if (insert is Map) {
        final nextInsert = Map<String, dynamic>.from(insert);
        for (final key in const ['image', 'video']) {
          final value = nextInsert[key];
          if (value is String) {
            nextInsert[key] = _api.expandEmbedForEditor(
              noteId: noteId,
              value: value,
            );
          }
        }
        op['insert'] = nextInsert;
      }
      return op;
    }).toList();
  }

  List<dynamic> _normalizeEmbedsForSave(String noteId, List<dynamic> rawOps) {
    return rawOps.map((item) {
      if (item is! Map) return item;
      final op = Map<String, dynamic>.from(item);
      final insert = op['insert'];
      if (insert is Map) {
        final nextInsert = Map<String, dynamic>.from(insert);
        for (final key in const ['image', 'video']) {
          final value = nextInsert[key];
          if (value is String) {
            nextInsert[key] = _api.normalizeEmbedForSave(
              noteId: noteId,
              value: value,
            );
          }
        }
        op['insert'] = nextInsert;
      }
      return op;
    }).toList();
  }

  Future<void> saveCurrentNote({bool force = false}) async {
    final note = currentNote.value;
    if (note == null || note.isDeleted) return;
    if (_saveInFlight) {
      await _waitForSaveCycle();
      return;
    }
    if (!_hasPendingSave) return;
    final titleToSave = titleController.text.trim();
    final titleChanged = titleToSave != _lastSavedTitle;
    final patchDelta = _pendingChangeDelta;
    final hasContentChanges = patchDelta.isNotEmpty;
    if (!force && !titleChanged && !hasContentChanges) return;
    final patchToSend = hasContentChanges
        ? _normalizeEmbedsForSave(note.id, patchDelta.toJson())
        : null;
    final revisionToSend = _contentRevision;
    _pendingChangeDelta = Delta();
    _saveInFlight = true;
    _saveCompleter = Completer<void>();
    savingNote.value = true;
    late final ApiResponse<Map<String, dynamic>> res;
    try {
      res = await _api.saveNote(
        noteId: note.id,
        title: titleToSave,
        baseRevision: revisionToSend,
        deltaPatch: patchToSend,
      );
    } finally {
      _saveInFlight = false;
      _saveCompleter?.complete();
      _saveCompleter = null;
      savingNote.value = false;
    }
    if (!res.success) {
      if (res.code == 409) {
        final recovered = await _recoverFromSaveConflict(
          noteId: note.id,
          localTitle: titleToSave,
          localPatchDelta: patchDelta,
        );
        if (recovered) {
          statusText.value = 'notes_save_conflict_retried'.tr;
          if (_hasPendingSave) {
            unawaited(saveCurrentNote(force: true));
          }
          return;
        }
      }
      if (hasContentChanges) {
        _pendingChangeDelta = patchDelta.compose(_pendingChangeDelta);
      }
      showSaveFailureWarning.value = true;
      statusText.value = res.message ?? 'notes_save_failed'.tr;
      return;
    }
    showSaveFailureWarning.value = false;
    statusText.value = 'notes_auto_saved'.tr;
    final noteMap = Map<String, dynamic>.from(
      res.data?['note'] as Map? ?? const {},
    );
    final updated = NotesNote.fromJson(noteMap);
    _lastSavedTitle = updated.title;
    _contentRevision =
        (res.data?['revision'] as num?)?.toInt() ?? _contentRevision;
    _replaceNoteInListOnly(updated);
    _sortLocalNotes();
    notebook.value = notebook.value;
    if (_hasPendingSave) {
      unawaited(saveCurrentNote());
    }
  }

  Future<void> createNote() async {
    if (showingTrash.value) {
      showingTrash.value = false;
    }
    final groupId = selectedGroupId.value.trim().isEmpty
        ? 'all'
        : selectedGroupId.value;
    final res = await _api.createNote(groupId: groupId, title: '');
    if (!res.success) {
      ToastUtil.show(res.message ?? 'notes_create_failed'.tr);
      return;
    }
    final noteMap = Map<String, dynamic>.from(
      res.data?['note'] as Map? ?? const {},
    );
    final note = NotesNote.fromJson(noteMap);
    selectedNoteId.value = note.id;
    currentNote.value = note;
    _applyGroupsPayload(res.data?['groups']);
    if (keyword.value.isNotEmpty || tagColorFilter.value != allTagFilterValue) {
      await refreshState(keepNoteId: note.id);
      await selectNote(note.id);
      return;
    }
    final currentNotebook = notebook.value;
    if (currentNotebook != null) {
      notebook.value = currentNotebook.copyWith(
        noteCount: currentNotebook.noteCount + 1,
      );
    }
    notes.removeWhere((item) => item.id == note.id);
    notes.insert(0, note);
    _sortLocalNotes();
    await selectNote(note.id);
  }

  Future<void> createGroup() async {
    final name = await DialogUtil.showInputDialog(
      title: 'notes_new_group'.tr,
      content: 'notes_group_name_input'.tr,
      confirmText: 'create'.tr,
      validator: (value) {
        final text = (value ?? '').trim();
        if (text.isEmpty) return 'notes_group_name_required'.tr;
        return null;
      },
    );
    if (name == null) return;
    final res = await _api.createGroup(name);
    if (!res.success) {
      ToastUtil.show(res.message ?? 'notes_group_create_failed'.tr);
      return;
    }
    await refreshState();
  }

  Future<void> renameGroup(NotesGroup group) async {
    final name = await DialogUtil.showInputDialog(
      title: 'notes_group_rename'.tr,
      content: 'notes_group_name_new_input'.tr,
      initialValue: displayNotesGroupName(
        groupId: group.id,
        groupName: group.name,
      ),
      confirmText: 'save'.tr,
      validator: (value) {
        final text = (value ?? '').trim();
        if (text.isEmpty) return 'notes_group_name_required'.tr;
        return null;
      },
    );
    if (name == null) return;
    final res = await _api.updateGroup(groupId: group.id, name: name);
    if (!res.success) {
      ToastUtil.show(res.message ?? 'notes_group_rename_failed'.tr);
      return;
    }
    await refreshState();
  }

  Future<void> deleteGroup(NotesGroup group) async {
    final groupName = displayNotesGroupName(
      groupId: group.id,
      groupName: group.name,
    );
    final ok = await DialogUtil.showConfirmDialog(
      title: 'notes_group_delete'.tr,
      content: 'notes_group_delete_confirm'.trParams({'name': groupName}),
      confirmText: 'delete'.tr,
      cancelText: 'cancel'.tr,
    );
    if (ok != true) return;
    final res = await _api.deleteGroup(group.id);
    if (!res.success) {
      ToastUtil.show(res.message ?? 'notes_group_delete_failed'.tr);
      return;
    }
    if (selectedGroupId.value == group.id) {
      selectedGroupId.value = 'all';
    }
    await refreshState();
  }

  Future<void> reorderGroups(List<NotesGroup> orderedCustomGroups) async {
    final ids = orderedCustomGroups.map((e) => e.id).toList();
    final res = await _api.reorderGroups(ids);
    if (!res.success) {
      ToastUtil.show(res.message ?? 'notes_group_reorder_failed'.tr);
      return;
    }
    await refreshState();
  }

  void toggleSidebarCollapsed() {
    sidebarCollapsed.value = !sidebarCollapsed.value;
  }

  Future<void> changeGroup(String groupId, {bool trash = false}) async {
    selectedGroupId.value = groupId;
    showingTrash.value = trash;
    selectedNoteId.value = '';
    currentNote.value = null;
    notes.clear();
    _resetEditor();
    await refreshState();
  }

  Future<void> togglePinned(NotesNote note) async {
    final current = _findLocalNote(note.id) ?? note;
    final res = await _api.updateNoteMeta(
      noteIds: [current.id],
      isPinned: !current.isPinned,
    );
    if (!res.success) {
      ToastUtil.show(res.message ?? 'operation_failed'.tr);
      return;
    }
    final updated = current.copyWith(isPinned: !current.isPinned);
    _replaceLocalNote(updated);
    _sortLocalNotes();
  }

  Future<void> setTagColor(NotesNote note, String color) async {
    final targets = _resolveMetaTargets(note);
    if (targets.isEmpty) return;
    final res = await _api.updateNoteMeta(
      noteIds: targets.map((item) => item.id).toList(growable: false),
      tagColor: color,
    );
    if (!res.success) {
      ToastUtil.show(res.message ?? 'notes_tag_update_failed'.tr);
      return;
    }
    _applyLocalNoteUpdates(
      targets.map((item) => item.copyWith(tagColor: color)),
    );
  }

  void setTagColorFilter(String color) {
    tagColorFilter.value = color;
  }

  void clearTagColorFilter() {
    tagColorFilter.value = allTagFilterValue;
  }

  Future<NotesGroup?> pickTargetGroup(
    BuildContext context, {
    String? excludedGroupId,
  }) async {
    final excluded = excludedGroupId?.trim() ?? '';
    final targets = groups
        .where((group) => excluded.isEmpty || group.id != excluded)
        .toList();
    if (targets.isEmpty) {
      ToastUtil.show('notes_no_group_to_move'.tr);
      return null;
    }
    return showDialog<NotesGroup>(
      context: context,
      builder: (dialogContext) {
        final scheme = Theme.of(dialogContext).colorScheme;
        return AlertDialog(
          title: Text('notes_group_select'.tr),
          content: SizedBox(
            width: 320,
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: targets.length,
              separatorBuilder: (_, _) => const SizedBox(height: 6),
              itemBuilder: (context, index) {
                final group = targets[index];
                return Material(
                  color: scheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(10),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () => Navigator.of(dialogContext).pop(group),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.folder_open_outlined,
                            size: 18,
                            color: scheme.primary,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              displayNotesGroupName(
                                groupId: group.id,
                                groupName: group.name,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(
                            '${group.noteCount}',
                            style: TextStyle(
                              fontSize: 12,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text('cancel'.tr),
            ),
          ],
        );
      },
    );
  }

  Future<void> moveNoteTo(String noteId, String targetGroupId) async {
    final ok = await _moveNoteOnce(noteId, targetGroupId);
    if (!ok) return;
    await refreshState(keepNoteId: noteId);
  }

  Future<bool> _moveNoteOnce(String noteId, String targetGroupId) async {
    final res = await _api.moveNote(
      noteId: noteId,
      targetGroupId: targetGroupId,
    );
    if (!res.success) {
      ToastUtil.show(res.message ?? 'notes_move_failed'.tr);
      return false;
    }
    return true;
  }

  Future<void> deleteCurrentNote() async {
    final note = currentNote.value;
    if (note == null) return;
    final ok = await DialogUtil.showConfirmDialog(
      title: 'notes_note_delete'.tr,
      content: 'notes_note_delete_confirm'.trParams({
        'title': displayNotesTitle(note.title),
      }),
      confirmText: 'delete'.tr,
      cancelText: 'cancel'.tr,
    );
    if (ok != true) return;
    final deleted = await _deleteNoteOnce(note.id);
    if (!deleted) return;
    await refreshState();
  }

  Future<bool> _deleteNoteOnce(String noteId) async {
    final res = await _api.deleteNote(noteId);
    if (!res.success) {
      ToastUtil.show(res.message ?? 'delete_failed'.tr);
      return false;
    }
    return true;
  }

  Future<void> restoreNote(NotesNote note) async {
    final res = await _api.restoreNote(note.id);
    if (!res.success) {
      ToastUtil.show(res.message ?? 'notes_restore_failed'.tr);
      return;
    }
    await refreshState();
  }

  Future<void> exportNote(NotesNote note, String format) async {
    final noteId = note.id.trim();
    final normalizedFormat = format.trim().toLowerCase();
    if (noteId.isEmpty || normalizedFormat.isEmpty) return;
    if (!note.isDeleted && currentNote.value?.id == noteId) {
      await saveCurrentNote(force: true);
    }
    if (normalizedFormat == 'pdf') {
      await _exportNoteAsPdf(note);
      return;
    }
    if (!Get.isRegistered<DownloadController>()) {
      Get.put(DownloadController(), permanent: true);
    }
    final url = _api.buildExportUrl(noteId: noteId, format: normalizedFormat);
    await Get.find<DownloadController>().handleDownload([url]);
    final label = switch (normalizedFormat) {
      'pdf' => 'PDF',
      'markdown' => 'Markdown',
      'txt' => 'TXT',
      _ => normalizedFormat.toUpperCase(),
    };
    ToastUtil.show('notes_export_started'.trParams({'format': label}));
  }

  Future<void> _exportNoteAsPdf(NotesNote note) async {
    var loadingShown = false;
    try {
      DialogUtil.showLoading(message: 'notes_export_pdf_loading'.tr);
      loadingShown = true;
      await WidgetsBinding.instance.endOfFrame;
      final document = _normalizeDocumentForPdfExport(
        await _buildPdfSourceDocument(note),
      );
      final fallbackFonts = await _loadPdfFallbackFonts();
      final converter = PDFConverter(
        document: document.toDelta(),
        pageFormat: _pdfPageFormat,
        textDirection: Get.context != null
            ? Directionality.of(Get.context!)
            : TextDirection.ltr,
        // Force `flutter_quill_to_pdf` to resolve note asset URLs through our
        // callback on desktop too. Its non-web branch only recognizes URLs
        // ending with image extensions, while note assets are API endpoints.
        isWeb: true,
        documentOptions: DocumentOptions(title: note.title.trim()),
        fallbacks: fallbackFonts,
        imageConstraints: pw.BoxConstraints(
          maxWidth: _pdfImageMaxWidth,
          maxHeight: _pdfImageMaxHeight,
        ),
        onDetectImageUrl: _loadPdfImageBytes,
      );
      final pdf = await converter.createDocument();
      if (pdf == null) {
        ToastUtil.show('notes_export_failed'.tr);
        return;
      }
      final bytes = await pdf.save();
      final fileName = _buildExportFileName(note, 'pdf');
      if (loadingShown) {
        DialogUtil.dismissLoading();
        loadingShown = false;
      }
      final savedPath = await FilePicker.platform.saveFile(
        dialogTitle: 'notes_export_pdf'.tr,
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: const <String>['pdf'],
        bytes: bytes,
      );
      if (savedPath != null || GetPlatform.isWeb) {
        ToastUtil.show('operation_success'.tr);
      }
    } catch (error) {
      ToastUtil.show('notes_export_failed'.tr);
      print('exportNotePdf failed: $error');
    } finally {
      if (loadingShown) {
        DialogUtil.dismissLoading();
      }
    }
  }

  Future<Document> _buildPdfSourceDocument(NotesNote note) async {
    if (!note.isDeleted && currentNote.value?.id == note.id) {
      return quillController.document;
    }
    final res = await _api.getNoteDetail(note.id);
    if (!res.success) {
      throw Exception(res.message ?? 'notes_load_failed'.tr);
    }
    final rawDelta = ((res.data?['delta'] as List?) ?? const <dynamic>[])
        .map((item) => item)
        .toList();
    final editorDelta = _expandEmbedsForEditor(note.id, rawDelta);
    return Document.fromJson(editorDelta);
  }

  Document _normalizeDocumentForPdfExport(Document source) {
    final normalizedOps = source.toDelta().toJson().map((item) {
      final op = Map<String, dynamic>.from(item);
      final insert = op['insert'];
      if (insert is! Map || insert['image'] is! String) {
        return op;
      }
      final attrs = op['attributes'] is Map
          ? Map<String, dynamic>.from(op['attributes'] as Map)
          : <String, dynamic>{};
      final normalizedStyle = _normalizePdfImageStyle(
        attrs['style']?.toString() ?? '',
      );
      if (normalizedStyle.isNotEmpty) {
        attrs['style'] = normalizedStyle;
        op['attributes'] = attrs;
      }
      return op;
    }).toList();
    return Document.fromJson(normalizedOps);
  }

  String _normalizePdfImageStyle(String style) {
    final width = _extractCssNumber(style, 'width');
    final height = _extractCssNumber(style, 'height');
    final margin = _extractCssNumber(style, 'margin');

    final parts = <String>[];
    if (width != null) {
      parts.add('width: ${_formatPdfCssNumber(_clampPdfValue(width, _pdfImageMaxWidth))}');
    }
    if (height != null) {
      parts.add(
        'height: ${_formatPdfCssNumber(_clampPdfValue(height, _pdfImageMaxHeight))}',
      );
    }
    if (margin != null) {
      parts.add('margin: ${_formatPdfCssNumber(_clampPdfValue(margin, 48))}');
    }
    return parts.join('; ');
  }

  double? _extractCssNumber(String style, String key) {
    if (style.trim().isEmpty) return null;
    final match = RegExp(
      '$key\\s*:\\s*([0-9]+(?:\\.[0-9]+)?)\\s*(?:px)?',
      caseSensitive: false,
    ).firstMatch(style);
    final raw = match?.group(1);
    if (raw == null || raw.isEmpty) return null;
    return double.tryParse(raw);
  }

  double _clampPdfValue(double value, double max) {
    if (value < 1) return 1;
    if (value > max) return max;
    return value;
  }

  String _formatPdfCssNumber(double value) {
    final rounded = value.roundToDouble();
    if ((value - rounded).abs() < 0.01) {
      return rounded.toInt().toString();
    }
    return value.toStringAsFixed(2);
  }

  Future<Uint8List?> _loadPdfImageBytes(String url) async {
    try {
      return await CustomExtendedImage.getOrCreateLoadFuture(url);
    } catch (error) {
      print('exportNotePdf image load failed: $url, error: $error');
      return null;
    }
  }

  Future<List<pw.Font>> _loadPdfFallbackFonts() {
    return _pdfFallbackFontsFuture ??= _createPdfFallbackFonts();
  }

  Future<List<pw.Font>> _createPdfFallbackFonts() async {
    final fonts = <pw.Font>[];
    Future<void> tryLoad(String assetPath) async {
      try {
        final data = await rootBundle.load(assetPath);
        fonts.add(pw.Font.ttf(data));
      } catch (_) {}
    }

    // `subfont.ttf` is bundled with the app and contains CJK glyphs used by the UI.
    await tryLoad('assets/subfont.ttf');
    await tryLoad('assets/fonts/RobotoMono-Regular.ttf');
    return fonts;
  }

  String _buildExportFileName(NotesNote note, String ext) {
    var base = note.title.trim();
    base = base.replaceAll(RegExp(r'[\u0000-\u001F]'), '_');
    base = base.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
    base = base.replaceAll(RegExp(r'\s+'), ' ').trim();
    base = base.replaceAll(RegExp(r'[. ]+$'), '');
    if (base.isEmpty) {
      final suffix = note.id.length >= 8 ? note.id.substring(0, 8) : note.id;
      base = suffix.isEmpty ? 'note' : 'note_$suffix';
    }
    return '$base.$ext';
  }

  Future<void> restoreSelectedNotes() async {
    final pickedIds = selectedNoteIds.toList(growable: false);
    if (pickedIds.length <= 1) return;
    final selected = visibleNotes
        .where((note) => pickedIds.contains(note.id))
        .toList();
    if (selected.length <= 1) return;
    loadingState.value = true;
    final res = await _api.batchRestoreNotes(
      selected.map((note) => note.id).toList(growable: false),
    );
    loadingState.value = false;
    if (!res.success) {
      ToastUtil.show(res.message ?? 'notes_restore_failed'.tr);
      return;
    }
    clearNoteSelection(keepActive: false);
    await refreshState();
  }

  Future<void> permanentlyDeleteNote(NotesNote note) async {
    final ok = await DialogUtil.showConfirmDialog(
      title: 'notes_delete_forever'.tr,
      content: 'notes_delete_forever_confirm'.tr,
      confirmText: 'delete'.tr,
      cancelText: 'cancel'.tr,
    );
    if (ok != true) return;
    final deleted = await _permanentlyDeleteNoteOnce(note.id);
    if (!deleted) return;
    await refreshState();
  }

  Future<bool> _permanentlyDeleteNoteOnce(String noteId) async {
    final res = await _api.permanentlyDeleteNote(noteId);
    if (!res.success) {
      ToastUtil.show(res.message ?? 'delete_failed'.tr);
      return false;
    }
    return true;
  }

  Future<void> moveSelectedNotes(BuildContext context) async {
    final pickedIds = selectedNoteIds.toList(growable: false);
    if (pickedIds.length <= 1) return;
    final selected = visibleNotes
        .where((note) => pickedIds.contains(note.id))
        .toList();
    if (selected.length <= 1) return;
    await _flushPendingNoteSaves();
    if (!context.mounted) return;
    final uniqueGroupIds = selected.map((note) => note.groupId).toSet();
    final target = await pickTargetGroup(
      context,
      excludedGroupId: uniqueGroupIds.length == 1 ? uniqueGroupIds.first : null,
    );
    if (target == null) return;
    final keepNoteId = selectedNoteId.value.trim();
    final movableIds = selected
        .where((note) => note.groupId != target.id)
        .map((note) => note.id)
        .toList(growable: false);
    if (movableIds.isEmpty) {
      clearNoteSelection();
      return;
    }
    loadingState.value = true;
    final res = await _api.batchMoveNotes(
      noteIds: movableIds,
      targetGroupId: target.id,
    );
    loadingState.value = false;
    if (!res.success) {
      ToastUtil.show(res.message ?? 'notes_move_failed'.tr);
      return;
    }
    clearNoteSelection(keepActive: false);
    await refreshState(keepNoteId: keepNoteId);
  }

  Future<void> deleteSelectedNotes() async {
    final pickedIds = selectedNoteIds.toList(growable: false);
    if (pickedIds.length <= 1) return;
    await _flushPendingNoteSaves();
    final selected = visibleNotes
        .where((note) => pickedIds.contains(note.id))
        .toList();
    if (selected.length <= 1) return;
    final title = showingTrash.value
        ? 'notes_delete_forever'.tr
        : 'notes_note_delete'.tr;
    final content = showingTrash.value
        ? '${'notes_delete_forever_confirm'.tr}\n${'items_selected'.trParams({'count': '${selected.length}'})}'
        : 'book_delete_confirm_count'.trParams({'count': '${selected.length}'});
    final ok = await DialogUtil.showConfirmDialog(
      title: title,
      content: content,
      confirmText: 'delete'.tr,
      cancelText: 'cancel'.tr,
    );
    if (ok != true) return;
    final keepNoteId = selectedNoteId.value.trim();
    loadingState.value = true;
    final res = showingTrash.value
        ? await _api.batchPermanentlyDeleteNotes(
            selected.map((note) => note.id).toList(growable: false),
          )
        : await _api.batchDeleteNotes(
            selected.map((note) => note.id).toList(growable: false),
          );
    loadingState.value = false;
    if (!res.success) {
      ToastUtil.show(res.message ?? 'delete_failed'.tr);
      return;
    }
    clearNoteSelection(keepActive: false);
    await refreshState(keepNoteId: keepNoteId);
  }

  Future<void> insertImageFromPicker() async {
    final file = await FilePicker.platform.pickFiles(type: FileType.image);
    final picked = file?.files.single;
    if (picked == null || currentNote.value == null) return;
    if ((picked.bytes == null || picked.bytes!.isEmpty) &&
        (picked.path == null || picked.path!.trim().isEmpty)) {
      return;
    }
    await _insertEmbedAsset(picked);
  }

  Future<void> _insertEmbedAsset(PlatformFile localFile) async {
    final note = currentNote.value;
    if (note == null) return;
    try {
      final url = await _api.uploadAsset(noteId: note.id, file: localFile);
      final selection = quillController.selection;
      final index = selection.baseOffset >= 0 ? selection.baseOffset : 0;
      final length = selection.extentOffset - selection.baseOffset;
      quillController
        ..skipRequestKeyboard = true
        ..replaceText(
          index,
          length < 0 ? 0 : length,
          BlockEmbed.image(url),
          null,
        )
        ..formatText(
          index,
          1,
          Attribute.fromKeyValue('style', _defaultImageEmbedStyle),
        )
        ..moveCursorToPosition(index + 1);
      await saveCurrentNote(force: true);
      await refreshState(keepNoteId: note.id);
    } catch (e) {
      final text = e.toString().replaceFirst('Exception: ', '').trim();
      ToastUtil.show(text.isEmpty ? 'upload_failed'.tr : text);
    }
  }

  void _replaceLocalNote(NotesNote updated) {
    final idx = notes.indexWhere((item) => item.id == updated.id);
    if (idx >= 0) {
      notes[idx] = updated;
      notes.refresh();
    }
    if (currentNote.value?.id == updated.id) {
      currentNote.value = updated;
    }
    if (selectedNoteId.value == updated.id || selectedNoteId.value.isEmpty) {
      selectedNoteId.value = updated.id;
    }
  }

  void _applyLocalNoteUpdates(
    Iterable<NotesNote> updatedNotes, {
    bool sortAfter = false,
  }) {
    final updateMap = <String, NotesNote>{};
    for (final note in updatedNotes) {
      updateMap[note.id] = note;
    }
    if (updateMap.isEmpty) return;
    final next = notes
        .map((item) => updateMap[item.id] ?? item)
        .toList(growable: true);
    if (sortAfter) {
      next.sort(_compareLocalNotes);
    }
    notes.assignAll(next);
    final current = currentNote.value;
    if (current != null && updateMap.containsKey(current.id)) {
      currentNote.value = updateMap[current.id];
    }
    if (selectedNoteId.value.isEmpty) {
      selectedNoteId.value = updateMap.keys.first;
    }
  }

  void _replaceNoteInListOnly(NotesNote updated) {
    final idx = notes.indexWhere((item) => item.id == updated.id);
    if (idx >= 0) {
      notes[idx] = updated;
      notes.refresh();
    }
    if (selectedNoteId.value == updated.id || selectedNoteId.value.isEmpty) {
      selectedNoteId.value = updated.id;
    }
  }

  NotesNote? _findLocalNote(String noteId) {
    if (currentNote.value?.id == noteId) {
      return currentNote.value;
    }
    return notes.firstWhereOrNull((item) => item.id == noteId);
  }

  List<NotesNote> _resolveMetaTargets(NotesNote note) {
    final current = _findLocalNote(note.id) ?? note;
    if (!(hasBatchSelection && isNoteSelected(note.id))) {
      return [current];
    }
    final pickedIds = selectedNoteIds.toSet();
    final targets = visibleNotes
        .where((item) => pickedIds.contains(item.id))
        .map((item) => _findLocalNote(item.id) ?? item)
        .toList(growable: false);
    return targets.isEmpty ? [current] : targets;
  }

  QuillSimpleToolbarConfig buildToolbarConfig({
    required bool compact,
    required ThemeData theme,
  }) {
    final scheme = theme.colorScheme;
    return QuillSimpleToolbarConfig(
      multiRowsDisplay: false,
      color: scheme.surfaceContainerHighest,
      sectionDividerColor: scheme.outlineVariant,
      showDividers: true,
      showClipboardCopy: false,
      showClipboardCut: false,
      showClipboardPaste: false,
      showSearchButton: false,
      showCodeBlock: false,
      showQuote: false,
      showSubscript: false,
      showSuperscript: false,
      showDirection: false,
      showFontFamily: false,
      showBackgroundColorButton: false,
      showHeaderStyle: false,
      showListNumbers: false,
      showListBullets: false,
      showListCheck: false,
      showIndent: false,
      showLink: false,
      showRedo: false,
      showInlineCode: false,
      showClearFormat: true,
      showAlignmentButtons: false,
      showColorButton: true,
      showFontSize: true,
      showBoldButton: true,
      showItalicButton: true,
      showUnderLineButton: true,
      showStrikeThrough: true,
      iconTheme: QuillIconTheme(
        iconButtonUnselectedData: IconButtonData(
          color: scheme.onSurfaceVariant,
          hoverColor: scheme.surfaceContainerHigh,
        ),
        iconButtonSelectedData: IconButtonData(
          color: scheme.primary,
          style: IconButton.styleFrom(
            backgroundColor: scheme.primary.withValues(alpha: 0.14),
          ),
        ),
      ),
    );
  }

  QuillEditorConfig buildEditorConfig({required ThemeData theme}) {
    return QuillEditorConfig(
      placeholder: 'notes_editor_placeholder'.tr,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      customStyles: DefaultStyles(
        placeHolder: DefaultTextBlockStyle(
          TextStyle(
            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.58),
            fontSize: 16,
          ),
          const HorizontalSpacing(0, 0),
          const VerticalSpacing(0, 0),
          const VerticalSpacing(0, 0),
          null,
        ),
      ),
      embedBuilders: [
        NotesQuillImageEmbedBuilder(
          config: QuillEditorImageEmbedConfig(
            imageProviderBuilder: (context, imageUrl) {
              if (imageUrl.startsWith('http://') ||
                  imageUrl.startsWith('https://')) {
                return NotesNetworkImageProvider(imageUrl);
              }
              return null;
            },
          ),
        ),
        ...FlutterQuillEmbeds.editorBuilders(imageEmbedConfig: null),
      ],
    );
  }
}
