part of '../file_share_server_view.dart';

class _RootPathRowState {
  String path;
  bool write;
  bool update;
  bool delete;
  _RootPathRowState({
    required this.path,
    this.write = true,
    this.update = true,
    this.delete = true,
  });
}

class _RootPathRow extends StatelessWidget {
  final _RootPathRowState state;
  final VoidCallback onPickPath;
  final VoidCallback onRemove;
  final bool canRemove;
  final VoidCallback onChanged;

  const _RootPathRow({
    required this.state,
    required this.onPickPath,
    required this.onRemove,
    required this.canRemove,
    required this.onChanged,
  });

  Widget _permChip({
    required bool selected,
    required String label,
    required ValueChanged<bool>? onSelected,
  }) {
    return FilterChip(
      selected: selected,
      label: Text(label, style: const TextStyle(fontSize: 10)),
      visualDensity: VisualDensity.comfortable,
      padding: const EdgeInsets.all(4),
      labelPadding: const EdgeInsets.symmetric(horizontal: 2),
      onSelected: onSelected,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onSurface = theme.colorScheme.onSurface;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  state.path.isEmpty ? '-' : state.path,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(color: onSurface),
                ),
              ),
              const SizedBox(width: 8),
              InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: onPickPath,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 6,
                  ),
                  child: Text(
                    'user_mgmt_select_dir'.tr,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                tooltip: 'delete'.tr,
                onPressed: canRemove ? onRemove : null,
                icon: const Icon(Icons.close_outlined),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: Wrap(
              spacing: 8,
              runSpacing: 10,
              children: [
                _permChip(
                  selected: true,
                  label: 'file_share_server_perm_read'.tr,
                  onSelected: null,
                ),
                _permChip(
                  selected: state.write,
                  label: 'file_share_server_perm_write'.tr,
                  onSelected: (v) {
                    state.write = v;
                    onChanged();
                  },
                ),
                _permChip(
                  selected: state.update,
                  label: 'file_share_server_perm_update'.tr,
                  onSelected: (v) {
                    state.update = v;
                    onChanged();
                  },
                ),
                _permChip(
                  selected: state.delete,
                  label: 'file_share_server_perm_delete'.tr,
                  onSelected: (v) {
                    state.delete = v;
                    onChanged();
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
