import 'package:flutter/material.dart';

class CustomNoData extends StatelessWidget {
  final String text;
  final Color? backgroundColor;
  final double imageWidth;
  final double imageHeight;
  final String imagePath;
  final List<Color?> backgroundColorList;

  const CustomNoData({
    super.key,
    this.text = '无数据',
    this.backgroundColor,
    this.backgroundColorList = const [],
    this.imageWidth = 100,
    this.imageHeight = 100,
    this.imagePath = 'assets/icons/no_data.png',
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      color: backgroundColor,
      decoration: backgroundColorList.isNotEmpty
          ? BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: backgroundColorList
                    .map((e) => e ?? Colors.transparent)
                    .toList(),
              ),
            )
          : null,
      alignment: Alignment.center,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Image.asset(
            imagePath,
            width: imageWidth,
            height: imageHeight,
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) {
              return Icon(
                Icons.inbox_outlined,
                size: imageWidth * 0.8,
                color: theme.disabledColor,
              );
            },
          ),
          if (text.isNotEmpty) const SizedBox(height: 15),
          if (text.isNotEmpty)
            Text(
              text,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.hintColor,
              ),
              textAlign: TextAlign.center,
            ),
        ],
      ),
    );
  }
}
