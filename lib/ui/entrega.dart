import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:rotaoitimobile/class/classgerais.dart';
import 'package:rotaoitimobile/db/auth_service.dart';
import 'package:rotaoitimobile/db/db_helper.dart';
import 'package:rotaoitimobile/ui/baixa.dart';
import 'package:http/http.dart' as http;

class EntregasPage extends StatefulWidget {
  final int caminhaoId;
  const EntregasPage({super.key, required this.caminhaoId});

  @override
  State<EntregasPage> createState() => _EntregasPageState();
}

class _EntregasPageState extends State<EntregasPage> {
  final DBHelper _dbHelper = DBHelper();
  final AuthService _authService = AuthService();

  List<Entrega> entregas = [];
  bool loading = true;
  bool _isCarregando = false;
  bool gpsAtivo = false;
  late final Connectivity _connectivity;
  StreamSubscription<ConnectivityResult>? _connectivitySubscription;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _connectivity = Connectivity();
    _init();

    // ⏱️ Atualiza lista de entregas a cada 30s
    _timer = Timer.periodic(const Duration(seconds: 30), (timer) async {
      if (!mounted || _isCarregando) return;
      await _carregarEntregas(silent: true);
    });
  }

  @override
  void dispose() {
    _connectivitySubscription?.cancel();
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _init() async {
    await _verificarGPS();
    await _carregarEntregas();
  }

  Future<void> _verificarGPS() async {
    bool servicoAtivo = await Geolocator.isLocationServiceEnabled();
    LocationPermission permissao = await Geolocator.checkPermission();
    if (permissao == LocationPermission.denied) {
      permissao = await Geolocator.requestPermission();
    }
    if (!mounted) return;
    setState(() {
      gpsAtivo = servicoAtivo &&
          (permissao == LocationPermission.always ||
              permissao == LocationPermission.whileInUse);
    });
  }

  Future<void> _carregarEntregas({bool silent = false}) async {
    if (_isCarregando) return; // Evita chamadas simultâneas
    _isCarregando = true;

    if (!silent && mounted) setState(() => loading = true);

    Future<void> carregarCache() async {
      List<Entrega> locais = await _dbHelper.buscarTodasEntregas();
      if (!mounted) return;
      setState(() {
        entregas = locais.where((e) => e.status == 'pendente' || e.status == 'parcial').toList();
      });
      if (!silent && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Não foi possível carregar do servidor. Mostrando dados locais."),
            backgroundColor: Colors.orange,
          ),
        );
      }
    }

    try {
      var connectivity = await _connectivity.checkConnectivity();

      if (connectivity == ConnectivityResult.none) {
        // Sem internet, usa cache
        await carregarCache();
        return;
      }

      final usuario = await _dbHelper.buscarUsuarioLogado();
      if (usuario == null) {
        await carregarCache();
        return;
      }

      final token = usuario['token'] ?? '';
      final uri = Uri.parse("${_authService.apiUrl}/api/caminhoes/${widget.caminhaoId}/entregas");

      final response = await http
          .get(uri, headers: {
            "Content-Type": "application/json",
            "Authorization": "Bearer $token",
          })
          .timeout(const Duration(seconds: 15)); // ⏱ Timeout de 15s

      if (response.statusCode == 200) {
        final Map<String, dynamic> jsonData = jsonDecode(response.body);
        final data = jsonData['data'];
        final lista = (data is List) ? data : [];

        List<Map<String, dynamic>> pendentesParaDB = [];
        List<Entrega> online = [];

        for (var e in lista) {
          final entrega = Entrega.fromJson(e);
          if (entrega.status == "pendente" || entrega.status == "parcial") {
            online.add(entrega);
            pendentesParaDB.add({
              "entrega_id": entrega.id,
              "numero_pedido": entrega.nrEntrega,
              "cliente": entrega.cliente,
              "endereco": entrega.endereco,
              "bairro": entrega.bairro,
              "cidade": entrega.cidade,
              "estado": entrega.estado,
              "telefone": entrega.telefone,
              "status": entrega.status,
              "vendedor": entrega.vendedor,
              "obs": entrega.obs ?? '',
              "latitude": entrega.latitude ?? '',
              "longitude": entrega.longitude ?? '',
              "fotos": jsonEncode(entrega.fotos),
              "enviado": 0,
              "enviando": 0,
            });
          }
        }

        await _dbHelper.salvarEntregasPendentes(pendentesParaDB, replace: true);

        if (mounted) {
          setState(() => entregas = online);
        }
      } else {
        // API respondeu, mas não OK -> fallback para cache
        await carregarCache();
      }
    } on TimeoutException {
      // Timeout -> fallback para cache
      await carregarCache();
    } catch (e) {
      // Qualquer outro erro -> fallback para cache
      await carregarCache();
      if (!silent && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Erro ao carregar entregas: $e"),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      _isCarregando = false;
      if (!silent && mounted) setState(() => loading = false);
    }
  }

  Future<void> _enviarEntregasPendentes() async {
    final connectivity = await _connectivity.checkConnectivity();
    if (connectivity == ConnectivityResult.none) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Sem internet para fazer envio!"),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final pendentes = await _dbHelper.buscarEntregasOffline();
    if (pendentes.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Sem entregas pendentes para envio!"),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // Mostra loading
    showDialog(
      // ignore: use_build_context_synchronously
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    int sucesso = 0;
    int falha = 0;

    for (var e in pendentes) {
      await _dbHelper.marcarEntregaEnviando(e.id);
      try {
        await _enviarEntregaOffline(e);
        sucesso++;
      } catch (_) {
        await _dbHelper.marcarEntregaFalha(e.id);
        falha++;
      }
    }

    if (mounted) Navigator.pop(context); // Fecha o loading

    // Atualiza UI
    await _carregarEntregas();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("Entregas enviadas: $sucesso | Falharam: $falha"),
        backgroundColor: falha > 0 ? Colors.orange : Colors.green,
      ),
    );
  }

  Future<void> _enviarEntregaOffline(Entrega e) async {
    final usuario = await _dbHelper.buscarUsuarioLogado();
    if (usuario == null) return;
    final token = usuario["token"];
    if (token == null || token.isEmpty) return;

    var uri = Uri.parse("${_authService.apiUrl}/api/entregas/${e.id}/concluir");
    var request = http.MultipartRequest("POST", uri);

    request.fields["latitude"] = e.latitude ?? '';
    request.fields["longitude"] = e.longitude ?? '';
    request.fields["obs"] = e.obs ?? '';

    if (e.fotos.isNotEmpty) {
      for (int i = 0; i < e.fotos.length; i++) {
        var path = e.fotos[i];
        request.files.add(await http.MultipartFile.fromPath('fotos[$i]', path));
      }
    }

    request.headers['Authorization'] = 'Bearer $token';
    request.headers['Content-Type'] = 'multipart/form-data';

    try {
      var response = await request.send();
      if (response.statusCode == 200) {
        await _dbHelper.deletarEntregaOffline(e.id);
      } else {
        await _dbHelper.marcarEntregaFalha(e.id);
      }
    } catch (err) {
      await _dbHelper.marcarEntregaFalha(e.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Minhas Entregas"),
        backgroundColor: AppColors.verdeEscuro,
        actions: [
          IconButton(
            icon: const Icon(Icons.download),
            tooltip: "Baixar entregas offline",
            onPressed: _carregarEntregas,
          ),
          IconButton(
            icon: const Icon(Icons.upload),
            tooltip: "Enviar entregas pendentes",
            onPressed: _enviarEntregasPendentes,
          ),
        ],
      ),
      backgroundColor: AppColors.begeClaro,
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : entregas.isEmpty
              ? Center(
                  child: Text(
                    "Nenhuma entrega pendente!",
                    style: TextStyle(fontSize: 18, color: AppColors.marromEscuro),
                  ),
                )
              : _buildListaEntregas(),
    );
  }

  Widget _buildListaEntregas() {
    return FutureBuilder<List<Entrega>>(
      future: _dbHelper.buscarEntregasOffline(),
      builder: (context, snapshot) {
        final pendentes = snapshot.data ?? [];

        return Column(
          children: [
            if (pendentes.isNotEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.cloud_upload),
                  label: const Text("Entregas Pendentes de Envio"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.verdeEscuro,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    textStyle: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  onPressed: () {
                    Navigator.pushNamed(context, '/pendentes');
                  },
                ),
              ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: entregas.length,
                itemBuilder: (context, index) {
                  final entrega = entregas[index];
                  return Card(
                    color: Colors.white.withValues(alpha: 0.9),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    margin: const EdgeInsets.symmetric(vertical: 8),
                    child: ListTile(
                      contentPadding: const EdgeInsets.all(16),
                      title: Text(
                          "#${entrega.nrEntrega} - ${entrega.cliente}",
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 18)),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 4),
                          Text("Endereço: ${entrega.endereco}, ${entrega.bairro}"),
                          Text("Cidade: ${entrega.cidade} - ${entrega.estado}"),
                          Text("Telefone: ${entrega.telefone}"),
                          Text("Vendedor: ${entrega.vendedor}"),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              const Text("Status: ",
                                  style:
                                      TextStyle(fontWeight: FontWeight.bold)),
                              Text(
                                entrega.status,
                                style: TextStyle(
                                  color: entrega.status == "pendente"
                                      ? Colors.orange
                                      : entrega.status == "parcial"
                                          ? Colors.blue
                                          : Colors.green,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      trailing: Icon(
                        entrega.status == "pendente"
                            ? Icons.pending
                            : entrega.status == "parcial"
                                ? Icons.hourglass_bottom
                                : Icons.check,
                        color: entrega.status == "pendente"
                            ? Colors.orange
                            : entrega.status == "parcial"
                                ? Colors.blue
                                : Colors.green,
                      ),
                      onTap: () async {
                        final result = await Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => BaixaEntregaPage(entrega: entrega)),
                        );
                        if (result == true) {
                          await _carregarEntregas();
                        }
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}
