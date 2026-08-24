import 'package:flutter/material.dart';
import 'custom_colors.dart';

/// 暗色主题配置
final ThemeData darkTheme = ThemeData(
  cardColor: const Color.fromARGB(255, 18, 18, 18), //
  unselectedWidgetColor: Colors.grey.shade400, //未选中的边框颜色
  dividerColor: Colors.white.withValues(alpha: 0.3), //分割线颜色
  useMaterial3: true,
  brightness: Brightness.dark,
  colorScheme: ColorScheme.dark(
    surface: const Color.fromARGB(255, 42, 42, 42),
    primary: Color.fromARGB(255, 0, 122, 255),
    secondary: Colors.orange.shade500,
    error: Color.fromARGB(255, 255, 59, 48),
  ),
  scaffoldBackgroundColor: const Color.fromARGB(255, 26, 26, 26), //脚手架背景 黑色
  appBarTheme: AppBarTheme(
    backgroundColor: Colors.grey.shade800,
    foregroundColor: Colors.white,
    elevation: 2,
  ),
  dividerTheme: DividerThemeData(
    color: Colors.grey.shade600,
    thickness: 1,
    space: 1,
  ),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: Colors.grey.shade800,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(color: Colors.grey.shade600),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(color: Colors.grey.shade600),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(color: Colors.blue.shade600, width: 2),
    ),
  ),
  elevatedButtonTheme: ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      backgroundColor: Colors.blue.shade800,
      foregroundColor: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      elevation: 2,
    ),
  ),
  scrollbarTheme: ScrollbarThemeData(
    thumbColor: WidgetStateProperty.all(
      Colors.grey.shade600.withValues(alpha: 0.3),
    ),
    trackColor: WidgetStateProperty.all(
      Colors.grey.shade800.withValues(alpha: 0.3),
    ),
  ),
  extensions: <ThemeExtension<dynamic>>[
    CustomColors(
      nestedCardColor: Color.fromARGB(65, 0, 115, 255), // 用于嵌套卡片
      emptyCardColor: Color.fromARGB(70, 228, 228, 228), // 用于空卡片背景色
      leftTreeBgColor: Color.fromARGB(255, 18, 19, 30), // 用于左侧树背景色
      mainContentBgColor: Color.fromARGB(255, 18, 18, 18), // 用于主内容背景色
      oprationBarBgColor: Color.fromARGB(255, 30, 30, 30), //操作栏背景色
    ),
  ],
);
