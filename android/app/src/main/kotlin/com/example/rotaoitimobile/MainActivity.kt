package com.example.rotaoitimobile

import android.app.ActivityManager
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    companion object {
        var logChannel: MethodChannel? = null

        fun sendLog(msg: String) {
            try {
                logChannel?.invokeMethod("sendLog", msg)
            } catch (e: Exception) {
                Log.e("LOG_BRIDGE", "Erro ao enviar log: ${e.message}")
            }
        }
    }

    private val CHANNEL = "com.example.rotaoitimobile/service"
    private val LOG_CHANNEL = "rotaoiti_logs"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Instancia canal de logs
        logChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            LOG_CHANNEL
        )

        // Canal do serviço
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {

                    "startService" -> {
                        val token = call.argument<String>("token")
                        val caminhaoId = call.argument<Int>("caminhao_id") ?: 0
                        val paradaLongaMinutos =
                            (call.arguments as Map<String, Any?>)["paradaLongaMinutos"]?.toString()?.toIntOrNull()
                                ?: 0
                        val garagemLat =
                            (call.arguments as Map<String, Any?>)["garagemLat"]?.toString()?.toDoubleOrNull()
                                ?: 0.0
                        val garagemLon =
                            (call.arguments as Map<String, Any?>)["garagemLon"]?.toString()?.toDoubleOrNull()
                                ?: 0.0

                        Log.d("MAINCHANNEL", "Recebido do Flutter:")
                        Log.d("MAINCHANNEL", "token = $token")
                        Log.d("MAINCHANNEL", "caminhaoId = $caminhaoId")
                        Log.d("MAINCHANNEL", "paradaLongaMinutos = $paradaLongaMinutos")
                        Log.d("MAINCHANNEL", "garagemLat = $garagemLat")
                        Log.d("MAINCHANNEL", "garagemLon = $garagemLon")

                        val intent = Intent(this, LocationForegroundService::class.java)
                        intent.putExtra("token", token)
                        intent.putExtra("caminhao_id", caminhaoId)
                        intent.putExtra("parada_longa_minutos", paradaLongaMinutos)
                        intent.putExtra("garagem_latitude", garagemLat)
                        intent.putExtra("garagem_longitude", garagemLon)

                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            startForegroundService(intent)
                        } else {
                            startService(intent)
                        }
                        result.success(null)
                    }

                    "stopService" -> {
                        val intent = Intent(this, LocationForegroundService::class.java)
                        stopService(intent)
                        result.success(null)
                    }

                    "isServiceRunning" -> {
                        val isRunning = isMyServiceRunning(LocationForegroundService::class.java)
                        result.success(isRunning)
                    }

                    else -> result.notImplemented()
                }
            }
    }

    private fun isMyServiceRunning(serviceClass: Class<*>): Boolean {
        val manager = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        for (service in manager.getRunningServices(Int.MAX_VALUE)) {
            if (serviceClass.name == service.service.className) {
                return true
            }
        }
        return false
    }
}
