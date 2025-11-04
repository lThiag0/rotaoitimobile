package com.example.rotaoitimobile

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.database.sqlite.SQLiteDatabase
import android.location.Location
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.os.Build
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationCompat
import com.google.android.gms.location.*
import kotlinx.coroutines.*
import okhttp3.MediaType.Companion.toMediaTypeOrNull
import okhttp3.MultipartBody
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.asRequestBody
import org.json.JSONObject
import java.io.File
import java.util.concurrent.TimeUnit

class LocationForegroundService : Service() {

    private val TAG = "LocationService"
    private val CHANNEL_ID = "rotaoiti_channel"

    private lateinit var fusedLocationClient: FusedLocationProviderClient
    private lateinit var locationCallback: LocationCallback

    private var token: String? = null
    private var caminhaoID: Int? = null
    private var db: SQLiteDatabase? = null
    private val coroutineScope = CoroutineScope(Dispatchers.IO + SupervisorJob())

    // APIs
    private val API_URL_LOCALIZACAO = "https://srv962439.hstgr.cloud/api/localizacoes"
    private val API_URL_ENTREGAS = "https://srv962439.hstgr.cloud/api/entregas"
    private val API_URL_PARADAS = "https://srv962439.hstgr.cloud/api/paradas"
    private val API_URL_ABASTECIMENTO = "https://srv962439.hstgr.cloud/api/abastecimentos"

    private val client = OkHttpClient.Builder()
        .connectTimeout(60, TimeUnit.SECONDS)
        .writeTimeout(60, TimeUnit.SECONDS)
        .readTimeout(60, TimeUnit.SECONDS)
        .build()

    // Configuração de paradas
    private val MIN_PARADA_MILLIS = 10 * 60 * 1000L // 1 minuto para teste
    private val MIN_DIST_PARADA_METROS = 40f       // 10 metros
    private val MADEIREIRA_LAT = -2.9203299154158238
    private val MADEIREIRA_LON = -41.728875099999975
    private val RAIO_MADEIREIRA_METROS = 100.0

    private var ultimaLocalizacao: Location? = null
    private var inicioParada: Long? = null
    private var ultimaParadaRegistrada: Location? = null
    private var ultimoRegistroParada: Long? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.d(TAG, "Sistema de Foreground iniciado!")
        token = intent?.getStringExtra("token")
        caminhaoID = intent?.getIntExtra("caminhao_id", 0)

        createNotificationChannel()
        startForeground(888, buildNotification())

        fusedLocationClient = LocationServices.getFusedLocationProviderClient(this)
        startLocationUpdates()
        initDatabase()
        startPendingDeliveriesLoop()
        startParadasLoop()
        startAbastecimentosLoop()

