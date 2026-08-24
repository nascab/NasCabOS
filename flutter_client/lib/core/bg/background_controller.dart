import 'package:get/get.dart';

///背景和壁纸全局控制器
class BackgroundController extends GetxController {
  static BackgroundController get instance => Get.find<BackgroundController>();

  /// 背景图片URL
  final Rx<String> _loginBgUrl = Rx<String>('assets/home/login_bg.jpg');
  String get loginBgUrl => _loginBgUrl.value;
  set loginBgUrl(String value) => _loginBgUrl.value = value;
}
