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

class AbastecimentoPage extends StatefulWidget {
  const AbastecimentoPage({super.key});

  @override
  State<AbastecimentoPage> createState() => _AbastecimentoPageState();
}

class _AbastecimentoPageState extends State<AbastecimentoPage> {
  final DBHelper _dbHelper = DBHelper();
  final AuthService _authService = AuthService();

  Position? posicao;
  bool loading = false;

  final litrosController = TextEditingController();
  final valorController = TextEditingController();
  final valorTotalController = TextEditingController();
  final odometroController = TextEditingController();
  final obsController = TextEditingController();
  final postoController = TextEditingController();

  Caminhao? caminhaoSelecionado;
  String? combustivelSelecionado;
  String? departamentoSelecionado;

  File? fotoPlaca;
  File? fotoBomba;
  File? fotoOdometro;
  File? fotoMarcador;
  File? fotoTalao;
  File? fotoCupom;

  List<Caminhao> listaCaminhoes = [];
  final List<String> listaCombustivel = [
    'Gasolina Comum',
    'Gasolina Aditivada',
    'Etanol (Álcool)',
    'Diesel S10',
    'Diesel S500',
    'GNV',
    'Flex (Gasolina/Etanol)',
    'Óleo Diesel Biodiesel',
    'Biodiesel',
    'GPL (Gás de Petróleo Liquefeito)',
    'GLP (Gás de Cozinha)',
    'Eletricidade',
  ];

  String formatarDataHora(DateTime dt) {
    return "${dt.year.toString().padLeft(4, '0')}-"
        "${dt.month.toString().padLeft(2, '0')}-"
        "${dt.day.toString().padLeft(2, '0')} "
        "${dt.hour.toString().padLeft(2, '0')}:"
        "${dt.minute.toString().padLeft(2, '0')}:"
        "${dt.second.toString().padLeft(2, '0')}";
  }

  @override
  void initState() {
    super.initState();
    carregarCaminhoes();

    litrosController.addListener(atualizarValorTotal);
    valorController.addListener(atualizarValorTotal);
  }

  void atualizarValorTotal() {
    // Pega os valores digitados
    final litrosText = litrosController.text.replaceAll(',', '.');
    final valorText = valorController.text.replaceAll(',', '.');

    // Converte para double
    double litros = double.tryParse(litrosText) ?? 0;
    double valorLitro = double.tryParse(valorText) ?? 0;

    // Calcula o valor total
    double total = litros * valorLitro;

    // Atualiza o campo valorTotalController sem disparar listener
    valorTotalController.value = valorTotalController.value.copyWith(
      text: total.toStringAsFixed(2),
      selection: TextSelection.collapsed(
        offset: total.toStringAsFixed(2).length,
      ),
    );
  }

  Future<void> carregarCaminhoes() async {
    final dados = await DBHelper().buscarCaminhoes();
    listaCaminhoes = dados.map((e) => Caminhao.fromJson(e)).toList();

    final usuario = await _dbHelper.buscarUsuarioLogado();
    if (usuario != null && usuario['caminhao_id'] != null) {
      // Procura o caminhão vinculado do usuário
      final caminhaoVinculado = listaCaminhoes.firstWhere(
        (c) => c.id == usuario['caminhao_id'],
        orElse: () => Caminhao(
          id: 0,
          nome: '',
          placa: '',
          cor: '#FFFFFF',
          departamento: '',
          userId: 0,
        ),
      );

      if (caminhaoVinculado.id != 0) {
        caminhaoSelecionado = caminhaoVinculado;
        departamentoSelecionado = caminhaoVinculado.departamento.isNotEmpty
            ? caminhaoVinculado.departamento
            : caminhaoVinculado.placa;
      }
    }

    setState(() {});
  }

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

