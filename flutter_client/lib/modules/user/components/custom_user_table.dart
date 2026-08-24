import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../base/components/custom_checkbox.dart';

class CustomUserTable extends StatelessWidget {
  final List<Map<String, dynamic>> users;
  final Set<int> selectedIds;
  final void Function(int id) onToggleSelect;
  final void Function(Map<String, dynamic> user) onEdit;
  const CustomUserTable({
    super.key,
    required this.users,
    required this.selectedIds,
    required this.onToggleSelect,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: DataTable(
        columns: [
          DataColumn(label: Text('username'.tr)),
          DataColumn(label: Text('user_mgmt_type'.tr)),
          DataColumn(label: Text('edit'.tr)),
        ],
        rows: users.map((u) {
          final id = (u['id'] as int);
          final isSelected = selectedIds.contains(id);
          return DataRow(
            selected: isSelected,
            onSelectChanged: (_) => onToggleSelect(id),
            cells: [
              DataCell(
                Row(
                  children: [
                    CustomCheckbox(
                      value: isSelected,
                      onChanged: (_) => onToggleSelect(id),
                    ),
                    Text(u['username']?.toString() ?? ''),
                  ],
                ),
              ),
              DataCell(Text(u['type']?.toString() ?? '')),
              DataCell(
                IconButton(
                  icon: const Icon(Icons.edit),
                  onPressed: () => onEdit(u),
                ),
              ),
            ],
          );
        }).toList(),
      ),
    );
  }
}
