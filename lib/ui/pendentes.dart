import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:rotaoitimobile/class/classgerais.dart';
import 'package:rotaoitimobile/db/auth_service.dart';
import 'package:rotaoitimobile/db/db_helper.dart';

class EntregasPendentesPage extends StatefulWidget {
  const EntregasPendentesPage({super.key});

  @override
  State<EntregasPendentesPage> createState() => _EntregasPendentesPageState();
}

class _EntregasPendentesPageState extends State<EntregasPendentesPage> {
  final DBHelper _dbHelper = DBHelper();
  final AuthService _authService = AuthService();
  List<Entrega> pendentes = [];
  bool loading = true;
  late final Connectivity _connectivity;
  StreamSubscription<ConnectivityResult>? _connectivitySubscription;

  @override
  void initState() {
    super.initState();
    _carregarPendentes();
    _connectivity = Connectivity();
  }

  @override
  void dispose() {
    _connectivitySubscription?.cancel();
    super.dispose();
  }

  Future<void> _carregarPendentes() async {
    setState(() => loading = true);
    try {
      final lista = await _dbHelper.buscarEntregasOffline();
      if (mounted) {
        setState(() {
          pendentes = lista;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Erro ao carregar: $e"),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _enviarTodasPendentes() async {
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

    for (var e in pendentes) {
      await _dbHelper.marcarEntregaEnviando(e.id);
      try {
        await _enviarEntregaOffline(e);
      } catch (_) {
        await _dbHelper.marcarEntregaFalha(e.id);
      }
    }

    // Atualiza UI
    await _carregarPendentes();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Entregas pendentes enviadas!"),
        backgroundColor: Colors.green,
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
        title: const Text("Pendentes para Envio"),
        backgroundColor: AppColors.verdeEscuro,
      ),
      backgroundColor: AppColors.begeClaro,
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            child: ElevatedButton.icon(
              icon: const Icon(Icons.cloud_upload),
              label: const Text("Enviar Todas"),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.verdeEscuro,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                textStyle: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              onPressed: _enviarTodasPendentes,
            ),
          ),

          // Lista
          Expanded(
            child: loading
                ? const Center(child: CircularProgressIndicator())
                : pendentes.isEmpty
                    ? Center(
                        child: Text(
                          "Nenhuma entrega pendente para envio!",
                          style: TextStyle(
                              fontSize: 18, color: AppColors.marromEscuro),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: pendentes.length,
                        itemBuilder: (context, index) {
                          final entrega = pendentes[index];
                          return Card(
                            color: Colors.white.withValues(alpha: 0.9),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                            margin: const EdgeInsets.symmetric(vertical: 8),
                            child: ListTile(
                              contentPadding: const EdgeInsets.all(16),
                              title: Text("#${entrega.nrEntrega} - ${entrega.cliente}",
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 18)),
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
                                    children: const [
                                      Text("Status: ",
                                          style: TextStyle(
                                              fontWeight: FontWeight.bold)),
                                      Text("Pendente para envio",
                                          style: TextStyle(
                                            color: Colors.red,
                                            fontWeight: FontWeight.bold,
                                          )),
                                    ],
                                  ),
                                ],
                              ),
                              trailing: const Icon(
                                Icons.cloud_upload,
                                color: Colors.red,
                              ),
                              onTap: () async {
                                if (!mounted) return;
                                await _carregarPendentes();
                              },
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
