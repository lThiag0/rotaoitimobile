package com.example.rotaoitimobile

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteDatabaseLockedException
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
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.MediaType.Companion.toMediaType
import org.json.JSONObject
import java.io.File
import java.util.concurrent.TimeUnit
import org.json.JSONArray
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.os.Handler
import android.os.Looper

class LocationForegroundService : Service() {

    private val TAG = "LocationService"
    private val CHANNEL_ID = "rotaoiti_channel"

    private lateinit var fusedLocationClient: FusedLocationProviderClient
    private lateinit var locationCallback: LocationCallback
    
    private var logChannel: MethodChannel? = null

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
    private var paradaLongaMinutos = 10
    private val MIN_DIST_PARADA_METROS = 40f
    private var MIN_PARADA_MILLIS = 10 * 60 * 1000L
    private var garagemLat: Double = 0.0
    private var garagemLon: Double = 0.0
    private val RAIO_GARAGEM_METROS = 100.0

    private var ultimaLocalizacao: Location? = null
    private var inicioParada: Long? = null
    private var ultimaParadaRegistrada: Location? = null
    private var ultimoRegistroParada: Long? = null

    private val bufferDistancias = mutableListOf<Double>()
    private val TAMANHO_BUFFER = 5 // últimas 5 leituras
    private val LIMITE_FLUTUACAO = 8.0 // até 8 metros é variação normal do GPS

    private var lastLocationSentAt = 0L
    private val LOCATION_SEND_INTERVAL = 4000L // 4s para evitar spam (ajuste se quiser)

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        token = intent?.getStringExtra("token")
        caminhaoID = intent?.getIntExtra("caminhao_id", 0)

        paradaLongaMinutos = intent?.getIntExtra("parada_longa_minutos", 10) ?: 10
        garagemLat = intent?.getDoubleExtra("garagem_latitude", 0.0) ?: 0.0
        garagemLon = intent?.getDoubleExtra("garagem_longitude", 0.0) ?: 0.0

        MIN_PARADA_MILLIS = paradaLongaMinutos * 60 * 1000L

        createNotificationChannel()
        startForeground(888, buildNotification())

        fusedLocationClient = LocationServices.getFusedLocationProviderClient(this)
        startLocationUpdates()
        initDatabase()
        startSyncLoop()