        return START_STICKY
    }

    private fun buildNotification(): Notification {
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("RotaOiti ativo")
            .setContentText("Monitorando localização, entregas, paradas e abastecimento")
            .setSmallIcon(R.drawable.ic_service)
            .setOngoing(true)
            .build()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val serviceChannel = NotificationChannel(
                CHANNEL_ID,
                "Rastreamento RotaOiti",
                NotificationManager.IMPORTANCE_DEFAULT
            )
            val manager = getSystemService(NotificationManager::class.java)
            manager?.createNotificationChannel(serviceChannel)
        }
    }

    private fun startLocationUpdates() {
        val locationRequest = LocationRequest.Builder(Priority.PRIORITY_HIGH_ACCURACY, 10000L)
            .setMinUpdateIntervalMillis(5000L)
            .build()

        locationCallback = object : LocationCallback() {
            override fun onLocationResult(locationResult: LocationResult) {
                locationResult.locations.forEach { location ->
                    handleLocation(location)
                }
            }
        }

        try {
            fusedLocationClient.requestLocationUpdates(locationRequest, locationCallback, mainLooper)
        } catch (e: SecurityException) {
            Log.e(TAG, "Permissão de localização não concedida: $e")
        }
    }

    private fun handleLocation(location: Location) {
        sendLocation(location.latitude, location.longitude)
        detectarParada(location)
        ultimaLocalizacao = location
    }

    private fun sendLocation(lat: Double, lng: Double) {
        coroutineScope.launch {
            try {
                val url = java.net.URL(API_URL_LOCALIZACAO)
                val conn = url.openConnection() as java.net.HttpURLConnection
                conn.requestMethod = "POST"
                conn.setRequestProperty("Content-Type", "application/json")
                token?.let { conn.setRequestProperty("Authorization", "Bearer $it") }
                conn.doOutput = true

                val body = JSONObject()
                body.put("latitude", lat)
                body.put("longitude", lng)

                conn.outputStream.use { os -> os.write(body.toString().toByteArray()) }

                val responseCode = conn.responseCode
                if (responseCode !in 200..201) {
                    Log.e(TAG, "Falha ao enviar localização: $responseCode")
                }
                conn.disconnect()
            } catch (e: Exception) {
                Log.e(TAG, "Erro ao enviar localização: $e")
            }
        }
    }

    private fun initDatabase() {
        try {
            val dbPath = File(filesDir.parentFile, "databases/rotaoiti.db")
            db = SQLiteDatabase.openDatabase(dbPath.path, null, SQLiteDatabase.OPEN_READWRITE)
            Log.d(TAG, "DB Flutter aberto com sucesso em: ${dbPath.path}")
        } catch (e: Exception) {
            Log.e(TAG, "Erro ao abrir DB Flutter: $e")
        }
    }

    private fun startPendingDeliveriesLoop() {
        coroutineScope.launch {
            while (isActive) {
                if (isConnectedToInternet() && hasPendingDeliveries()) {
                    enviarEntregasPendentes()
                }
                delay(10000L)
            }
        }
    }

    private fun startParadasLoop() {
        coroutineScope.launch {
            while (isActive) {
                if (isConnectedToInternet()) {
                    enviarParadasPendentes()
                }
                delay(10000L)
            }
        }
    }

    private fun startAbastecimentosLoop() {
        coroutineScope.launch {
            while (isActive) {
                if (isConnectedToInternet()) {
                    enviarAbastecimentosPendentes()
                }
                delay(10000L) // checa a cada 10 segundos
            }
        }
    }

    private fun detectarParada(location: Location) {
        val lat = location.latitude
        val lon = location.longitude

        // Ignora se estiver na madeireira
        if (distanciaMetros(lat, lon, MADEIREIRA_LAT, MADEIREIRA_LON) <= RAIO_MADEIREIRA_METROS) {
            inicioParada = null
            return
        }

        val agora = System.currentTimeMillis()

        if (ultimaLocalizacao != null) {
            val distancia = distanciaMetros(lat, lon, ultimaLocalizacao!!.latitude, ultimaLocalizacao!!.longitude)

            if (distancia < 5.0) { // considerado parado
                if (inicioParada == null) inicioParada = agora
                else if (agora - inicioParada!! >= MIN_PARADA_MILLIS) {

                    // Verifica se está longe da última parada registrada
                    val distanciaUltimaParada: Double = if (ultimaParadaRegistrada != null)
                        distanciaMetros(lat, lon, ultimaParadaRegistrada!!.latitude, ultimaParadaRegistrada!!.longitude)
                    else
                        Double.MAX_VALUE

                    if (distanciaUltimaParada >= 20.0) { // só registra se mudou mais de 10 metros
                        registrarParada(ultimaLocalizacao!!, inicioParada!!, agora)

                        // Salva a posição exata da parada registrada
                        ultimaParadaRegistrada = Location("").apply {
                            latitude = ultimaLocalizacao!!.latitude
                            longitude = ultimaLocalizacao!!.longitude
                        }
                    }

                    inicioParada = null // reinicia contagem
                }
            } else {
                inicioParada = null
            }
        } else {
            inicioParada = agora
        }

        // Atualiza última localização
        ultimaLocalizacao = location
    }

    private fun registrarParada(location: Location, inicio: Long, fim: Long) {
        coroutineScope.launch {
            val dados = JSONObject()
            dados.put("caminhao_id", caminhaoID) 
            dados.put("latitude", location.latitude)
            dados.put("longitude", location.longitude)
            dados.put("inicio_parada", inicio)
            dados.put("fim_parada", fim)

            if (isConnectedToInternet()) {
                try {
                    val request = Request.Builder()
                        .url(API_URL_PARADAS)
                        .addHeader("Authorization", "Bearer $token")
                        .post(MultipartBody.Builder().setType(MultipartBody.FORM)
                            .addFormDataPart("caminhao_id", dados.getInt("caminhao_id").toString())
                            .addFormDataPart("latitude", dados.getDouble("latitude").toString())
                            .addFormDataPart("longitude", dados.getDouble("longitude").toString())
                            .addFormDataPart("inicio_parada", dados.getLong("inicio_parada").toString())
                            .addFormDataPart("fim_parada", dados.getLong("fim_parada").toString())
                            .build()
                        )
                        .build()
                    val response = client.newCall(request).execute()
                    if (!response.isSuccessful) salvarParadaOffline(dados)
                    response.close()
                } catch (e: Exception) {
                    salvarParadaOffline(dados)
                }
            } else {
                salvarParadaOffline(dados)
            }
        }
    }

    private fun salvarParadaOffline(dados: JSONObject) {
        try {
            db?.execSQL(
                "INSERT INTO paradas_offline (caminhao_id, latitude, longitude, inicio_parada, fim_parada, enviado) VALUES (?,?,?,?,?,0)",
                arrayOf(
                    dados.getInt("caminhao_id"),
                    dados.getDouble("latitude"),
                    dados.getDouble("longitude"),
                    dados.getLong("inicio_parada"),
                    dados.getLong("fim_parada")
                )
            )
        } catch (e: Exception) {
            Log.e(TAG, "Erro ao salvar parada offline: $e")
        }
    }

    private suspend fun enviarParadasPendentes() {
        if (db == null || token.isNullOrEmpty()) return
        val cursor = db!!.rawQuery("SELECT * FROM paradas_offline WHERE enviado = 0", null)
        while (cursor.moveToNext()) {
            val id = cursor.getInt(cursor.getColumnIndexOrThrow("id"))
            val caminhaoId = cursor.getInt(cursor.getColumnIndexOrThrow("caminhao_id"))
            val lat = cursor.getDouble(cursor.getColumnIndexOrThrow("latitude"))
            val lon = cursor.getDouble(cursor.getColumnIndexOrThrow("longitude"))
            val inicio = cursor.getLong(cursor.getColumnIndexOrThrow("inicio_parada"))
            val fim = cursor.getLong(cursor.getColumnIndexOrThrow("fim_parada"))

            try {
                val request = Request.Builder()
                    .url(API_URL_PARADAS)
                    .addHeader("Authorization", "Bearer $token")
                    .post(MultipartBody.Builder().setType(MultipartBody.FORM)
                        .addFormDataPart("caminhao_id", caminhaoId.toString())
                        .addFormDataPart("latitude", lat.toString())
                        .addFormDataPart("longitude", lon.toString())
                        .addFormDataPart("inicio_parada", inicio.toString())
                        .addFormDataPart("fim_parada", fim.toString())
                        .build()
                    )
                    .build()
                val response = client.newCall(request).execute()
                if (response.isSuccessful) {
                    db!!.execSQL("UPDATE paradas_offline SET enviado = 1 WHERE id = ?", arrayOf(id))
                }
                response.close()
            } catch (e: Exception) {
                Log.e(TAG, "Falha ao enviar parada offline: $e")
            }
        }
        cursor.close()
    }

    // Função auxiliar de distância em metros
    private fun distanciaMetros(lat1: Double, lon1: Double, lat2: Double, lon2: Double): Double {
        val R = 6371000.0 // raio da Terra em metros
        val dLat = Math.toRadians(lat2 - lat1)
        val dLon = Math.toRadians(lon2 - lon1)
        val a = Math.sin(dLat / 2) * Math.sin(dLat / 2) +
                Math.cos(Math.toRadians(lat1)) * Math.cos(Math.toRadians(lat2)) *
                Math.sin(dLon / 2) * Math.sin(dLon / 2)
        val c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a))
        return R * c
    }

    private suspend fun enviarAbastecimentosPendentes() {
        if (db == null || token.isNullOrEmpty()) return

        val cursor = db!!.rawQuery(
            "SELECT * FROM abastecimentos_offline WHERE enviado = 0 AND (enviando IS NULL OR enviando = 0)",
            null
        )

        while (cursor.moveToNext()) {
            val id = cursor.getInt(cursor.getColumnIndexOrThrow("id"))
            val caminhaoId = cursor.getInt(cursor.getColumnIndexOrThrow("caminhao_id"))
            val departamento = cursor.getString(cursor.getColumnIndexOrThrow("departamento")) ?: ""
            val motorista = cursor.getString(cursor.getColumnIndexOrThrow("motorista")) ?: ""
            val combustivel = cursor.getString(cursor.getColumnIndexOrThrow("combustivel")) ?: ""
            val litros = cursor.getString(cursor.getColumnIndexOrThrow("litros")) ?: "0"
            val valorLitro = cursor.getString(cursor.getColumnIndexOrThrow("valor_litro")) ?: "0"
            val valorTotal = cursor.getString(cursor.getColumnIndexOrThrow("valor_total")) ?: "0"
            val odometro = cursor.getString(cursor.getColumnIndexOrThrow("odometro")) ?: "0"
            val posto = cursor.getString(cursor.getColumnIndexOrThrow("posto")) ?: ""
            val dataHora = cursor.getString(cursor.getColumnIndexOrThrow("data_hora")) ?: ""
            val latitude = cursor.getString(cursor.getColumnIndexOrThrow("latitude")) ?: ""
            val longitude = cursor.getString(cursor.getColumnIndexOrThrow("longitude")) ?: ""
            val obs = cursor.getString(cursor.getColumnIndexOrThrow("obs")) ?: ""

            // Fotos
            val fotoPlaca = cursor.getString(cursor.getColumnIndexOrThrow("foto_placa")) ?: ""
            val fotoBomba = cursor.getString(cursor.getColumnIndexOrThrow("foto_bomba")) ?: ""
            val fotoOdometro = cursor.getString(cursor.getColumnIndexOrThrow("foto_odometro")) ?: ""
            val fotoMarcador = cursor.getString(cursor.getColumnIndexOrThrow("foto_marcador_combustivel")) ?: ""
            val fotoTalao = cursor.getString(cursor.getColumnIndexOrThrow("foto_talao")) ?: ""
            val fotoCupom = cursor.getString(cursor.getColumnIndexOrThrow("foto_cupom")) ?: ""

            val nomesFotos = listOf(
                "foto_placa",
                "foto_bomba",
                "foto_odometro",
                "foto_marcador_combustivel",
                "foto_talao",
                "foto_cupom"
            )

            val fotos = listOf(fotoPlaca, fotoBomba, fotoOdometro, fotoMarcador, fotoTalao, fotoCupom)

            // Marca como enviando
            db!!.execSQL("UPDATE abastecimentos_offline SET enviando = 1 WHERE id = ?", arrayOf(id))

            try {
                val multipartBuilder = MultipartBody.Builder().setType(MultipartBody.FORM)
                multipartBuilder.addFormDataPart("caminhao_id", caminhaoId.toString())
                multipartBuilder.addFormDataPart("departamento", departamento)
                multipartBuilder.addFormDataPart("motorista", motorista)
                multipartBuilder.addFormDataPart("combustivel", combustivel)
                multipartBuilder.addFormDataPart("litros", litros)
                multipartBuilder.addFormDataPart("valor_litro", valorLitro)
                multipartBuilder.addFormDataPart("valor_total", valorLitro)
                multipartBuilder.addFormDataPart("odometro", odometro)
                multipartBuilder.addFormDataPart("posto", posto)
                multipartBuilder.addFormDataPart("data_hora", dataHora)
                multipartBuilder.addFormDataPart("latitude", latitude)
                multipartBuilder.addFormDataPart("longitude", longitude)
                multipartBuilder.addFormDataPart("obs", obs)

                // Adiciona as fotos, somente se o arquivo existir
                fotos.forEachIndexed { index, path ->
                    val file = File(path)
                    if (file.exists()) {
                        multipartBuilder.addFormDataPart(
                            nomesFotos[index],
                            file.name,
                            file.asRequestBody("image/jpeg".toMediaTypeOrNull())
                        )
                    }
                }

                val request = Request.Builder()
                    .url(API_URL_ABASTECIMENTO)
                    .addHeader("Authorization", "Bearer $token")
                    .post(multipartBuilder.build())
                    .build()

                val response = client.newCall(request).execute()
                if (response.isSuccessful) {
                    // Remove do offline
                    db!!.execSQL("DELETE FROM abastecimentos_offline WHERE id = ?", arrayOf(id))
                } else {
                    // Marca como não enviando
                    db!!.execSQL("UPDATE abastecimentos_offline SET enviando = 0 WHERE id = ?", arrayOf(id))
                }
                response.close()
            } catch (e: Exception) {
                Log.e(TAG, "Falha ao enviar abastecimento offline: $e")
                db!!.execSQL("UPDATE abastecimentos_offline SET enviando = 0 WHERE id = ?", arrayOf(id))
            }
        }
        cursor.close()
    }

    private fun isConnectedToInternet(): Boolean {
        val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val nc = cm.getNetworkCapabilities(cm.activeNetwork)
            nc != null && (nc.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)
                    || nc.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR)
                    || nc.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET))
        } else {
            @Suppress("DEPRECATION")
            val netInfo = cm.activeNetworkInfo
            netInfo != null && netInfo.isConnected
        }
    }

    // ---------------- Entregas ----------------
    private fun hasPendingDeliveries(): Boolean {
        val cursor = db?.rawQuery(
            "SELECT * FROM entregas_offline WHERE enviado = 0 AND (enviando IS NULL OR enviando = 0) AND (status = 'concluida' OR status = 'parcial')",
            null
        )
        val hasPending = cursor?.moveToFirst() == true
        cursor?.close()
        return hasPending
    }

    private suspend fun enviarEntregasPendentes() {
        if (db == null || token.isNullOrEmpty()) return
        val cursor = db!!.rawQuery(
            "SELECT * FROM entregas_offline WHERE enviado = 0 AND (enviando IS NULL OR enviando = 0) AND (status = 'concluida' OR status = 'parcial')",
            null
        )
        while (cursor.moveToNext()) {
            val entregaId = cursor.getInt(cursor.getColumnIndexOrThrow("entrega_id"))
            val obs = cursor.getString(cursor.getColumnIndexOrThrow("obs")) ?: ""
            val latitude = cursor.getString(cursor.getColumnIndexOrThrow("latitude")) ?: ""
            val longitude = cursor.getString(cursor.getColumnIndexOrThrow("longitude")) ?: ""
            val fotosStr = cursor.getString(cursor.getColumnIndexOrThrow("fotos")) ?: ""
            val status = cursor.getString(cursor.getColumnIndexOrThrow("status")) ?: "parcial"

            val fotos = try {
                val arr = JSONObject("{\"fotos\":$fotosStr}").getJSONArray("fotos")
                (0 until arr.length()).map { arr.getString(it) }
            } catch (e: Exception) {
                emptyList<String>()
            }

            db!!.execSQL("UPDATE entregas_offline SET enviando = 1 WHERE entrega_id = ?", arrayOf(entregaId))

            try {
                val multipartBuilder = MultipartBody.Builder().setType(MultipartBody.FORM)
                multipartBuilder.addFormDataPart("latitude", latitude)
                multipartBuilder.addFormDataPart("longitude", longitude)
                multipartBuilder.addFormDataPart("obs", obs)
                multipartBuilder.addFormDataPart("status", status)

                fotos.forEachIndexed { index, path ->
                    val file = File(path)
                    if (file.exists()) {
                        multipartBuilder.addFormDataPart(
                            "fotos[$index]",
                            file.name,
                            file.asRequestBody("image/jpeg".toMediaTypeOrNull())
                        )
                    }
                }

                val request = Request.Builder()
                    .url("$API_URL_ENTREGAS/$entregaId/concluir")
                    .addHeader("Authorization", "Bearer $token")
                    .post(multipartBuilder.build())
                    .build()

                val response = client.newCall(request).execute()
                if (response.isSuccessful) {
                    db!!.execSQL("DELETE FROM entregas_offline WHERE entrega_id = ?", arrayOf(entregaId))
                } else {
                    db!!.execSQL("UPDATE entregas_offline SET enviando = 0 WHERE entrega_id = ?", arrayOf(entregaId))
                }
                response.close()
            } catch (e: Exception) {
                db!!.execSQL("UPDATE entregas_offline SET enviando = 0 WHERE entrega_id = ?", arrayOf(entregaId))
            }
        }
        cursor.close()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        super.onDestroy()
        fusedLocationClient.removeLocationUpdates(locationCallback)
        coroutineScope.cancel()
        db?.close()
        Log.d(TAG, "Serviço destruído")
    }
}
