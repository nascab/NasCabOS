import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../../core/api/api_controller.dart';
import '../pc_home_controller.dart';

class PcAllAppsOverlay extends StatelessWidget {
  const PcAllAppsOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ctrl = PcHomeController.instance;

    return GetBuilder<ApiController>(
      builder: (api) {
        return Obx(() {
          final apps = ctrl.filteredAllApps();
          return Positioned.fill(
            child: Stack(
              children: [
                ClipRect(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                    child: Container(
                      color: theme.colorScheme.surface.withValues(alpha: 0.2),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: () => ctrl.toggleAllAppsOverlay(false),
                    child: Container(color: Colors.transparent),
                  ),
                ),
                Center(
                  child: GestureDetector(
                    onTap: () {},
                    child: Container(
                      constraints: const BoxConstraints(
                        minWidth: 720,
                        maxWidth: 960,
                      ),
                      margin: const EdgeInsets.only(top: 80),
                      child: Column(
                        children: [
                          _searchBar(context),
                          const SizedBox(height: 24),
                          Expanded(
                            child: GestureDetector(
                              behavior: HitTestBehavior.translucent,
                              onTap: () => ctrl.toggleAllAppsOverlay(false),
                              child: GridView.builder(
                                gridDelegate:
                                    const SliverGridDelegateWithMaxCrossAxisExtent(
                                      maxCrossAxisExtent: 160,
                                      mainAxisSpacing: 16,
                                      crossAxisSpacing: 16,
                                      childAspectRatio: 0.9,
                                    ),
                                itemBuilder: (c, i) {
                                  final app = apps[i];
                                  return _AllAppsTile(app: app);
                                },
                                itemCount: apps.length,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        });
      },
    );
  }

  Widget _searchBar(BuildContext context) {
    final ctrl = PcHomeController.instance;
    final theme = Theme.of(context);
    return TextField(
      autofocus: true,
      onChanged: ctrl.updateSearch,
      decoration: InputDecoration(
        hintText: 'home_search_placeholder'.tr,
        prefixIcon: const Icon(Icons.search),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        filled: true,
        fillColor: theme.colorScheme.surface,
      ),
    );
  }
}

class _AllAppsTile extends StatefulWidget {
  final String app;
  const _AllAppsTile({required this.app});

  @override
  State<_AllAppsTile> createState() => _AllAppsTileState();
}

class _AllAppsTileState extends State<_AllAppsTile> {
  bool _hover = false;

  void _openApp(PcHomeController ctrl, String app) {
    final desktopRect = ctrl.getDeskRect();
    if (app == 'monitor') {
      const size = Size(320, 620);
      ctrl.openApp(
        windowId: app,
        viewBuilder: ctrl.builtinAppViewBuilder(app),
        title: 'app_monitor'.tr,
        icon: ctrl.buildAppIcon(app),
        showTitle: false,
        resizable: false,
        maximizable: false,
        minimizable: false,
        minSize: size,
        initialSize: size,
        initialPosition: Offset(
          desktopRect.right - size.width,
          desktopRect.top,
        ),
      );
      return;
    }
    if (app == 'process') {
      ctrl.openApp(
        windowId: app,
        viewBuilder: ctrl.builtinAppViewBuilder(app),
        title: 'app_process'.tr,
        icon: ctrl.buildAppIcon(app),
        showTitle: false,
      );
      return;
    }
    if (app == 'task_center') {
      final w = ctrl.windows.defaultWindowWidth;
      final h = ctrl.windows.defaultWindowHeight;
      ctrl.openApp(
        windowId: app,
        viewBuilder: ctrl.builtinAppViewBuilder(app),
        title: 'app_$app'.tr,
        icon: ctrl.buildAppIcon(app),
        initialSize: Size(w, h),
        initialPosition: Offset(desktopRect.right - w, desktopRect.top),
      );
      return;
    }
    ctrl.openApp(
      windowId: app,
      viewBuilder: ctrl.builtinAppViewBuilder(app),
      title: 'app_$app'.tr,
      icon: ctrl.buildAppIcon(app),
      showTitle: app != 'movie' && app != 'process',
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ctrl = PcHomeController.instance;
    final app = widget.app;
    final inDesktop = ctrl.isInDesktop(app);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          _openApp(ctrl, app);
          ctrl.toggleAllAppsOverlay(false);
        },
        child: Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface.withValues(alpha: 0.65),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 8,
              ),
            ],
          ),
          child: Stack(
            children: [
              Positioned.fill(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Image.asset(
                      'assets/app_icons/$app.webp',
                      width: 48,
                      height: 48,
                      filterQuality: FilterQuality.high,
                      isAntiAlias: true,
                      cacheWidth: (48 * MediaQuery.devicePixelRatioOf(context))
                          .round()
                          .clamp(1, 4096),
                      cacheHeight: (48 * MediaQuery.devicePixelRatioOf(context))
                          .round()
                          .clamp(1, 4096),
                      errorBuilder: (c, e, s) {
                        return Icon(
                          Icons.apps,
                          size: 40,
                          color: theme.colorScheme.onSurface,
                        );
                      },
                    ),
                    const SizedBox(height: 8),
                    Text('app_$app'.tr, style: theme.textTheme.bodyMedium),
                  ],
                ),
              ),
              Positioned(
                right: 8,
                top: 8,
                child: MouseRegion(
                  onEnter: (_) => setState(() => _hover = true),
                  onExit: (_) => setState(() => _hover = false),
                  child: Tooltip(
                    message: inDesktop
                        ? 'home_action_remove'.tr
                        : 'home_action_add'.tr,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: () async {
                        if (inDesktop) {
                          await ctrl.removeFromDesktop(app);
                        } else {
                          await ctrl.addToDesktop(app);
                        }
                        setState(() {});
                      },
                      child: Container(
                        width: 36,
                        height: 36,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: _hover
                              ? theme.colorScheme.primary.withValues(
                                  alpha: 0.12,
                                )
                              : Colors.transparent,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          inDesktop ? Icons.remove : Icons.add,
                          color: theme.colorScheme.onSurface,
                          size: 20,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
