import 'package:NasCabOS/modules/base/components.dart';
import 'package:NasCabOS/modules/base/components/custom_outlined_button.dart';
import 'package:NasCabOS/utils/dialog_util.dart';
import 'package:NasCabOS/utils/toast_util.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../../../base/components/custom_glass_card.dart';
import '../controller/nascab_account_controller.dart';

class NasCabAccountView extends GetView<NasCabAccountController> {
  final bool showTitle;

  const NasCabAccountView({super.key, this.showTitle = true});

  @override
  Widget build(BuildContext context) {
    return GetBuilder<NasCabAccountController>(
      init: NasCabAccountController(),
      builder: (ctrl) {
        return Obx(() {
          final theme = Theme.of(context);
          final isLoading = ctrl.isLoading.value;
          final user = ctrl.user.value;
          final hasUser = user != null && user.isNotEmpty;
          final errorText = ctrl.errorText.value.trim();

          return Stack(
            children: [
              Align(
                alignment: Alignment.topCenter,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 720),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (showTitle) ...[
                          Text(
                            'service_nascab_title'.tr,
                            style: theme.textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],
                        if (errorText.isNotEmpty) ...[
                          CustomGlassCard(
                            padding: const EdgeInsets.all(14),
                            border: Border.all(
                              color: theme.colorScheme.error.withValues(
                                alpha: 0.4,
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.error_outline,
                                  color: theme.colorScheme.error,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    errorText,
                                    style: theme.textTheme.bodyMedium,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                TextButton(
                                  onPressed: ctrl.refreshUser,
                                  child: Text('retry'.tr),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],
                        CustomGlassCard(
                          child: hasUser
                              ? _LoggedInCard(
                                  user: user,
                                  onLogout: ctrl.logout,
                                  onSwitchAccount: ctrl.switchAccount,
                                  onRefresh: ctrl.refreshAccount,
                                )
                              : _LoggedOutCard(onLogin: ctrl.login),
                        ),
                        if (hasUser) ...[
                          const SizedBox(height: 12),
                          _MembershipCard(
                            membership:
                                user['membership'] as Map<String, dynamic>?,
                            onPurchase: () async {
                              final opened = await ctrl.openPurchaseUrl();
                              if (opened) {
                                DialogUtil.showInfoDialog(
                                  title: 'tip'.tr,
                                  content: 'membership_purchase_refresh_tip'.tr,
                                  buttonText: 'refresh'.tr,
                                  onPressed: ctrl.refreshAccount,
                                );
                              }
                            },
                            onRefresh: ctrl.refreshAccount,
                            onUserCenter: ctrl.openUserCenterUrl,
                            onVipDiff: ctrl.openVipDiffUrl,
                            onMyDevices: ctrl.openMyDevicesUrl,
                          ),
                          // const SizedBox(height: 12),
                          // _PromotionCard(onPromotion: ctrl.openPromotionUrl),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              if (isLoading)
                Positioned.fill(
                  child: IgnorePointer(
                    child: ColoredBox(
                      color: theme.colorScheme.surface.withValues(alpha: 0.25),
                      child: const Center(
                        child: SizedBox(
                          width: 28,
                          height: 28,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );
        });
      },
    );
  }
}

class _LoggedOutCard extends StatelessWidget {
  final VoidCallback onLogin;

  const _LoggedOutCard({required this.onLogin});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'service_nascab_not_logged_in'.tr,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'service_nascab_not_logged_in_hint'.tr,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              ElevatedButton.icon(
                onPressed: onLogin,
                icon: const Icon(Icons.login),
                label: Text('service_nascab_login'.tr),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LoggedInCard extends StatelessWidget {
  final Map<String, dynamic> user;
  final VoidCallback onLogout;
  final VoidCallback onSwitchAccount;
  final VoidCallback onRefresh;

  const _LoggedInCard({
    required this.user,
    required this.onLogout,
    required this.onSwitchAccount,
    required this.onRefresh,
  });

  String? _getLoginType() {
    final loginType = user['loginType']?.toString().trim().toLowerCase() ?? '';
    if (['wechat', 'google', 'apple'].contains(loginType)) {
      return loginType;
    }
    return null;
  }

  String _displayName() {
    final nickname = user['nickname']?.toString().trim() ?? '';
    if (nickname.isNotEmpty) return nickname;
    final email = user['email']?.toString().trim() ?? '';
    if (email.isNotEmpty) return email;
    return user['id']?.toString() ?? '';
  }

  String _formatLocalTime(dynamic v) {
    DateTime? dt;
    if (v is DateTime) {
      dt = v.isUtc
          ? v
          : DateTime.utc(
              v.year,
              v.month,
              v.day,
              v.hour,
              v.minute,
              v.second,
              v.millisecond,
            );
    } else if (v is int) {
      final isMs = v > 10000000000;
      dt = DateTime.fromMillisecondsSinceEpoch(
        isMs ? v : v * 1000,
        isUtc: true,
      );
    } else if (v is String) {
      final s = v.trim();
      final n = int.tryParse(s);
      if (n != null) {
        final isMs = n > 10000000000;
        dt = DateTime.fromMillisecondsSinceEpoch(
          isMs ? n : n * 1000,
          isUtc: true,
        );
      } else {
        dt = DateTime.tryParse(s);
        if (dt != null && !dt.isUtc) {
          dt = DateTime.utc(
            dt.year,
            dt.month,
            dt.day,
            dt.hour,
            dt.minute,
            dt.second,
            dt.millisecond,
          );
        }
      }
    }
    if (dt == null) return (v?.toString() ?? '');
    final local = dt.toLocal();
    String two(int x) => x.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = _displayName();
    final lastLoginAt = _formatLocalTime(user['lastLoginAt']);
    final loginType = _getLoginType();

    return Padding(
      padding: const EdgeInsets.all(6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: theme.colorScheme.onSurface.withValues(
                  alpha: 0.2,
                ),
                child: Icon(
                  Icons.person,
                  color: theme.colorScheme.primary.withValues(alpha: 0.9),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (loginType != null) ...[
                          Image.asset(
                            'assets/icons/$loginType.png',
                            width: 22,
                            height: 22,
                          ),
                          const SizedBox(width: 8),
                        ],
                        Expanded(
                          child: Text(
                            name,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    GestureDetector(
                      onTap: () {
                        final id = user['id']?.toString() ?? '';
                        if (id.isNotEmpty) {
                          Clipboard.setData(ClipboardData(text: id));
                          ToastUtil.show('copied'.tr);
                        }
                      },
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              "ID:${user['id']?.toString() ?? ''}",
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text(
                          'service_nascab_last_login'.trParams({
                            'time': lastLoginAt.isEmpty ? '-' : lastLoginAt,
                          }),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(width: 8),
                        TextButton(
                          onPressed: onRefresh,
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            minimumSize: const Size(0, 28),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: Text('refresh'.tr),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              CustomOutlinedButton(
                onPressed: onLogout,
                icon: const Icon(Icons.logout),
                text: 'service_nascab_logout'.tr,
              ),
              CustomOutlinedButton(
                onPressed: onSwitchAccount,
                icon: const Icon(Icons.switch_account),
                text: 'service_nascab_switch_account'.tr,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 解析会员相关时间，返回 (DateTime? utcOrLocal, bool treatAsLocal)。
/// 若服务器返回的是当地时间（无 Z 的字符串），treatAsLocal=true，直接按本地时间展示，不再 toLocal，避免重复加时区。
(DateTime?, bool) _parseMembershipDateTime(dynamic v) {
  DateTime? dt;
  bool treatAsLocal = false;
  if (v is DateTime) {
    treatAsLocal = !v.isUtc;
    dt = v.isUtc
        ? v
        : DateTime.utc(
            v.year,
            v.month,
            v.day,
            v.hour,
            v.minute,
            v.second,
            v.millisecond,
          );
  } else if (v is int) {
    final isMs = v > 10000000000;
    dt = DateTime.fromMillisecondsSinceEpoch(isMs ? v : v * 1000, isUtc: true);
  } else if (v is String) {
    final s = v.trim();
    final n = int.tryParse(s);
    if (n != null) {
      final isMs = n > 10000000000;
      dt = DateTime.fromMillisecondsSinceEpoch(
        isMs ? n : n * 1000,
        isUtc: true,
      );
    } else {
      dt = DateTime.tryParse(s);
      if (dt != null && !dt.isUtc) treatAsLocal = true;
      if (dt != null && !dt.isUtc) {
        dt = DateTime(
          dt.year,
          dt.month,
          dt.day,
          dt.hour,
          dt.minute,
          dt.second,
          dt.millisecond,
        );
      }
    }
  }
  return (dt, treatAsLocal);
}

/// 格式化会员相关时间。若服务器返回的是当地时间（无 Z 的字符串），则直接按本地时间展示，不再 toLocal，避免重复加时区。
String _formatMembershipTime(dynamic v) {
  final (dt, treatAsLocal) = _parseMembershipDateTime(v);
  if (dt == null) return (v?.toString() ?? '-');
  final display = treatAsLocal ? dt : dt.toLocal();
  String two(int x) => x.toString().padLeft(2, '0');
  return '${display.year}-${two(display.month)}-${two(display.day)} ${two(display.hour)}:${two(display.minute)}';
}

/// 判断会员时间是否已过期（早于当前时间）。
bool _isMembershipExpired(dynamic v) {
  final (dt, treatAsLocal) = _parseMembershipDateTime(v);
  if (dt == null) return false;
  final now = treatAsLocal ? DateTime.now() : DateTime.now().toUtc();
  return dt.isBefore(now);
}

class _MembershipCard extends StatelessWidget {
  final Map<String, dynamic>? membership;
  final VoidCallback onPurchase;
  final VoidCallback onRefresh;
  final VoidCallback onUserCenter;
  final VoidCallback onVipDiff;
  final VoidCallback onMyDevices;

  const _MembershipCard({
    this.membership,
    required this.onPurchase,
    required this.onRefresh,
    required this.onUserCenter,
    required this.onVipDiff,
    required this.onMyDevices,
  });

  String _vipTypeLabel(int? vipType) {
    if (vipType == null) return 'service_nascab_membership_free'.tr;
    switch (vipType) {
      case 1:
        return 'service_nascab_membership_vip_family'.tr;
      case 2:
        return 'service_nascab_membership_vip_enterprise'.tr;
      default:
        return 'service_nascab_membership_free'.tr;
    }
  }

  String _statusLabel(String? status) {
    if (status == null) return '-';
    return status.toLowerCase() == 'active'
        ? 'service_nascab_membership_status_active'.tr
        : 'service_nascab_membership_status_inactive'.tr;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isMember = membership != null && membership!.isNotEmpty;

    return CustomGlassCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isMember ? Icons.card_membership : Icons.loyalty_outlined,
                  size: 22,
                  color: isMember
                      ? theme.colorScheme.primary.withValues(alpha: 0.9)
                      : theme.colorScheme.onSurfaceVariant.withValues(
                          alpha: 0.8,
                        ),
                ),
                const SizedBox(width: 10),
                Text(
                  'service_nascab_membership_title'.tr,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 10),
                TextButton(
                  onPressed: onUserCenter,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    minimumSize: const Size(0, 32),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text('service_nascab_membership_user_center'.tr),
                ),
                TextButton(
                  onPressed: onRefresh,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    minimumSize: const Size(0, 32),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text('refresh'.tr),
                ),
              ],
            ),
            const SizedBox(height: 14),
            if (!isMember) ...[
              Text(
                'service_nascab_membership_free'.tr,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: CustomButton(
                  text: 'service_nascab_membership_purchase'.tr,
                  onPressed: onPurchase,
                ),
              ),
            ] else ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 120,
                    child: Text(
                      'service_nascab_membership_vip_type'.tr,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  Flexible(
                    child: Text(
                      _vipTypeLabel(
                        _parseInt(
                          membership!['vipType'] ?? membership!['vip_type'],
                        ),
                      ),
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                  const SizedBox(width: 10),
                  TextButton(
                    onPressed: onVipDiff,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: const Size(0, 28),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text('service_nascab_membership_vip_diff'.tr),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _InfoRow(
                label: 'service_nascab_membership_max_devices'.tr,
                value:
                    '${_parseInt(membership!['maxBindServer'] ?? membership!['max_bind_server']) ?? 0}',
                theme: theme,
              ),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 120,
                    child: Text(
                      'service_nascab_membership_bound_devices'.tr,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  Flexible(
                    child: Text(
                      '${_parseInt(membership!['bindServerCount'] ?? membership!['bind_server_count']) ?? 0}',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                  const SizedBox(width: 10),
                  TextButton(
                    onPressed: onMyDevices,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: const Size(0, 28),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text('service_nascab_membership_my_devices'.tr),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _InfoRow(
                label: 'service_nascab_membership_expires_at'.tr,
                value: _formatMembershipTime(
                  membership!['expiresAt'] ?? membership!['expires_at'],
                ),
                valueSuffix:
                    _isMembershipExpired(
                      membership!['expiresAt'] ?? membership!['expires_at'],
                    )
                    ? 'service_nascab_membership_expired'.tr
                    : null,
                valueSuffixColor: theme.colorScheme.error,
                theme: theme,
              ),
              const SizedBox(height: 8),
              _InfoRow(
                label: 'service_nascab_membership_status'.tr,
                value: _statusLabel(membership!['status']?.toString()),
                valueColor:
                    (membership!['status']?.toString().toLowerCase() !=
                        'active')
                    ? theme.colorScheme.error
                    : null,
                theme: theme,
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: CustomButton(
                  text: 'service_nascab_membership_renew_or_upgrade'.tr,
                  onPressed: onPurchase,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PromotionCard extends StatelessWidget {
  final VoidCallback onPromotion;

  const _PromotionCard({required this.onPromotion});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return CustomGlassCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'service_nascab_promotion_title'.tr,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'service_nascab_promotion_subtitle'.tr,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            CustomButton(
              text: 'service_nascab_promotion_action'.tr,
              onPressed: onPromotion,
            ),
          ],
        ),
      ),
    );
  }
}

int? _parseInt(dynamic v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString());
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final ThemeData theme;
  final Color? valueColor;
  final String? valueSuffix;
  final Color? valueSuffixColor;

  const _InfoRow({
    required this.label,
    required this.value,
    required this.theme,
    this.valueColor,
    this.valueSuffix,
    this.valueSuffixColor,
  });

  @override
  Widget build(BuildContext context) {
    final suffix = valueSuffix;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 120,
          child: Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(
          child: suffix != null && suffix.isNotEmpty
              ? RichText(
                  text: TextSpan(
                    style: theme.textTheme.bodyMedium,
                    children: [
                      TextSpan(
                        text: value,
                        style: valueColor != null
                            ? TextStyle(color: valueColor)
                            : null,
                      ),
                      TextSpan(
                        text: '  $suffix',
                        style: TextStyle(
                          color: valueSuffixColor ?? theme.colorScheme.error,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                )
              : Text(
                  value,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: valueColor,
                  ),
                ),
        ),
      ],
    );
  }
}
