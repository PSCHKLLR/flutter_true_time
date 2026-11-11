import 'package:flutter_web_plugins/flutter_web_plugins.dart';

/// Web is session-scoped; no native epoch or socket implementation is registered.
class FlutterTrueTimeWeb {
  static void registerWith(Registrar registrar) {}
}
