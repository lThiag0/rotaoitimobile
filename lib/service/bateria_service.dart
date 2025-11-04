import 'package:android_intent_plus/android_intent.dart';
import 'dart:io' show Platform;

Future<void> pedirIgnorarBateria() async {
  if (Platform.isAndroid) {
    final intent = AndroidIntent(
      action: 'android.settings.IGNORE_BATTERY_OPTIMIZATION_SETTINGS',
    );
    await intent.launch();
  }
}
