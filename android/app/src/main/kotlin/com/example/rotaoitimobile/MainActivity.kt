package com.example.rotaoitimobile

import android.app.ActivityManager
import android.content.Context
import android.content.Intent
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val CHANNEL = "com.example.rotaoitimobile/service"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {

                    // Iniciar serviço
                    "startService" -> {
                        val token = call.argument<String>("token")
                        val caminhaoId = call.argument<Int>("caminhao_id") ?: 0
                        val intent = Intent(this, LocationForegroundService::class.java)
                        intent.putExtra("token", token)
                        intent.putExtra("caminhao_id", caminhaoId)
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            startForegroundService(intent)
                        } else {
                            startService(intent)
                        }
                        result.success(null)
                    }

                    // Parar serviço
                    "stopService" -> {
                        val intent = Intent(this, LocationForegroundService::class.java)
                        stopService(intent)
                        result.success(null)
                    }

                    // Verificar se o serviço está rodando
                    "isServiceRunning" -> {
                        val isRunning = isMyServiceRunning(LocationForegroundService::class.java)
                        result.success(isRunning)
                    }

                    else -> result.notImplemented()
                }
            }
    }

    // Função auxiliar para checar se o serviço está ativo
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