        //Log.d(TAG, "Sistema de Foreground iniciado! paradaLongaMinutos: " + paradaLongaMinutos + ", garagemLat: " + garagemLat + ", garagemLon: " + garagemLon);
        sendLogFlutter("Sistema de Foreground iniciado -> paradaLongaMinutos=${paradaLongaMinutos} garagemLat=${garagemLat} garagemLon=${garagemLon}")

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
            //Log.e(TAG, "Permissão de localização não concedida: $e")
            sendLogFlutter("Permissão de localização não concedida: $e")
        }
    }

    private fun handleLocation(location: Location) {
        sendLocation(location.latitude, location.longitude)
        detectarParada(location)
        ultimaLocalizacao = location
    }

    private fun sendLocation(lat: Double, lng: Double) {
        coroutineScope.launch {

            // Evita enviar muitas vezes por segundo (economia de bateria e dados)
            val agora = System.currentTimeMillis()
            if (agora - lastLocationSentAt < LOCATION_SEND_INTERVAL) return@launch
            lastLocationSentAt = agora

            try {
                // Reutiliza um único JSON estático, muito mais leve
                val jsonBody = """{"latitude":$lat,"longitude":$lng}"""
                    .toRequestBody("application/json".toMediaType())

                val request = Request.Builder()
                    .url(API_URL_LOCALIZACAO)
                    .addHeader("Authorization", "Bearer $token")
                    .post(jsonBody)
                    .build()

                val response = client.newCall(request).execute()

                if (!response.isSuccessful) {
                    //Log.e(TAG, "Falha ao enviar localização: ${response.code}")
                    sendLogFlutter("Falha ao enviar localização: ${response.code}")
                }

                response.close()

            } catch (e: Exception) {
                //Log.e(TAG, "Erro ao enviar localização: $e")
                sendLogFlutter("Erro ao enviar localização: $e")
            }
        }
    }

    private fun initDatabase() {
        try {
            val dbFile = getDatabasePath("rotaoiti.db")
            if (dbFile.exists()) {
                db = SQLiteDatabase.openDatabase(dbFile.path, null, SQLiteDatabase.OPEN_READWRITE)
                //Log.d(TAG, "DB aberto em: ${dbFile.path}")
                sendLogFlutter("DB aberto em: ${dbFile.path}")
            } else {
                //Log.w(TAG, "DB rotaoiti.db não encontrado em: ${dbFile.path}")
                sendLogFlutter("DB rotaoiti.db não encontrado em: ${dbFile.path}")
                // opcional: tentar abrir somente leitura ou criar cópia
            }
        } catch (e: Exception) {
            //Log.e(TAG, "Erro ao abrir DB Flutter: $e")
            sendLogFlutter("Erro ao abrir DB Flutter: $e")
        }
    }

    private fun startSyncLoop() {
        coroutineScope.launch {
            while (isActive) {

                if (isConnectedToInternet()) {

                    // envia somente o que existir
                    if (hasPendingDeliveries()) {
                        enviarEntregasPendentes()
                    }

                    enviarParadasPendentes()  // sempre terá pendentes ou não

                    enviarAbastecimentosPendentes() // idem
                }

                delay(10000L)
            }
        }
    }

    private fun estaRealmenteParado(distancia: Double): Boolean {
        bufferDistancias.add(distancia)

        if (bufferDistancias.size > TAMANHO_BUFFER) {
            bufferDistancias.removeAt(0)
        }

        // Se todas as últimas leituras estiverem dentro do limite → parado
        return bufferDistancias.all { it <= LIMITE_FLUTUACAO }
    }

    private fun detectarParada(location: Location) {
        val lat = location.latitude
        val lon = location.longitude
        val agora = System.currentTimeMillis()

        // 0. Ignora localização ruim
        if (location.accuracy > 35) {
            return
        }

        // 1. Ignora dentro da garagem
        val distGaragem = distanciaMetros(lat, lon, garagemLat, garagemLon)
        if (distGaragem <= RAIO_GARAGEM_METROS) {
            inicioParada = agora
            ultimaLocalizacao = location
            bufferDistancias.clear()
            return
        }

        // 2. Sem última localização? define e sai
        val ultima = ultimaLocalizacao
        if (ultima == null) {
            ultimaLocalizacao = location
            inicioParada = agora
            return
        }

        // 3. Distância desde último ponto
        val distanciaMov = distanciaMetros(lat, lon, ultima.latitude, ultima.longitude)

        // 4. Velocidade real
        val velocidade = location.speed  // m/s

        // 5. Estabilidade com buffer
        bufferDistancias.add(distanciaMov)
        if (bufferDistancias.size > 6) bufferDistancias.removeAt(0)

        val bufferOk = bufferDistancias.all { it < 5 } // tolerância maior
        val paradoPorVelocidade = velocidade < 0.35f   // mais estável que 0.4

        val paradoEstavel = bufferOk && paradoPorVelocidade

        // 6. Parado realmente
        if (paradoEstavel) {

            if (inicioParada == null) {
                inicioParada = agora
                ultimaParadaRegistrada = location
                return
            }

            val tempoParado = agora - inicioParada!!

            if (tempoParado >= MIN_PARADA_MILLIS) {

                val distanciaUltimaParada = ultimaParadaRegistrada?.let {
                    distanciaMetros(lat, lon, it.latitude, it.longitude)
                } ?: Double.MAX_VALUE

                // REGISTRA PARADA
                registrarParada(location, inicioParada!!, agora)

                // Atualização segura da última parada
                if (distanciaUltimaParada > 20.0) {
                    ultimaParadaRegistrada = Location("").apply {
                        latitude = lat
                        longitude = lon
                    }
                }

                // Reinicia apenas o relógio, mantém estabilidade
                inicioParada = agora
            }

        } else {
            // Movimento real → reset suave
            inicioParada = agora
            bufferDistancias.clear()
        }

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

        } catch (e: SQLiteDatabaseLockedException) {
            // retry após 200ms
            Thread.sleep(200)
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
            } catch (e2: Exception) {
                //Log.e(TAG, "Falha mesmo após retry: $e2")
                sendLogFlutter("Falha mesmo após retry: $e2")
            }

        } catch (e: Exception) {
            //Log.e(TAG, "Erro ao salvar parada offline: $e")
            sendLogFlutter("Erro ao salvar parada offline: $e")
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
                //Log.e(TAG, "Falha ao enviar parada offline: $e")
                sendLogFlutter("Falha ao enviar parada offline: $e")
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
        val dbLocal = db ?: return
        if (token.isNullOrEmpty()) return

        val cursor = dbLocal.rawQuery(
            "SELECT * FROM abastecimentos_offline WHERE enviado = 0 AND (enviando IS NULL OR enviando = 0)",
            null
        )

        cursor.use {
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
                val nomesFotos = listOf(
                    "foto_placa",
                    "foto_bomba",
                    "foto_odometro",
                    "foto_marcador_combustivel",
                    "foto_talao",
                    "foto_cupom"
                )

                val fotos = nomesFotos.map { nome ->
                    cursor.getString(cursor.getColumnIndexOrThrow(nome)) ?: ""
                }

                // Marca como enviando
                dbLocal.execSQL(
                    "UPDATE abastecimentos_offline SET enviando = 1 WHERE id = ?",
                    arrayOf(id)
                )

                runCatching {

                    val multipart = MultipartBody.Builder()
                        .setType(MultipartBody.FORM)
                        .apply {
                            addFormDataPart("caminhao_id", caminhaoId.toString())
                            addFormDataPart("departamento", departamento)
                            addFormDataPart("motorista", motorista)
                            addFormDataPart("combustivel", combustivel)
                            addFormDataPart("litros", litros)
                            addFormDataPart("valor_litro", valorLitro)
                            addFormDataPart("valor_total", valorTotal)
                            addFormDataPart("odometro", odometro)
                            addFormDataPart("posto", posto)
                            addFormDataPart("data_hora", dataHora)
                            addFormDataPart("latitude", latitude)
                            addFormDataPart("longitude", longitude)
                            addFormDataPart("obs", obs)

                            // Anexa fotos somente se existir
                            fotos.forEachIndexed { index, path ->
                                val file = File(path)
                                if (path.isNotBlank() && file.exists() && file.length() > 100) {
                                    addFormDataPart(
                                        nomesFotos[index],
                                        file.name,
                                        file.asRequestBody("image/jpeg".toMediaTypeOrNull())
                                    )
                                }
                            }
                        }.build()

                    val request = Request.Builder()
                        .url(API_URL_ABASTECIMENTO)
                        .addHeader("Authorization", "Bearer $token")
                        .post(multipart)
                        .build()

                    client.newCall(request).execute().use { response ->
                        if (response.isSuccessful) {
                            dbLocal.execSQL(
                                "DELETE FROM abastecimentos_offline WHERE id = ?",
                                arrayOf(id)
                            )
                        } else {
                            dbLocal.execSQL(
                                "UPDATE abastecimentos_offline SET enviando = 0 WHERE id = ?",
                                arrayOf(id)
                            )
                        }
                    }

                }.onFailure { e ->
                    //Log.e(TAG, "Falha ao enviar abastecimento offline: $e")
                    sendLogFlutter("Falha ao enviar abastecimento offline: $e")
                    dbLocal.execSQL(
                        "UPDATE abastecimentos_offline SET enviando = 0 WHERE id = ?",
                        arrayOf(id)
                    )
                }
            }
        }
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

    private fun sendLogFlutter(msg: String) {
        MainActivity.sendLog(msg)
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

        val query = """
            SELECT * FROM entregas_offline
            WHERE enviado = 0
            AND (enviando IS NULL OR enviando = 0)
            AND (status = 'concluida' OR status = 'parcial')
        """

        val cursor = db!!.rawQuery(query, null)

        cursor.use { c ->
            while (c.moveToNext()) {

                val entregaId = c.getInt(c.getColumnIndexOrThrow("entrega_id"))
                val obs = c.getString(c.getColumnIndexOrThrow("obs")) ?: ""
                val latitude = c.getString(c.getColumnIndexOrThrow("latitude")) ?: ""
                val longitude = c.getString(c.getColumnIndexOrThrow("longitude")) ?: ""
                val status = c.getString(c.getColumnIndexOrThrow("status")) ?: "parcial"
                val fotosStr = c.getString(c.getColumnIndexOrThrow("fotos")) ?: "[]"

                // ------------ Melhor interpretação das fotos JSON ------------
                val fotos = try {
                    val arr = JSONArray(fotosStr)
                    (0 until arr.length()).map { arr.getString(it) }
                } catch (e: Exception) {
                    //Log.e(TAG, "Erro ao interpretar fotos offline: $e")
                    sendLogFlutter("Erro ao interpretar fotos offline: $e")
                    emptyList<String>()
                }

                // Marca como enviando
                try {
                    db!!.execSQL(
                        "UPDATE entregas_offline SET enviando = 1 WHERE entrega_id = ?",
                        arrayOf(entregaId)
                    )
                } catch (e: Exception) {
                    //Log.e(TAG, "Erro ao atualizar enviando=1: $e")
                    sendLogFlutter("Erro ao atualizar enviando=1: $e")
                    continue
                }

                try {
                    // ---------------- MONTAGEM DO MULTIPART ----------------
                    val multipart = MultipartBody.Builder().setType(MultipartBody.FORM)
                        .addFormDataPart("latitude", latitude)
                        .addFormDataPart("longitude", longitude)
                        .addFormDataPart("obs", obs)
                        .addFormDataPart("status", status)

                    // Adicionar fotos SE existirem
                    fotos.forEachIndexed { index, path ->
                        val file = File(path)
                        if (file.exists()) {
                            multipart.addFormDataPart(
                                "fotos[$index]",
                                file.name,
                                file.asRequestBody("image/jpeg".toMediaTypeOrNull())
                            )
                        }
                    }

                    val request = Request.Builder()
                        .url("$API_URL_ENTREGAS/$entregaId/concluir")
                        .addHeader("Authorization", "Bearer $token")
                        .post(multipart.build())
                        .build()

                    val response = client.newCall(request).execute()

                    if (response.isSuccessful) {
                        db!!.execSQL(
                            "DELETE FROM entregas_offline WHERE entrega_id = ?",
                            arrayOf(entregaId)
                        )
                    } else {
                        db!!.execSQL(
                            "UPDATE entregas_offline SET enviando = 0 WHERE entrega_id = ?",
                            arrayOf(entregaId)
                        )
                    }

                    response.close()

                } catch (e: Exception) {

                    //Log.e(TAG, "Erro ao enviar entrega offline: $e")
                    sendLogFlutter("Erro ao enviar entrega offline: $e")

                    db!!.execSQL(
                        "UPDATE entregas_offline SET enviando = 0 WHERE entrega_id = ?",
                        arrayOf(entregaId)
                    )
                }
            }
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        super.onDestroy()
        fusedLocationClient.removeLocationUpdates(locationCallback)
        coroutineScope.cancel()
        db?.close()
        //Log.d(TAG, "Serviço destruído")
        sendLogFlutter("Serviço destruído")
    }
}
