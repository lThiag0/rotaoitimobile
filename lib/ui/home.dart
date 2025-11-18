import 'dart:async';
import 'dart:convert';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:rotaoitimobile/class/classgerais.dart';
import 'package:rotaoitimobile/db/auth_service.dart';
import 'package:rotaoitimobile/db/db_helper.dart';
import 'package:rotaoitimobile/service/foreground.dart';
import 'package:rotaoitimobile/service/update.dart';
import 'package:rotaoitimobile/ui/entrega.dart';
import 'package:geocoding/geocoding.dart';
import 'package:rotaoitimobile/service/logcontroller.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final DBHelper _dbHelper = DBHelper();
  final AuthService _authService = AuthService();
  final updater = UpdateApp();

  String userName = "";
  String userEmail = "";
  int? userIdLogado;
  String userCaminhao = "";
  int? userIdCaminhao;
  String userCaminhaoCor = "";
  String userCaminhaoPlaca = "";
  int userCaminhaoParadaMin = 10;
  double userCaminhaoGaragemLat = 0.0;
  double userCaminhaoGaragemLon = 0.0;
  String? token;
  bool loading = true;
  bool gpsAtivo = false;
  bool servicoAtivo = false;

  List<Entrega> entregas = [];

  @override
  void initState() {
    super.initState();
    _init();
  }

  static void _log(String message) {
    LogController.instance.addLog("📱 FLUTTER → $message");
  }

  Future<void> _init() async {
    await _carregarUsuario();
    await _verificarGPS();
    await _verificarServico();
    // ignore: use_build_context_synchronously
    await updater.checkForUpdateSemInfo(context);
  }

  Future<void> _verificarServico() async {
    final estaRodando = await ForegroundServiceHelper.isServiceRunning();
    if (!mounted) return;
    setState(() {
      servicoAtivo = estaRodando;
    });
  }

  Future<void> _carregarUsuario() async {
    final usuario = await _dbHelper.buscarUsuarioLocal();
    if (!mounted || usuario == null) return;

    // Atualiza informações do usuário
    setState(() {
      userName = usuario['nome'] ?? "Usuário";

      userEmail = usuario['email'] ?? "email deslogado";
      userIdLogado = usuario['id_usuario'];
      token = usuario['token'];
    });

    await sincronizarCaminhoes();

    // Busca caminhão vinculado ao usuário
    final caminhao = await _dbHelper.buscarCaminhaoPorUsuario(userIdLogado!);

    setState(() {
      userCaminhao = caminhao?['nome'] ?? "Veículo";
      userIdCaminhao = caminhao?['id'] ?? 0;
      userCaminhaoCor = caminhao?['cor'] ?? "#FFFFFF";
      userCaminhaoPlaca = caminhao?['placa'] ?? "SEM-PLACA";
      userCaminhaoParadaMin = caminhao?['parada_longa_minutos'] ?? 10;
      userCaminhaoGaragemLat = caminhao?['garagem_latitude'] ?? 0.0;
      userCaminhaoGaragemLon = caminhao?['garagem_longitude'] ?? 0.0;
    });

    // Inicia serviço de localização apenas se houver caminhão vinculado
    await iniciarServico(
      usuarioToken: usuario['token'] ?? '',
      caminhaoId: userIdCaminhao ?? 0,
      paradaLongaMinutos: userCaminhaoParadaMin,
      garagemLat: userCaminhaoGaragemLat,
      garagemLon: userCaminhaoGaragemLon,
    );

    // Carrega entregas
    await _carregarEntregas();
  }

  Future<String?> pedirSenhaUsuario() async {
    String senha = "";
    return await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("Confirme sua senha"),
          content: TextField(
            obscureText: true,
            onChanged: (value) => senha = value,
            decoration: const InputDecoration(hintText: "Digite sua senha"),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, null),
              child: const Text("Cancelar"),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, senha),
              child: const Text("Confirmar"),
            ),
          ],
        );
      },
    );
  }

  Future<void> iniciarServico({
    required String usuarioToken,
    required int caminhaoId,
    required int paradaLongaMinutos,
    required double garagemLat,
    required double garagemLon,
  }) async {
    final isRunning = await ForegroundServiceHelper.isServiceRunning();
    if (caminhaoId > 0 && usuarioToken.isNotEmpty) {
      if (!isRunning) {
        await ForegroundServiceHelper.startLocationService(
          usuarioToken,
          caminhaoId: caminhaoId,
          paradaLongaMinutos: paradaLongaMinutos,
          garagemLat: garagemLat,
          garagemLon: garagemLon,
        );
      } else {
        _log('✅ Serviço de localização já está ativo.');
      }
    } else {
      if (isRunning) {
        await ForegroundServiceHelper.stopLocationService();
        _log('⚠️ Caminhão ou token inválido. Serviço desligado.');
      }
    }
    _verificarServico();
  }

  Future<void> _carregarEntregas() async {
    setState(() => loading = true);

    // Verifica se existe caminhão vinculado
    if (userIdCaminhao == null || userIdCaminhao == 0) {
      setState(() {
        entregas = []; // zera entregas
        loading = false;
      });
      return;
    }
    final conexao = await Connectivity().checkConnectivity();

    if (conexao != ConnectivityResult.none) {
      //await sincronizarCaminhoes();

      try {
        final response = await http.get(
          Uri.parse(
            "${_authService.apiUrl}/api/caminhoes/$userIdCaminhao/entregas",
          ),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
        );

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body) as Map<String, dynamic>;

          // Entregas
          final List<dynamic> entregasJson = data['data'] ?? [];
          final List<Entrega> entregasApi = entregasJson
              .map((e) => Entrega.fromJson(e as Map<String, dynamic>))
              .toList();

          if (mounted) {
            setState(() {
              entregas = entregasApi;
            });
          }

          // Salva no SQLite
          await _dbHelper.salvarEntregas(entregasApi);
        } else {
          _log("Erro API: ${response.statusCode}");
          //mostrarMensagem("Erro API: ${response.statusCode}");
        }
      } catch (e) {
        _log("Erro ao carregar entregas online: $e");
        mostrarMensagem("Erro ao carregar entregas online!");
      }
    } else {
      // OFFLINE
      try {
        final offlineData = await _dbHelper.buscarEntregas();
        if (mounted) {
          setState(() {
            entregas = offlineData;
          });
        }
      } catch (e) {
        _log("Erro ao carregar entregas offline: $e");
        mostrarMensagem("Erro ao carregar entregas offline!");
      }
    }

    if (!mounted) return;
    setState(() {
      loading = false;
    });
  }

  Future<bool> _desvincularVeiculo(String token) async {
    try {
      final response = await http.post(
        Uri.parse("${_authService.apiUrl}/api/caminhao/desvincular"),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['success'] == true;
      }
      _log(
        "Erro grave ao desvincular caminhão: codigo: ${response.statusCode}",
      );
      return false;
    } catch (e) {
      _log("Erro ao desvincular caminhão: $e");
      return false;
    }
  }

  Future<void> sincronizarCaminhoes() async {
    _log("✅ Sistema de splash iniciado!");
    final usuario = await _dbHelper.buscarUsuarioLocal();
    final token = usuario?['token'];

    if (token == null || token.isEmpty) {
      _log("🔒 Token não encontrado. Faça login primeiro.");
      return;
    }

    try {
      final response = await http.get(
        Uri.parse('${_authService.apiUrl}/api/caminhoes'),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final List<dynamic> dados = jsonDecode(response.body);
        await _dbHelper.atualizarCaminhoes(
          List<Map<String, dynamic>>.from(dados),
        );
        _log("✅ Caminhões sincronizados com sucesso!");
      } else if (response.statusCode == 401) {
        _log("🔒 Token inválido ou expirado. Faça login novamente.");
      } else {
        _log("⚠️ Erro ao buscar caminhões da API: ${response.statusCode}");
      }
    } catch (e) {
      _log("📴 Sem conexão, usando dados locais: $e");
    }
  }

  Future<bool> _enviarTrocaVeiculo(String token, int caminhaoId) async {
    try {
      final response = await http.post(
        Uri.parse("${_authService.apiUrl}/api/trocar-caminhao"),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'caminhao_id': caminhaoId}),
      );

      return response.statusCode == 200;
    } catch (e) {
      _log("Erro na requisição de troca de veículo: $e");
      return false;
    }
  }

  Future<void> _verificarGPS() async {
    bool servicoAtivo = await Geolocator.isLocationServiceEnabled();
    LocationPermission permissao = await Geolocator.checkPermission();
    if (permissao == LocationPermission.denied) {
      permissao = await Geolocator.requestPermission();
    }

    if (!mounted) return;
    setState(() {
      gpsAtivo =
          servicoAtivo &&
          (permissao == LocationPermission.always ||
              permissao == LocationPermission.whileInUse);
    });

    _log("GPS ativo: $gpsAtivo");
  }

  Future<bool> validarSenha(String email, String senhaDigitada) async {
    final usuario = await _dbHelper.buscarUsuarioLocal();
    if (usuario == null) return false;

    final conexao = await Connectivity().checkConnectivity();

    if (conexao != ConnectivityResult.none) {
      // ONLINE: tenta validar no servidor usando API de login
      try {
        final res = await http.post(
          Uri.parse("${AuthService().apiUrl}/api/login"),
          body: {"email": usuario['email'], "password": senhaDigitada},
        );

        if (res.statusCode == 200) {
          // login online válido
          return true;
        }
      } catch (_) {
        // falha no servidor → tenta local
      }
    }

    // OFFLINE ou falha no servidor → valida local
    final hashLocal = usuario['senha_hash'] ?? '';
    final hashDigitado = AuthService().hashSenha(senhaDigitada);

    return hashLocal == hashDigitado;
  }

  void _logout() async {
    final senha = await pedirSenhaUsuario();
    if (senha == null || senha.isEmpty) return;

    final valido = await validarSenha(userEmail, senha);
    if (!valido) {
      mostrarMensagem("Senha incorreta.");
      return;
    }

    await _dbHelper.limparUsuarios();
    await iniciarServico(
      usuarioToken: '',
      caminhaoId: 0,
      paradaLongaMinutos: 10,
      garagemLat: 0.0,
      garagemLon: 0.0,
    );
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
  }

  void mostrarMensagem(String texto) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(texto),
        backgroundColor: const Color.fromARGB(255, 34, 34, 34),
      ),
    );
  }

  Future<void> iniciarEntregas() async {
    final usuario = await _dbHelper.buscarUsuarioLocal();
    if (usuario == null) return;

    final token = usuario['token'] ?? '';
    final userId = usuario['id_usuario'] ?? 0;
    final caminhaoId = userIdCaminhao ?? 0;

    // Verifica conexão
    final conexao = await Connectivity().checkConnectivity();
    if (conexao == ConnectivityResult.none) {
      mostrarMensagem(
        "É necessário conexão com a internet para iniciar as entregas.",
      );
      return;
    }

    if (caminhaoId == 0 || token.isEmpty || userId == 0) {
      mostrarMensagem(
        "Não é possível iniciar entregas sem veículo ou login válido.",
      );
      return;
    }

    _carregarEntregas();

    try {
      // Pega localização atual
      Position pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      final payload = {
        'user_id': userId,
        'caminhao_id': caminhaoId,
        'inicio_entrega': DateTime.now().toIso8601String(),
        'latitude': pos.latitude,
        'longitude': pos.longitude,
      };

      final res = await http
          .post(
            Uri.parse("${_authService.apiUrl}/api/entregas/iniciar"),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
            body: jsonEncode(payload),
          )
          .timeout(
            const Duration(seconds: 10),
            onTimeout: () {
              throw TimeoutException(
                'O servidor demorou muito para responder. Tente novamente.',
              );
            },
          );

      final data = jsonDecode(res.body);

      if (res.statusCode == 200 && data['success'] == true) {
        mostrarMensagem(data['message'] ?? "Entregas iniciadas com sucesso!");
      } else {
        mostrarMensagem(data['message'] ?? 'Falha ao iniciar entregas.');
      }
    } on TimeoutException catch (_) {
      mostrarMensagem("Tempo de resposta esgotado. Verifique sua conexão.");
    } catch (e) {
      mostrarMensagem("Erro ao notificar servidor: $e");
    }
  }

  void mostrarConfiguracoesVeiculo() async {
    final usuario = await _dbHelper.buscarUsuarioLocal();
    if (usuario == null) return;

    final caminhao = await _dbHelper.buscarCaminhaoPorUsuario(userIdLogado!);
    if (caminhao == null) {
      mostrarMensagem(
        "Não é possível abrir as configurações rastreamento do veículo.",
      );
      return;
    }

    if (!mounted) return;

    String enderecoGaragem = "Carregando...";

    final latStr = caminhao?['garagem_latitude']?.toString();
    final lonStr = caminhao?['garagem_longitude']?.toString();

    if (latStr != null && lonStr != null) {
      final lat = double.tryParse(latStr);
      final lon = double.tryParse(lonStr);

      if (lat != null && lon != null) {
        try {
          // 🔒 Garante que permissões foram concedidas
          LocationPermission permission = await Geolocator.checkPermission();
          if (permission == LocationPermission.denied ||
              permission == LocationPermission.deniedForever) {
            permission = await Geolocator.requestPermission();
          }

          final placemarks = await placemarkFromCoordinates(lat, lon);

          if (placemarks.isNotEmpty) {
            final p = placemarks.first;
            enderecoGaragem =
                "${p.street ?? ''}, ${p.subLocality ?? ''}, ${p.locality ?? ''} - ${p.administrativeArea ?? ''}";
          } else {
            enderecoGaragem = "Endereço não encontrado";
          }
        } catch (e) {
          enderecoGaragem = "Erro ao buscar endereço: ${e.toString()}";
          _log("❌ Erro Geocoding: $e");
        }
      } else {
        enderecoGaragem = "Coordenadas inválidas";
      }
    } else {
      enderecoGaragem = "Coordenadas não cadastradas";
    }

    // Converte a cor (se for em formato HEX)
    Color corCaminhao = Colors.grey;
    if (caminhao?['cor'] != null && caminhao!['cor'].toString().isNotEmpty) {
      try {
        String corStr = caminhao['cor'].toString().replaceAll('#', '');
        corCaminhao = Color(int.parse('0xFF$corStr'));
      } catch (_) {}
    }

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text(
            "Configurações do Veículo",
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("👤 Motorista: ${usuario?['nome'] ?? '-'}"),
                Text("📧 Email: ${usuario?['email'] ?? '-'}"),
                const Divider(height: 15),
                Text("🚛 Veículo: ${caminhao?['nome'] ?? '-'}"),
                Text("🪪 Placa: ${caminhao?['placa'] ?? '-'}"),
                Row(
                  children: [
                    const Text("🎨 Cor: "),
                    Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: corCaminhao,
                        border: Border.all(color: Colors.black26),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                ),
                const SizedBox(height: 8),
                Text("🏢 Empresa: ${caminhao?['empresa'] ?? '-'}"),
                Text("🧾 CNPJ: ${caminhao?['cnpj'] ?? '-'}"),
                const Divider(height: 15),
                Text(
                  "📍 Rastreamento: ${(caminhao?['rastreamento_ligado'] == 1) ? 'Ativo' : 'Desligado'}",
                  style: TextStyle(
                    color: (caminhao?['rastreamento_ligado'] == 1)
                        ? Colors.green
                        : Colors.red,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  "🕒 Horário rastreamento: ${caminhao?['horario_rastreamento'] ?? '-'}",
                ),
                Text(
                  "📅 Dias rastreamento: ${caminhao?['dias_rastreamento'] ?? '-'}",
                ),
                Text(
                  "⏱️ Parada longa (min): ${caminhao?['parada_longa_minutos'] ?? '-'}",
                ),
                const Divider(height: 15),
                Text("🏠 Garagem:"),
                Text(
                  enderecoGaragem,
                  style: const TextStyle(fontStyle: FontStyle.italic),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Fechar"),
            ),
          ],
        );
      },
    );
  }

  void _trocarVeiculo() async {
    final usuario = await _dbHelper.buscarUsuarioLocal();
    final token = usuario?['token'];

    if (token == null || token.isEmpty) {
      mostrarMensagem("Você precisa estar logado.");
      return;
    }

    // Verifica conexão
    final conexao = await Connectivity().checkConnectivity();
    if (conexao == ConnectivityResult.none) {
      mostrarMensagem(
        "É necessário conexão com a internet para trocar o veículo.",
      );
      return;
    }

    try {
      // Pega lista de veículos da API
      final response = await http.get(
        Uri.parse('${_authService.apiUrl}/api/caminhoes'),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      );

      if (response.statusCode != 200) {
        mostrarMensagem("Erro ao carregar veículos da API.");
        return;
      }

      final List<dynamic> dados = jsonDecode(response.body);

      // Exibe diálogo para selecionar ou desvincular
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text("Selecione um veículo"),
            content: SizedBox(
              width: double.maxFinite,
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: dados.length,
                itemBuilder: (context, index) {
                  final caminhao = dados[index];
                  return ListTile(
                    title: Text(caminhao['nome']),
                    subtitle: Text("Placa: ${caminhao['placa']}"),
                    trailing: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: parseColor(caminhao['cor']),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        "Cor",
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    onTap: () async {
                      Navigator.pop(context); // fecha diálogo

                      // Chama API para trocar veículo
                      final sucesso = await _enviarTrocaVeiculo(
                        token,
                        caminhao['id'],
                      );

                      if (sucesso) {
                        //Para o serviço antes
                        final isRunning =
                            await ForegroundServiceHelper.isServiceRunning();
                        if (isRunning) {
                          await iniciarServico(
                            usuarioToken: '',
                            caminhaoId: 0,
                            paradaLongaMinutos: 10,
                            garagemLat: 0.0,
                            garagemLon: 0.0,
                          );
                        }

                        // Atualiza SQLite local
                        await _dbHelper.atualizarCaminhaoVinculado(caminhao);

                        // Atualiza UI com dados do novo caminhão
                        setState(() {
                          userCaminhao = caminhao['nome'];
                          userCaminhaoCor = caminhao['cor'];
                          userCaminhaoPlaca = caminhao['placa'];
                          userIdCaminhao = caminhao['id'];
                          userCaminhaoParadaMin =
                              caminhao?['parada_longa_minutos'] ?? 10;
                          userCaminhaoGaragemLat =
                              double.tryParse(
                                caminhao?['garagem_latitude']?.toString() ?? '',
                              ) ??
                              0.0;
                          userCaminhaoGaragemLon =
                              double.tryParse(
                                caminhao?['garagem_longitude']?.toString() ??
                                    '',
                              ) ??
                              0.0;
                        });

                        // Recarrega entregas usando o novo caminhão
                        await _carregarUsuario();
                        await _carregarEntregas();

                        // Inicia serviço de localização com caminhão atualizado
                        await iniciarServico(
                          usuarioToken: usuario?['token'] ?? '',
                          caminhaoId: userIdCaminhao ?? 0,
                          paradaLongaMinutos: userCaminhaoParadaMin,
                          garagemLat: userCaminhaoGaragemLat,
                          garagemLon: userCaminhaoGaragemLon,
                        );

                        mostrarMensagem(
                          "Veículo alterado para ${caminhao['nome']}",
                        );
                      } else {
                        mostrarMensagem(
                          "Falha ao alterar veículo. Tente novamente.",
                        );
                      }
                    },
                  );
                },
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("Cancelar"),
              ),
              TextButton(
                onPressed: () async {
                  Navigator.pop(context); // fecha diálogo

                  final conexao = await Connectivity().checkConnectivity();
                  if (conexao == ConnectivityResult.none) {
                    mostrarMensagem(
                      "É necessário estar conectado à internet para desvincular o veículo.",
                    );
                    return; // não faz nada sem internet
                  }

                  final usuario = await _dbHelper.buscarUsuarioLocal();
                  final token = usuario?['token'];

                  if (token == null || token.isEmpty) {
                    mostrarMensagem("Você precisa estar logado.");
                    return;
                  }

                  final senha = await pedirSenhaUsuario();
                  if (senha == null || senha.isEmpty) return;

                  final valido = await validarSenha(userEmail, senha);
                  if (!valido) {
                    mostrarMensagem("Senha incorreta.");
                    return;
                  }

                  final sucesso = await _desvincularVeiculo(token);

                  if (sucesso) {
                    // Atualiza SQLite local
                    final desvinculado = {
                      'caminhao_nome': "Veículo",
                      'caminhao_id': 0,
                      'caminhao_cor': "#FFFFFF",
                      'caminhao_placa': "SEM-PLACA",
                    };
                    await _dbHelper.atualizarCaminhaoVinculado(desvinculado);
                    await sincronizarCaminhoes();
                    await _carregarUsuario();

                    // Atualiza UI
                    setState(() {
                      userCaminhao = desvinculado['caminhao_nome'] as String;
                      userIdCaminhao = desvinculado['caminhao_id'] as int;
                      userCaminhaoCor = desvinculado['caminhao_cor'] as String;
                      userCaminhaoPlaca =
                          desvinculado['caminhao_placa'] as String;
                    });

                    // Recarrega entregas
                    await _carregarEntregas();

                    // Para o serviço de localização
                    //await ForegroundServiceHelper.stopLocationService();
                    await iniciarServico(
                      usuarioToken: '',
                      caminhaoId: 0,
                      paradaLongaMinutos: 10,
                      garagemLat: 0.0,
                      garagemLon: 0.0,
                    );

                    mostrarMensagem("Veículo desvinculado com sucesso.");
                  } else {
                    mostrarMensagem(
                      "Falha ao desvincular o veículo. Tente novamente.",
                    );
                  }
                },
                child: const Text(
                  "Desvincular",
                  style: TextStyle(color: Colors.red),
                ),
              ),
            ],
          );
        },
      );
    } catch (e) {
      mostrarMensagem("Erro ao carregar veículos: $e");
    }
  }

  Color parseColor(String color) {
    try {
      if (color.startsWith('#')) {
        return Color(int.parse(color.substring(1), radix: 16) + 0xFF000000);
      } else if (color == "Amarela") {
        return Colors.amber;
      } else if (color == "Vermelha") {
        return Colors.red;
      }
    } catch (_) {}
    return Colors.grey;
  }

  Widget _botaoCard(String titulo, IconData icone, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(16),
        margin: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [AppColors.verdeNatural, AppColors.verdeEscuro],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: const [
            BoxShadow(
              color: Colors.black26,
              blurRadius: 6,
              offset: Offset(2, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Icon(icone, color: Colors.white, size: 36),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                titulo,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const Icon(Icons.arrow_forward_ios, color: Colors.white, size: 18),
          ],
        ),
      ),
    );
  }

  Widget _statusCard(
    String label,
    String valor,
    IconData icon, {
    VoidCallback? onTap, // ação ao clicar
    IconData? botaoIcon, // ícone do botão lateral
  }) {
    const double cardHeight = 70;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      height: cardHeight,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.9),
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(2, 2)),
        ],
      ),
      child: Row(
        children: [
          // Parte principal do card
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Icon(icon, color: AppColors.verdeNatural, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          label,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(valor, style: const TextStyle(fontSize: 14)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Faixa lateral com ícone e ação
          Container(
            width: 55,
            height: cardHeight,
            decoration: const BoxDecoration(
              color: AppColors.verdeNatural,
              borderRadius: BorderRadius.only(
                topRight: Radius.circular(12),
                bottomRight: Radius.circular(12),
              ),
            ),
            child: IconButton(
              icon: Icon(
                botaoIcon ?? Icons.more_horiz,
                color: Colors.white,
                size: 26,
              ),
              onPressed: onTap,
            ),
          ),
        ],
      ),
    );
  }

  Widget _caminhaoCard(String nome, String corPlaca, String placa) {
    return Card(
      color: Colors.white.withValues(alpha: 0.9),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.symmetric(vertical: 4), // mesmo padrão visual
      child: Row(
        children: [
          // Ícone do caminhão
          Padding(
            padding: const EdgeInsets.all(12),
            child: Icon(Icons.local_shipping, color: AppColors.verdeNatural),
          ),

          // Informações do caminhão
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  nome,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text("Placa: $placa", style: const TextStyle(fontSize: 14)),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: parseColor(corPlaca),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        "Cor",
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Botão de troca
          Container(
            height: 65, // mesma altura visual do ListTile
            decoration: const BoxDecoration(
              color: AppColors.verdeNatural,
              borderRadius: BorderRadius.only(
                topRight: Radius.circular(12),
                bottomRight: Radius.circular(12),
              ),
            ),
            child: IconButton(
              icon: const Icon(Icons.swap_horiz, color: Colors.white),
              tooltip: 'Trocar veículo',
              onPressed: _trocarVeiculo,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // cálculos otimizados
    final pendentes = entregas.where((e) => e.status == 'pendente').length;

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [AppColors.begeMadeira, AppColors.begeClaro],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.only(bottom: 20),
                  child: Column(
                    children: [
                      // cabeçalho
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 20,
                        ),
                        child: Row(
                          children: [
                            const CircleAvatar(
                              radius: 28,
                              backgroundColor: AppColors.verdeNatural,
                              child: Icon(
                                Icons.person,
                                color: Colors.white,
                                size: 32,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                "Olá, $userName",
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.marromEscuro,
                                ),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(
                                Icons.sync,
                                color: Color(0xFF52A3FF),
                              ),
                              onPressed: _carregarUsuario,
                              tooltip: "Recarregar",
                            ),
                            IconButton(
                              icon: const Icon(
                                Icons.logout,
                                color: Colors.redAccent,
                              ),
                              onPressed: _logout,
                              tooltip: "Sair",
                            ),
                          ],
                        ),
                      ),
                      // dica
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 8,
                        ),
                        child: Text(
                          "💡 Dica: Confira suas entregas e mantenha o GPS ativo!",
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 16,
                            fontStyle: FontStyle.italic,
                            color: AppColors.marromEscuro,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      // status
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Column(
                          children: [
                            _statusCard(
                              "Entregas de hoje",
                              "$pendentes pendentes",
                              Icons.assignment,
                              onTap: iniciarEntregas,
                              botaoIcon: Icons.play_arrow,
                            ),
                            const SizedBox(height: 8),
                            _statusCard(
                              "GPS",
                              gpsAtivo
                                  ? (servicoAtivo
                                        ? "Ativo (Serviço rodando)"
                                        : "Ativo (Serviço parado)")
                                  : "Inativo",
                              gpsAtivo ? Icons.gps_fixed : Icons.gps_off,
                              onTap: () {
                                mostrarConfiguracoesVeiculo();
                              },
                              botaoIcon: Icons.settings,
                            ),
                            const SizedBox(height: 8),
                            _caminhaoCard(
                              userCaminhao,
                              userCaminhaoCor,
                              userCaminhaoPlaca,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      // atalhos
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Center(
                          child: Text(
                            "Meus Atalhos",
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: AppColors.marromEscuro,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 20,
                        ),
                        child: Column(
                          children: [
                            _botaoCard("Entregas", Icons.local_shipping, () {
                              if (gpsAtivo) {
                                if (userIdCaminhao! > 0) {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => EntregasPage(
                                        caminhaoId: userIdCaminhao!,
                                      ),
                                    ),
                                  );
                                } else {
                                  mostrarMensagem(
                                    "Você não tem um veículo vinculado.",
                                  );
                                }
                              } else {
                                mostrarMensagem(
                                  "Para fazer entregas ligue o GPS do aparelho.",
                                );
                              }
                            }),
                            _botaoCard(
                              "Abastecimentos",
                              Icons.local_gas_station,
                              () {
                                Navigator.pushNamed(context, '/abastecimentos');
                              },
                            ),
                            _botaoCard(
                              "Informações do App",
                              Icons.info_outline,
                              () {
                                Navigator.pushNamed(context, '/info');
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // rodapé
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Center(
                  child: Text(
                    "Madeireira Oiti",
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: AppColors.marromEscuro,
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
