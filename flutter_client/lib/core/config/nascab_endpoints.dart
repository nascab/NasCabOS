import 'package:flutter/foundation.dart';

class NasCabEndpoints {
  NasCabEndpoints._();
  // defaultValue: kReleaseMode ? 'https://nas.cab' : 'https://test.nas.cab',
  static const String websiteBaseUrl = String.fromEnvironment(
    'NASCAB_WEBSITE_BASE_URL',
    defaultValue: kReleaseMode ? 'https://nas.cab' : 'https://nas.cab',
  );
  // defaultValue: kReleaseMode ? 'https://nas.cab' : 'https://test.nas.cab',
  static const String signalBaseUrl = String.fromEnvironment(
    'NASCAB_SIGNAL_BASE_URL',
    defaultValue: kReleaseMode ? 'https://nas.cab' : 'https://nas.cab',
  );
}

