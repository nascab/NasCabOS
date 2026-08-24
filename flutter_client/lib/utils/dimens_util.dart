import 'package:flutter/material.dart';

/// 尺寸工具类 - 统一管理所有尺寸相关的数值
/// 支持响应式设计，适配PC和移动端
class DimensUtil {
  DimensUtil._();

  // ===== 屏幕尺寸判断 =====

  /// 判断是否为移动端
  static bool isMobile(BuildContext context) =>
      MediaQuery.of(context).size.width < 600;

  /// 判断是否为平板端
  static bool isTablet(BuildContext context) =>
      MediaQuery.of(context).size.width >= 600 &&
      MediaQuery.of(context).size.width < 1024;

  /// 判断是否为PC端
  static bool isDesktop(BuildContext context) =>
      MediaQuery.of(context).size.width >= 1024;

  // ===== 圆角尺寸 =====

  /// 小圆角 (4dp)
  static double get radiusSmall => 4.0;

  /// 中等圆角 (8dp)
  static double get radiusMedium => 8.0;

  /// 大圆角 (12dp)
  static double get radiusLarge => 12.0;

  /// 超大圆角 (16dp)
  static double get radiusXLarge => 16.0;

  /// 特大圆角 (20dp)
  static double get radiusXXLarge => 20.0;

  /// 按钮圆角 (响应式)
  static double buttonRadius(BuildContext context) =>
      isMobile(context) ? radiusMedium : radiusLarge;

  // ===== 间距尺寸 =====

  /// 极小间距 (2dp)
  static double get spacingXSmall => 2.0;

  /// 小间距 (4dp)
  static double get spacingSmall => 4.0;

  /// 中等间距 (8dp)
  static double get spacingMedium => 8.0;

  /// 标准间距 (12dp)
  static double get spacingStandard => 12.0;

  /// 大间距 (16dp)
  static double get spacingLarge => 16.0;

  /// 超大间距 (20dp)
  static double get spacingXLarge => 20.0;

  /// 特大间距 (24dp)
  static double get spacingXXLarge => 24.0;

  /// 巨大间距 (32dp)
  static double get spacingXXXLarge => 32.0;

  // ===== 边距尺寸 =====

  /// 页面边距 (响应式)
  static EdgeInsets pagePadding(BuildContext context) => isMobile(context)
      ? EdgeInsets.zero
      : const EdgeInsets.symmetric(horizontal: 20, vertical: 20);

  /// 内容边距 (响应式)
  static EdgeInsets contentPadding(BuildContext context) =>
      EdgeInsets.all(isMobile(context) ? spacingLarge : spacingXLarge);

  /// 标题栏边距
  static EdgeInsets get headerPadding => const EdgeInsets.all(20);

  /// 表单字段间距
  static EdgeInsets get formFieldPadding =>
      const EdgeInsets.symmetric(horizontal: 20, vertical: 16);

  // ===== 容器尺寸 =====

  /// 登录相关页面中心卡片最大宽度 (响应式)
  static BoxConstraints authCenterMaxWidthConstraints(BuildContext context) =>
      BoxConstraints(
        maxWidth: isMobile(context) ? double.infinity : 500,
        maxHeight: isMobile(context) ? double.infinity : 500,
      );

  /// 登录中心卡片圆角 (响应式)
  static double authCenterCardRadius(BuildContext context) =>
      isMobile(context) ? 0 : radiusXXLarge;

  /// 嵌套卡片圆角 (12dp)
  static double get nestedCardRadius => radiusLarge;

  /// 默认容器圆角 (12dp)
  static double get containerCardRadius => radiusLarge;

  /// 对话框最大宽度约束
  static BoxConstraints get dialogMaxWidthConstraints =>
      const BoxConstraints(maxWidth: 500);

  /// 按钮高度
  static double get buttonHeight => 48.0;

  /// 输入框高度
  static double get textFieldHeight => 56.0;

  // ===== 图标尺寸 =====

  /// 小图标尺寸 (16dp)
  static double get iconSmall => 16.0;

  /// 中等图标尺寸 (20dp)
  static double get iconMedium => 20.0;

  /// 标准图标尺寸 (24dp)
  static double get iconStandard => 24.0;

  /// 大图标尺寸 (32dp)
  static double get iconLarge => 32.0;

  /// 超大图标尺寸 (40dp)
  static double get iconXLarge => 40.0;

  // ===== 文字尺寸 =====
  static double get textXXSmall => 8.0;

  /// 极小文字 (10dp)
  static double get textXSmall => 10.0;

  /// 小文字 (12dp)
  static double get textSmall => 12.0;

  /// 中等文字 (14dp)
  static double get textMedium => 14.0;

  /// 标准文字 (16dp)
  static double get textStandard => 16.0;

  /// 大文字 (18dp)
  static double get textLarge => 18.0;

  /// 超大文字 (20dp)
  static double get textXLarge => 20.0;

  /// 特大文字 (24dp)
  static double get textXXLarge => 24.0;

  // ===== 滚动条尺寸 =====

  /// 滚动条宽度
  static double get scrollbarThickness => 8.0;

  /// 滚动条圆角
  static Radius get scrollbarRadius => const Radius.circular(4);
}

/// 尺寸工具类的快捷方式
class Dimens {
  Dimens._();

  // 圆角快捷方式
  static double get r4 => DimensUtil.radiusSmall;
  static double get r8 => DimensUtil.radiusMedium;
  static double get r12 => DimensUtil.radiusLarge;
  static double get r16 => DimensUtil.radiusXLarge;
  static double get r20 => DimensUtil.radiusXXLarge;

  // 间距快捷方式
  static double get s2 => DimensUtil.spacingXSmall;
  static double get s4 => DimensUtil.spacingSmall;
  static double get s8 => DimensUtil.spacingMedium;
  static double get s12 => DimensUtil.spacingStandard;
  static double get s16 => DimensUtil.spacingLarge;
  static double get s20 => DimensUtil.spacingXLarge;
  static double get s24 => DimensUtil.spacingXXLarge;
  static double get s32 => DimensUtil.spacingXXXLarge;

  // 文字尺寸快捷方式
  static double get t8 => DimensUtil.textXXSmall;
  static double get t10 => DimensUtil.textXSmall;
  static double get t12 => DimensUtil.textSmall;
  static double get t14 => DimensUtil.textMedium;
  static double get t16 => DimensUtil.textStandard;
  static double get t18 => DimensUtil.textLarge;
  static double get t20 => DimensUtil.textXLarge;
  static double get t24 => DimensUtil.textXXLarge;

  // 图标尺寸快捷方式
  static double get i16 => DimensUtil.iconSmall;
  static double get i20 => DimensUtil.iconMedium;
  static double get i24 => DimensUtil.iconStandard;
  static double get i32 => DimensUtil.iconLarge;
  static double get i40 => DimensUtil.iconXLarge;
}
