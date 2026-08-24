import 'package:flutter/material.dart';

/// 自定义颜色扩展
class CustomColors extends ThemeExtension<CustomColors> {
  final Color nestedCardColor;

  final Color emptyCardColor; // 新增：空卡片背景色参数
  final Color leftTreeBgColor; // 新增：左侧树背景色参数
  final Color mainContentBgColor; // 新增：主内容背景色参数
  final Color oprationBarBgColor; // 新增：操作栏背景色参数

  const CustomColors({
    required this.nestedCardColor,
    required this.emptyCardColor,
    required this.leftTreeBgColor,
    required this.mainContentBgColor,
    required this.oprationBarBgColor,
  });

  @override
  ThemeExtension<CustomColors> copyWith({
    Color? nestedCardColor,
    Color? secondaryCardColor,
    Color? tertiaryCardColor, // 新增：第三级卡片颜色参数
    Color? emptyCardColor, // 新增：空卡片背景色参数
    Color? leftTreeBgColor, // 新增：左侧树背景色参数
    Color? mainContentBgColor, // 新增：主内容背景色参数
    Color? oprationBarBgColor, // 新增：操作栏背景色参数
  }) {
    return CustomColors(
      nestedCardColor: nestedCardColor ?? this.nestedCardColor,
      emptyCardColor: emptyCardColor ?? this.emptyCardColor,
      leftTreeBgColor: leftTreeBgColor ?? this.leftTreeBgColor,
      mainContentBgColor: mainContentBgColor ?? this.mainContentBgColor,
      oprationBarBgColor: oprationBarBgColor ?? this.oprationBarBgColor,
    );
  }

  @override
  ThemeExtension<CustomColors> lerp(
    ThemeExtension<CustomColors>? other,
    double t,
  ) {
    if (other is! CustomColors) return this;
    return CustomColors(
      nestedCardColor: Color.lerp(nestedCardColor, other.nestedCardColor, t)!,
      emptyCardColor: Color.lerp(emptyCardColor, other.emptyCardColor, t)!,
      leftTreeBgColor: Color.lerp(leftTreeBgColor, other.leftTreeBgColor, t)!,
      mainContentBgColor: Color.lerp(
        mainContentBgColor,
        other.mainContentBgColor,
        t,
      )!,
      oprationBarBgColor: Color.lerp(
        oprationBarBgColor,
        other.oprationBarBgColor,
        t,
      )!,
    );
  }
}
