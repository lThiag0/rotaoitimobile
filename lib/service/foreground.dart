import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart';

class ForegroundServiceHelper {
  static const platform = MethodChannel("com.example.rotaoitimobile/service");

  static Future<void> startLocationService(
    String token, {
    int caminhaoId = 0,
  }) async {
    try {
      //print("🔹 Iniciando serviço com token: $token");
      await platform.invokeMethod("startService", {
        "token": token,
        "caminhao_id": caminhaoId, // envia para o Android
      });
      //print("✅ Serviço de localização iniciado");
    } catch (e) {
      //print("❌ Erro ao iniciar serviço: $e");
      ScaffoldMessenger.of(context as BuildContext).showSnackBar(
        SnackBar(
          content: Text("Erro ao parar serviço: $e!"),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  static Future<void> stopLocationService() async {
    try {
      //print("🔹 Parando serviço");
      await platform.invokeMethod("stopService");
      //print("✅ Serviço de localização parado");
    } catch (e) {
      //print("❌ Erro ao parar serviço: $e");
      ScaffoldMessenger.of(context as BuildContext).showSnackBar(
        SnackBar(
          content: Text("Erro ao parar serviço: $e!"),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  static Future<bool> isServiceRunning() async {
    try {
      final bool isRunning = await platform.invokeMethod("isServiceRunning");
      return isRunning;
    } catch (e) {
      //print("❌ Erro ao verificar status do serviço: $e");
      return false;
    }
  }
}
