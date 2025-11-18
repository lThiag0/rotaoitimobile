import 'package:flutter/services.dart';
import 'package:rotaoitimobile/service/logcontroller.dart';

class ForegroundServiceHelper {
  static const platform = MethodChannel("com.example.rotaoitimobile/service");

  static void _log(String message) {
    LogController.instance.addLog("📱 FLUTTER → $message");
  }

  static Future<void> startLocationService(
    String token, {
    int caminhaoId = 0,
    required int paradaLongaMinutos,
    required double garagemLat,
    required double garagemLon,
  }) async {
    try {
      await platform.invokeMethod("startService", {
        "token": token,
        "caminhao_id": caminhaoId,
        "paradaLongaMinutos": paradaLongaMinutos,
        "garagemLat": garagemLat,
        "garagemLon": garagemLon,
      });
      _log("✅ Serviço de localização iniciado");
    } catch (e) {
      _log("❌ Erro ao iniciar serviço: $e");
    }
  }

  static Future<void> stopLocationService() async {
    try {
      await platform.invokeMethod("stopService");
      _log("✅ Serviço de localização parado");
    } catch (e) {
      _log("❌ Erro ao parar serviço: $e");
    }
  }

  static Future<bool> isServiceRunning() async {
    try {
      final bool isRunning = await platform.invokeMethod("isServiceRunning");
      return isRunning;
    } catch (e) {
      _log("❌ Erro ao verificar status do serviço: $e");
      return false;
    }
  }
}
