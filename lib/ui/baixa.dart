import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:rotaoitimobile/class/classgerais.dart';
import 'package:rotaoitimobile/db/auth_service.dart';
import 'package:rotaoitimobile/db/db_helper.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

class BaixaEntregaPage extends StatefulWidget {
  final Entrega entrega;
  const BaixaEntregaPage({super.key, required this.entrega});

  @override
  State<BaixaEntregaPage> createState() => _BaixaEntregaPageState();
}

class _BaixaEntregaPageState extends State<BaixaEntregaPage> {
  final DBHelper _dbHelper = DBHelper();
  final AuthService _authService = AuthService();
  final TextEditingController obsController = TextEditingController();

  List<File> fotos = [];
  Position? posicao;
  bool loading = false;
  static const int maxFotos = 5;
  String? statusSelecionado;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    obsController.dispose();
    super.dispose();
  }

  Future<bool> _enviarEntregaOffline(Map<String, dynamic> entrega) async {
    final usuario = await _dbHelper.buscarUsuarioLogado();
    if (usuario == null) throw Exception("Usuário não logado");

    final token = usuario["token"];
    final uri = Uri.parse(
        "${_authService.apiUrl}/api/entregas/${entrega['entrega_id']}/concluir");

    var request = http.MultipartRequest("POST", uri);

    request.fields["status"] = entrega["status"] ?? "concluida";
    request.fields["latitude"] = entrega["latitude"] ?? '';
    request.fields["longitude"] = entrega["longitude"] ?? '';
    request.fields["obs"] = entrega["obs"] ?? '';

    for (var f in (entrega["fotos"] as List<String>)) {
      if (f.isNotEmpty) {
        try {
          request.files.add(await http.MultipartFile.fromPath('fotos[]', f));
        } catch (_) {}
      }
    }

    request.headers['Authorization'] = 'Bearer $token';

    try {
      final streamedResponse = await request
          .send()
          .timeout(const Duration(seconds: 30), onTimeout: () {
        throw TimeoutException("Servidor demorou para responder");
      });

      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        return true; // ✅ enviado com sucesso
      } else {
        await _dbHelper.salvarEntregaOffline(entrega);
        return false; // ❌ falhou
      }
    } on TimeoutException {
      await _dbHelper.salvarEntregaOffline(entrega);
      return false;
    } catch (_) {
      await _dbHelper.salvarEntregaOffline(entrega);
      return false;
    }
  }

  // --- Permissões ---
  Future<bool> solicitarPermissoes() async {
    if (!await Permission.camera.isGranted) {
      var status = await Permission.camera.request();
      if (!status.isGranted) return false;
    }

    if (!await Permission.locationWhenInUse.isGranted) {
      var status = await Permission.locationWhenInUse.request();
      if (!status.isGranted) return false;
    }

    return true;
  }

  Future<void> tirarFoto() async {
    if (fotos.length >= maxFotos) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Máximo de $maxFotos fotos permitido.")),
        );
      }
      return;
    }

    bool permissoes = await solicitarPermissoes();
    if (!permissoes) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Permissões de câmera e localização são necessárias.")),
        );
      }
      return;
    }

    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.camera, imageQuality: 70);

    if (picked != null && mounted) {
      setState(() => fotos.add(File(picked.path)));
    }
  }

  Future<void> pegarLocalizacao() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Ative o GPS para concluir a entrega")),
        );
      }
      return;
    }
    //posicao = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
    posicao = await Geolocator.getCurrentPosition(locationSettings: LocationSettings(accuracy: LocationAccuracy.best,),
);
  }

  // --- Concluir entrega ---
  Future<void> concluirEntrega() async {
    if (loading || !mounted) return;
    setState(() => loading = true);

    try {
      // --- Validações ---
      if (statusSelecionado == null) {
        throw Exception("Escolha o status da entrega (Concluída ou Parcial).");
      }

      if (fotos.isEmpty) {
        throw Exception("Tire pelo menos uma foto para concluir a entrega.");
      }

      if (obsController.text.isEmpty) {
        throw Exception("Coloque uma observação.");
      }

      await pegarLocalizacao();
      if (posicao == null) {
        throw Exception("Não foi possível obter a localização.");
      }

      // --- Monta entrega ---
      final entregaMap = {
        "entrega_id": widget.entrega.id,
        "numero_pedido": widget.entrega.nrEntrega,
        "cliente": widget.entrega.cliente,
        "endereco": widget.entrega.endereco,
        "bairro": widget.entrega.bairro,
        "cidade": widget.entrega.cidade,
        "estado": widget.entrega.estado,
        "telefone": widget.entrega.telefone,
        "vendedor": widget.entrega.vendedor,
        "status": statusSelecionado,
        "obs": obsController.text,
        "latitude": posicao!.latitude.toString(),
        "longitude": posicao!.longitude.toString(),
        "fotos": fotos.map((f) => f.path).toList(),
        "enviado": 0,
        "enviando": 0,
      };

      // --- Verifica conexão ---
      var connectivity = await Connectivity().checkConnectivity();
      if (connectivity == ConnectivityResult.none) {
        // ✅ Offline → guarda no cache
        await _dbHelper.salvarEntregaOffline(entregaMap);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Sem internet. Entrega salva offline."),
              backgroundColor: Colors.orange,
            ),
          );
        }
      } else {
        // 🌐 Online → tenta enviar
        await _dbHelper.marcarEntregaEnviando(widget.entrega.id);

        try {
          await _enviarEntregaOffline(entregaMap);
          await _dbHelper.marcarEntregaEnviada(widget.entrega.id);

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text("Entrega concluída com sucesso!"),
                backgroundColor: Colors.green,
              ),
            );
          }
        } catch (e) {
          // ❌ Falhou envio → salva offline
          await _dbHelper.salvarEntregaOffline(entregaMap);

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text("Erro ao enviar, salva offline: $e"),
                backgroundColor: Colors.orange,
              ),
            );
          }
        }
      }

      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString()),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Entrega #${widget.entrega.nrEntrega}"),
        backgroundColor: AppColors.verdeEscuro,
      ),
      body: AbsorbPointer(
        absorbing: loading,
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [AppColors.begeMadeira, AppColors.begeClaro],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
          child: SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // --- Card da entrega ---
                        Card(
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          elevation: 4,
                          color: Colors.white.withValues(alpha: 0.99),
                          margin: const EdgeInsets.only(bottom: 16),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(widget.entrega.cliente, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
                                const SizedBox(height: 8),
                                Text("Número do pedido: ${widget.entrega.nrEntrega}"),
                                Text("Endereço: ${widget.entrega.endereco}, ${widget.entrega.bairro}"),
                                Text("Cidade: ${widget.entrega.cidade} - ${widget.entrega.estado}"),
                                Text("Telefone: ${widget.entrega.telefone}"),
                                Text("Vendedor: ${widget.entrega.vendedor}"),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    const Text("Status: ", style: TextStyle(fontWeight: FontWeight.bold)),
                                    Chip(
                                      label: Text(widget.entrega.status),
                                      backgroundColor: widget.entrega.status == "pendente"
                                          ? Colors.orange[200]
                                          : widget.entrega.status == "parcial"
                                              ? Colors.blue[200]
                                              : Colors.green[200],
                                    )
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),

                        // --- Observação ---
                        const Text("Observação:", style: TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        TextField(
                          controller: obsController,
                          maxLines: 3,
                          decoration: InputDecoration(
                            hintText: "Digite uma observação",
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            fillColor: Colors.white.withValues(alpha: 0.9),
                            filled: true,
                          ),
                        ),

                        const SizedBox(height: 16),

                        // --- Fotos ---
                        const Text("Fotos da Entrega:", style: TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        SizedBox(
                          height: 120,
                          child: ListView.builder(
                            scrollDirection: Axis.horizontal,
                            itemCount: fotos.length + 1,
                            itemBuilder: (context, index) {
                              if (index == fotos.length) {
                                return GestureDetector(
                                  onTap: tirarFoto,
                                  child: Container(
                                    width: 120,
                                    margin: const EdgeInsets.only(right: 8),
                                    decoration: BoxDecoration(
                                      color: AppColors.verdeNatural.withValues(alpha: 0.6),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: const Center(
                                      child: Icon(Icons.camera_alt, size: 40, color: Colors.white),
                                    ),
                                  ),
                                );
                              }
                              return Stack(
                                children: [
                                  Container(
                                    width: 120,
                                    margin: const EdgeInsets.only(right: 8),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(12),
                                      child: Image.file(fotos[index], fit: BoxFit.cover),
                                    ),
                                  ),
                                  Positioned(
                                    top: 4,
                                    right: 4,
                                    child: GestureDetector(
                                      onTap: () => setState(() => fotos.removeAt(index)),
                                      child: const CircleAvatar(
                                        radius: 12,
                                        backgroundColor: Colors.red,
                                        child: Icon(Icons.close, size: 16, color: Colors.white),
                                      ),
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                        ),
                        // Status
                        const SizedBox(height: 16),
                        const Text("Status da Entrega:", 
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)
                        ),
                        const SizedBox(height: 8),

                        Row(
                          children: [
                            Expanded(
                              child: GestureDetector(
                                onTap: () => setState(() => statusSelecionado = "concluida"),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(vertical: 20),
                                  decoration: BoxDecoration(
                                    color: statusSelecionado == "concluida"
                                        ? Colors.green[600]
                                        : Colors.green[200],
                                    borderRadius: BorderRadius.circular(12),
                                    boxShadow: [
                                      if (statusSelecionado == "concluida")
                                        const BoxShadow(color: Colors.black26, blurRadius: 6, offset: Offset(0, 3)),
                                    ],
                                  ),
                                  child: Column(
                                    children: const [
                                      Icon(Icons.check_circle, size: 32, color: Colors.white),
                                      SizedBox(height: 8),
                                      Text("Concluída", 
                                        style: TextStyle(
                                          color: Colors.white, 
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: GestureDetector(
                                onTap: () => setState(() => statusSelecionado = "parcial"),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(vertical: 20),
                                  decoration: BoxDecoration(
                                    color: statusSelecionado == "parcial"
                                        ? Colors.blue[600]
                                        : Colors.blue[200],
                                    borderRadius: BorderRadius.circular(12),
                                    boxShadow: [
                                      if (statusSelecionado == "parcial")
                                        const BoxShadow(color: Colors.black26, blurRadius: 6, offset: Offset(0, 3)),
                                    ],
                                  ),
                                  child: Column(
                                    children: const [
                                      Icon(Icons.hourglass_bottom, size: 32, color: Colors.white),
                                      SizedBox(height: 8),
                                      Text("Parcial", 
                                        style: TextStyle(
                                          color: Colors.white, 
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),

                        
                      ],
                    ),
                  ),
                ),

                // --- Botão concluir ---
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: concluirEntrega,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        backgroundColor: AppColors.verdeEscuro,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: loading
                          ? const SizedBox(
                              height: 24,
                              width: 24,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                            )
                          : const Text("Concluir Entrega", style: TextStyle(fontSize: 18, color: Colors.white)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
