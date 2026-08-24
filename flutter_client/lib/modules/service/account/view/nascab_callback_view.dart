import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../../core/web/nascab_auth_stub.dart'
    if (dart.library.html) '../../../../core/web/nascab_auth_web.dart';

class NasCabCallbackView extends StatefulWidget {
  const NasCabCallbackView({super.key});

  @override
  State<NasCabCallbackView> createState() => _NasCabCallbackViewState();
}

class _NasCabCallbackViewState extends State<NasCabCallbackView> {
  final Map<String, String> _authResult = {};

  @override
  void initState() {
    super.initState();
    _authResult.addAll(_extractAuthFromCurrentUrl());
    if (_authResult.isNotEmpty) {
      sendAuthResultToOpenerAndClose(_authResult);
    }
  }

  Map<String, String> _extractAuthFromCurrentUrl() {
    final uri = Uri.base;
    final params = <String, String>{};
    params.addAll(uri.queryParameters);

    final fragment = uri.fragment;
    final idx = fragment.indexOf('?');
    if (idx >= 0) {
      final queryPart = fragment.substring(idx + 1);
      if (queryPart.isNotEmpty) {
        try {
          params.addAll(Uri.splitQueryString(queryPart));
        } catch (_) {}
      }
    }

    final code = params['code']?.trim() ?? '';
    final jwt = params['jwt']?.trim() ?? '';
    if (code.isNotEmpty) return {'code': code};
    if (jwt.isNotEmpty) return {'jwt': jwt};
    return {};
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasAuth = _authResult.isNotEmpty;
    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  hasAuth ? Icons.check_circle_outline : Icons.error_outline,
                  size: 44,
                  color: hasAuth
                      ? theme.colorScheme.primary
                      : theme.colorScheme.error,
                ),
                const SizedBox(height: 12),
                Text(
                  hasAuth
                      ? 'service_nascab_callback_success'.tr
                      : 'service_nascab_callback_failed'.tr,
                  style: theme.textTheme.titleMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  hasAuth
                      ? 'service_nascab_callback_success_hint'.tr
                      : 'service_nascab_callback_failed_hint'.tr,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
