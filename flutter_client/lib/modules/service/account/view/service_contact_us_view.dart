import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import '../../../base/components/custom_container.dart';
import '../../../base/components/custom_glass_card.dart';

class ServiceContactUsView extends StatelessWidget {
  const ServiceContactUsView({super.key});

  @override
  Widget build(BuildContext context) {
    return CustomContainer(
      padding: const EdgeInsets.all(0),
      borderRadius: BorderRadius.circular(0),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'service_contact_us_title'.tr,
              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            _buildContactCard(),
          ],
        ),
      ),
    );
  }

  Widget _buildContactCard() {
    return CustomGlassCard(
      child: Padding(
        padding: const EdgeInsets.all(0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'service_contact_us_feedback_title'.tr,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Get.theme.primaryColor,
                  ),
                ),
              ],
            ),
            Text(
              'service_contact_us_feedback_body'.tr,
              style: const TextStyle(fontSize: 15, height: 1.6),
            ),
            GestureDetector(
              onTap: () => _copyEmail('ypptec@gmail.com'),
              child: Container(
                decoration: BoxDecoration(
                  color: Get.theme.primaryColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Get.theme.primaryColor.withValues(alpha: 0.3),
                    width: 1,
                  ),
                ),
                child: Row(
                  children: [
                    Text(
                      'ypptec@gmail.com',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: Get.theme.colorScheme.primary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      Icons.touch_app,
                      size: 18,
                      color: Get.theme.colorScheme.primary.withValues(
                        alpha: 0.7,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Row(
              children: [
                Icon(
                  Icons.support_agent_outlined,
                  size: 24,
                  color: Get.theme.primaryColor,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'service_contact_us_issue_title'.tr,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Get.theme.primaryColor,
                    ),
                  ),
                ),
              ],
            ),
            Text(
              'service_contact_us_issue_body'.tr,
              style: const TextStyle(fontSize: 15, height: 1.6),
            ),
          ],
        ),
      ),
    );
  }

  void _copyEmail(String email) {
    Clipboard.setData(ClipboardData(text: email));
    Get.snackbar(
      'service_contact_us_email_copied'.tr,
      email,
      snackPosition: SnackPosition.BOTTOM,
      backgroundColor: Get.theme.colorScheme.primary,
      colorText: Colors.white,
      duration: const Duration(seconds: 2),
      margin: const EdgeInsets.all(16),
      borderRadius: 8,
    );
  }
}
