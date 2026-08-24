class NoScriptTagException implements Exception {
  String toString() =>
      'Did you add   <script src="https://cdn.jsdelivr.net/npm/hls.js@latest"  type="application/javascript"></script> in index.html? ';
}
