import 'package:flutter/material.dart';
import 'package:get/get.dart';

class CustomEmptyState extends StatelessWidget {
  final String? message;
  final String? imagePath;
  final double? width;
  final double? height;

  const CustomEmptyState({
    super.key,
    this.message,
    this.imagePath,
    this.width,
    this.height,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Image.asset(
            imagePath ?? 'assets/icons/no_data.png',
            width: width ?? 120,
            height: height ?? 120,
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) {
              return Icon(
                Icons.inbox_outlined,
                size: (width ?? 120) * 0.8,
                color: Theme.of(context).disabledColor,
              );
            },
          ),
          const SizedBox(height: 10),
          Text(
            message ?? 'no_data'.tr,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).hintColor,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
