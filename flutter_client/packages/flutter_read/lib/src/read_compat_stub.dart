class ReadCompat {
  static final ReadCompat _instance = ReadCompat._internal();

  factory ReadCompat() {
    return _instance;
  }

  ReadCompat._internal();

  bool isDartVersionAtLeast300() {
    return true;
  }
}
