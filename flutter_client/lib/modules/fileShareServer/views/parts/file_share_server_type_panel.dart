part of '../file_share_server_view.dart';

class _TypePanel extends StatelessWidget {
  final String serverType;
  final FileShareServerController ctrl;
  const _TypePanel({required this.serverType, required this.ctrl});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final customColors = theme.extension<CustomColors>();
    return Container(
      color: customColors?.mainContentBgColor,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            _ServiceHeader(serverType: serverType, ctrl: ctrl),
            const SizedBox(height: 12),

            CustomGlassCard(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'file_share_server_user_permission_rules'.tr,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    CustomButton(
                      text: 'file_share_server_add_config'.tr,
                      onPressed: () async {
                        final res = await showDialog<_ConfigDialogResult>(
                          context: context,
                          builder: (_) => _ConfigDialog(
                            ctrl: ctrl,
                            serverType: serverType,
                            existingUids:
                                ctrl.configsByType[serverType]
                                    ?.map((e) => e['uid'])
                                    .toList() ??
                                const [],
                          ),
                        );
                        if (res == null) return;
                        await ctrl.upsertConfig(
                          uid: res.uid,
                          serverType: serverType,
                          rootPath: res.rootPath,
                        );
                      },
                      icon: const Icon(Icons.add_outlined),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: Obx(() {
                final list = ctrl.configsByType[serverType] ?? const [];
                if (list.isEmpty) {
                  return CustomNoData(text: 'no_data'.tr);
                }
                return ListView.separated(
                  padding: EdgeInsets.zero,
                  itemCount: list.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final item = list[i];
                    return _ConfigCard(
                      ctrl: ctrl,
                      serverType: serverType,
                      item: item,
                    );
                  },
                );
              }),
            ),
          ],
        ),
      ),
    );
  }
}
