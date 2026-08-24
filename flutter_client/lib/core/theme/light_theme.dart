import 'package:flutter/material.dart';
import 'custom_colors.dart';

/// 亮色主题配置
final ThemeData lightTheme = ThemeData(
  cardColor: const Color.fromARGB(255, 255, 255, 255), //
  dividerColor: Color.fromARGB(96, 28, 26, 26), //分割线颜色
  useMaterial3: true,
  brightness: Brightness.light,
  colorScheme: ColorScheme.light(
    surface: const Color.fromARGB(255, 245, 245, 245),
    primary: Colors.blue.shade800,
    secondary: Colors.orangeAccent,
    onSurface: Color.fromARGB(255, 51, 51, 51),
  ),
  scaffoldBackgroundColor: const Color.fromARGB(255, 245, 245, 245),
  appBarTheme: AppBarTheme(
    backgroundColor: Colors.blue.shade800,
    foregroundColor: Colors.white,
    elevation: 2,
  ),
  dividerTheme: DividerThemeData(
    color: Colors.grey.shade300,
    thickness: 1,
    space: 1,
  ),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: Colors.grey.shade100,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(color: Colors.grey.shade400),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(color: Colors.grey.shade400),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(color: Colors.blue.shade800, width: 2),
    ),
  ),
  elevatedButtonTheme: ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      backgroundColor: Colors.blue.shade400,
      foregroundColor: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      elevation: 2,
    ),
  ),
  scrollbarTheme: ScrollbarThemeData(
    thumbColor: WidgetStateProperty.all(Colors.grey.shade400),
    trackColor: WidgetStateProperty.all(Colors.grey.shade200),
  ),
  extensions: const <ThemeExtension<dynamic>>[
    CustomColors(
      nestedCardColor: Color.fromARGB(150, 255, 255, 255), // 用于嵌套卡片
      emptyCardColor: Color.fromARGB(230, 245, 245, 245), // 用于空卡片背景色
      leftTreeBgColor: Color.fromARGB(255, 250, 250, 250), // 用于左侧树背景色
      mainContentBgColor: Color.fromARGB(255, 255, 255, 255), // 用于主内容背景色
      oprationBarBgColor: Color.fromARGB(255, 250, 250, 250), //操作栏背景色
    ),
  ],
);
