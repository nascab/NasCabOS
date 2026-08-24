import 'dart:js_interop';
import 'package:web/web.dart' as web;

void disableDefaultContextMenu() {
  web.document.oncontextmenu = (web.Event event) {
    event.preventDefault();
  }.toJS;
}