  Future<File?> tirarFoto() async {
    bool permissoes = await solicitarPermissoes();
    if (!permissoes) return null;

    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 70,
    );
    if (picked != null) return File(picked.path);
    return null;
  }

  Future<void> pegarLocalizacao() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Ative o GPS para registrar o abastecimento"),
          ),
        );
      }
      return;
    }
    posicao = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.best),
    );
  }

  Future<void> enviarAbastecimento() async {
    final usuario = await _dbHelper.buscarUsuarioLogado();
    if (loading || !mounted) return;
    setState(() => loading = true);

    try {
      if (caminhaoSelecionado == null) throw Exception("Selecione um veículo");
      if (combustivelSelecionado == null) {
        throw Exception("Selecione o tipo de combustível");
      }
      if (litrosController.text.isEmpty) {
        throw Exception("Informe a quantidade de litros");
      }
      if (valorController.text.isEmpty) {
        throw Exception("Informe o valor do litro");
      }
      if (valorTotalController.text.isEmpty) {
        throw Exception("Informe o valor total gasto");
      }
      if (odometroController.text.isEmpty) {
        throw Exception("Informe o odômetro");
      }
      if (postoController.text.isEmpty) throw Exception("Informe o posto");
      if ([
        fotoPlaca,
        fotoBomba,
        fotoOdometro,
        fotoMarcador,
        fotoTalao,
        fotoCupom,
      ].contains(null)) {
        throw Exception("Todas as fotos são obrigatórias");
      }

      await pegarLocalizacao();
      if (posicao == null) {
        throw Exception("Não foi possível obter a localização");
      }

      final data = {
        "caminhao_id": caminhaoSelecionado!.id,
        "combustivel": combustivelSelecionado!,
        "litros": litrosController.text,
        "valor_litro": valorController.text,
        "valor_total": valorTotalController.text,
        "odometro": odometroController.text,
        "departamento": departamentoSelecionado ?? '',
        "motorista": usuario?['nome'] ?? "Motorista",
        "data_hora": formatarDataHora(DateTime.now()),
        "posto": postoController.text,
        "obs": obsController.text,
        "latitude": posicao!.latitude.toStringAsFixed(8),
        "longitude": posicao!.longitude.toStringAsFixed(8),
        "fotos": [
          fotoPlaca!.path,
          fotoBomba!.path,
          fotoOdometro!.path,
          fotoMarcador!.path,
          fotoTalao!.path,
          fotoCupom!.path,
        ],
      };

      var connectivity = await Connectivity().checkConnectivity();
      if (connectivity == ConnectivityResult.none) {
        await _dbHelper.salvarAbastecimentoOffline(data);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Sem internet. Abastecimento salvo offline."),
            backgroundColor: Colors.orange,
          ),
        );
      } else {
        await enviarAbastecimentoOnline(data);
      }

      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> enviarAbastecimentoOnline(Map<String, dynamic> data) async {
    final usuario = await _dbHelper.buscarUsuarioLogado();
    if (usuario == null) throw Exception("Usuário não logado");

    final token = usuario["token"];
    final uri = Uri.parse("${_authService.apiUrl}/api/abastecimentos");

    var request = http.MultipartRequest("POST", uri)
      ..fields.addAll({
        "caminhao_id": data["caminhao_id"].toString(),
        "combustivel": data["combustivel"],
        "litros": data["litros"].toString(),
        "valor_litro": data["valor_litro"].toString(),
        "valor_total": data["valor_total"].toString(),
        "odometro": data["odometro"].toString(),
        "departamento": data["departamento"],
        "motorista": data["motorista"],
        "data_hora": data["data_hora"],
        "posto": data["posto"],
        "obs": data["obs"] ?? "",
        "latitude": data["latitude"].toString(),
        "longitude": data["longitude"].toString(),
      })
      ..headers.addAll({
        "Authorization": "Bearer $token",
        "Accept": "application/json",
      });

    if (fotoPlaca != null) {
      request.files.add(
        await http.MultipartFile.fromPath('foto_placa', fotoPlaca!.path),
      );
    }
    if (fotoBomba != null) {
      request.files.add(
        await http.MultipartFile.fromPath('foto_bomba', fotoBomba!.path),
      );
    }
    if (fotoOdometro != null) {
      request.files.add(
        await http.MultipartFile.fromPath('foto_odometro', fotoOdometro!.path),
      );
    }
    if (fotoMarcador != null) {
      request.files.add(
        await http.MultipartFile.fromPath(
          'foto_marcador_combustivel',
          fotoMarcador!.path,
        ),
      );
    }
    if (fotoTalao != null) {
      request.files.add(
        await http.MultipartFile.fromPath('foto_talao', fotoTalao!.path),
      );
    }
    if (fotoCupom != null) {
      request.files.add(
        await http.MultipartFile.fromPath('foto_cupom', fotoCupom!.path),
      );
    }

    try {
      // Timeout de 30 segundos
      final streamedResponse = await request.send().timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          // Se o tempo esgotar, salva offline
          _dbHelper.salvarAbastecimentoOffline(data);
          throw Exception(
            "Tempo de envio esgotado. Abastecimento salvo offline.",
          );
        },
      );

      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode != 200) {
        await _dbHelper.salvarAbastecimentoOffline(data);
        throw Exception(
          "Erro ao enviar abastecimento: ${response.statusCode} - ${response.body}",
        );
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Abastecimento enviado com sucesso!"),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      // Caso ocorra qualquer outro erro, também salva offline
      await _dbHelper.salvarAbastecimentoOffline(data);
      //print("Erro ao enviar abastecimento: $e");
      throw Exception("Erro ao enviar abastecimento: $e");
    }
  }

  Widget buildTextField(
    String label,
    TextEditingController controller, {
    TextInputType type = TextInputType.number,
  }) {
    return TextField(
      controller: controller,
      keyboardType: type,
      decoration: InputDecoration(
        labelText: label,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 12,
        ),
      ),
    );
  }

  Widget fotoWidget(String label, File? foto, Function(File) onTap) {
    return GestureDetector(
      onTap: () async {
        File? f = await tirarFoto();
        if (f != null) onTap(f);
      },
      child: Container(
        width: 90,
        height: 90,
        decoration: BoxDecoration(
          color: Colors.grey[300],
          borderRadius: BorderRadius.circular(8),
          image: foto != null
              ? DecorationImage(image: FileImage(foto), fit: BoxFit.cover)
              : null,
        ),
        child: foto == null
            ? Center(
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12),
                ),
              )
            : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Registrar Abastecimento"),
        backgroundColor: AppColors.verdeEscuro,
      ),
      body: AbsorbPointer(
        absorbing: loading,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Caminhão
              DropdownButtonFormField<Caminhao>(
                decoration: InputDecoration(
                  labelText: "Placa do Veículo",
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                ),
                value: caminhaoSelecionado,
                items: listaCaminhoes
                    .map(
                      (c) => DropdownMenuItem(value: c, child: Text(c.placa)),
                    )
                    .toList(),
                onChanged: (c) {
                  setState(() {
                    caminhaoSelecionado = c;
                    departamentoSelecionado =
                        c?.departamento ?? "Não informado";
                  });
                },
              ),
              const SizedBox(height: 8),

              // Departamento
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: Colors.grey[200],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey[400]!),
                ),
                child: Text(
                  departamentoSelecionado ?? "Selecione a placa do veículo",
                ),
              ),
              const SizedBox(height: 8),

              // Combustível
              DropdownButtonFormField<String>(
                decoration: InputDecoration(
                  labelText: "Combustível",
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                ),
                value: combustivelSelecionado,
                items: listaCombustivel
                    .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                    .toList(),
                onChanged: (c) => setState(() => combustivelSelecionado = c),
              ),
              const SizedBox(height: 8),

              buildTextField(
                "Nome do Posto",
                postoController,
                type: TextInputType.text,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: buildTextField(
                      "Quantidade de Litros",
                      litrosController,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: buildTextField("Valor do Litro", valorController),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              buildTextField("Valor Total", valorTotalController),
              const SizedBox(height: 8),
              buildTextField("Km do Odômetro", odometroController),
              const SizedBox(height: 8),

              TextField(
                controller: obsController,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: "Observação",
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  fillColor: Colors.white,
                  filled: true,
                ),
              ),
              const SizedBox(height: 12),

              const Text(
                "Fotos obrigatórias:",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  fotoWidget(
                    "Placa",
                    fotoPlaca,
                    (f) => setState(() => fotoPlaca = f),
                  ),
                  fotoWidget(
                    "Bomba",
                    fotoBomba,
                    (f) => setState(() => fotoBomba = f),
                  ),
                  fotoWidget(
                    "Odômetro",
                    fotoOdometro,
                    (f) => setState(() => fotoOdometro = f),
                  ),
                  fotoWidget(
                    "Marcador de combustivel",
                    fotoMarcador,
                    (f) => setState(() => fotoMarcador = f),
                  ),
                  fotoWidget(
                    "Talão do Posto",
                    fotoTalao,
                    (f) => setState(() => fotoTalao = f),
                  ),
                  fotoWidget(
                    "Cupom Fiscal",
                    fotoCupom,
                    (f) => setState(() => fotoCupom = f),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              SafeArea(
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: enviarAbastecimento,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      backgroundColor: AppColors.verdeEscuro,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: loading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Text(
                            "Concluir Abastecimento",
                            style: TextStyle(fontSize: 16, color: Colors.white),
                          ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
