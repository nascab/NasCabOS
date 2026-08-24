import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../base/components/custom_bordered_icon_button.dart';
import '../../../base/components/custom_expandable_search_bar.dart';
import '../../controllers/app_file_controller.dart';
import 'app_file_sheets.dart';

class AppFileSearchBar extends StatelessWidget {
  const AppFileSearchBar({
    super.key,
    required this.ctrl,
    required this.controller,
  });

  final AppFileController ctrl;
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      _syncText();
      final hasQuery = ctrl.searchQuery.value.trim().isNotEmpty;
      final hasSearchState =
          hasQuery ||
          ctrl.searchScope.value != 'current' ||
          ctrl.filterType.value != 'all';

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: CustomExpandableSearchBar(
                  hintText: 'folder_search_placeholder'.tr,
                  controller: controller,
                  onChanged: ctrl.setSearchQuery,
                  onClear: () => ctrl.setSearchQuery(''),
                  defaultExpanded: true,
                ),
              ),
              const SizedBox(width: 8),
              _SearchOptionsButton(
                active: hasSearchState,
                loading: ctrl.globalSearchLoading.value,
                onTap: () => showAppFileSearchOptionsSheet(context, ctrl),
              ),
            ],
          ),
          if (hasSearchState) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _SearchInfoChip(
                  label: _scopeLabel(ctrl.searchScope.value),
                  loading:
                      ctrl.globalSearchLoading.value &&
                      ctrl.searchScope.value != 'current',
                  onTap: () => showAppFileSearchOptionsSheet(context, ctrl),
                ),
                _SearchInfoChip(
                  label: _filterLabel(ctrl.filterType.value),
                  onTap: () => showAppFileSearchOptionsSheet(context, ctrl),
                ),
              ],
            ),
          ],
        ],
      );
    });
  }

  void _syncText() {
    final desired = ctrl.searchQuery.value;
    if (controller.text == desired) return;
    controller.value = controller.value.copyWith(
      text: desired,
      selection: TextSelection.collapsed(offset: desired.length),
      composing: TextRange.empty,
    );
  }

  String _scopeLabel(String scope) {
    if (scope == 'subtree') return 'file_search_scope_current_dir_subtree'.tr;
    if (scope == 'global') return 'file_search_scope_global'.tr;
    return 'file_search_scope_current_dir'.tr;
  }

  String _filterLabel(String type) {
    switch (type) {
      case 'dir':
        return 'dir'.tr;
      case 'document':
        return 'folder_filter_document'.tr;
      case 'video':
        return 'folder_filter_video'.tr;
      case 'audio':
        return 'folder_filter_audio'.tr;
      case 'image':
        return 'folder_filter_image'.tr;
      case 'archive':
        return 'folder_filter_archive'.tr;
      case 'file':
        return 'file'.tr;
      case 'all':
      default:
        return 'all'.tr;
    }
  }
}

class _SearchOptionsButton extends StatelessWidget {
  const _SearchOptionsButton({
    required this.active,
    required this.loading,
    required this.onTap,
  });

  final bool active;
  final bool loading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (loading) {
      return Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: theme.colorScheme.primary.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: theme.colorScheme.primary),
        ),
        child: Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: theme.colorScheme.primary,
            ),
          ),
        ),
      );
    }

    return CustomBorderedIconButton(
      icon: Icons.tune_rounded,
      tooltip: '',
      onTap: onTap,
      backgroundColor: active
          ? theme.colorScheme.primary.withValues(alpha: 0.12)
          : null,
    );
  }
}

class _SearchInfoChip extends StatelessWidget {
  const _SearchInfoChip({
    required this.label,
    required this.onTap,
    this.loading = false,
  });

  final String label;
  final bool loading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: theme.dividerColor),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label, style: theme.textTheme.bodySmall),
              if (loading) ...[
                const SizedBox(width: 6),
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
