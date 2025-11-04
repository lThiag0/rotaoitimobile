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
  int? userIdLogado;
  String userCaminhao = "";
  int? userIdCaminhao;
  String userCaminhaoCor = "";
  String userCaminhaoPlaca = "";
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
      userIdLogado = usuario['id_usuario'];
      token = usuario['token'];
    });

    // Busca caminhão vinculado ao usuário
    final caminhao = await _dbHelper.buscarCaminhaoPorUsuario(userIdLogado!);

    setState(() {
      userCaminhao = caminhao?['nome'] ?? "Veículo";
      userIdCaminhao = caminhao?['id'] ?? 0;
      userCaminhaoCor = caminhao?['cor'] ?? "#FFFFFF";
      userCaminhaoPlaca = caminhao?['placa'] ?? "SEM-PLACA";
    });

    // Inicia serviço de localização apenas se houver caminhão vinculado
    await iniciarServico(
      usuarioToken: usuario['token'] ?? '',
      caminhaoId: userIdCaminhao ?? 0,
    );

    // Carrega entregas
    await _carregarEntregas();
  }

  Future<void> iniciarServico({
    required String usuarioToken,
    required int caminhaoId,
  }) async {
    final isRunning = await ForegroundServiceHelper.isServiceRunning();
    if (caminhaoId > 0 && usuarioToken.isNotEmpty) {
      if (!isRunning) {
        await ForegroundServiceHelper.startLocationService(
          usuarioToken,
          caminhaoId: caminhaoId,
        );
        //print('🚀 Serviço de localização iniciado.');
      } else {
        //print('✅ Serviço de localização já está ativo.');
      }
    } else {
      if (isRunning) {
        await ForegroundServiceHelper.stopLocationService();
        //print('⚠️ Caminhão ou token inválido. Serviço desligado.');
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
      await sincronizarCaminhoes();

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
          //print("API: $data");

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
          //print("Erro API: ${response.statusCode} - ${response.body}");
          //mostrarMensagem("Erro API: ${response.statusCode}");
        }
      } catch (e) {
        //print("Erro ao carregar entregas online: $e");
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
        //print("Total de entregas pendentes (offline): $pendentes");
      } catch (e) {
        //print("Erro ao carregar entregas offline: $e");
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
      //print("Erro grave ao desvincular caminhão: codigo: ${response.statusCode} - ${response.body}");
      return false;
    } catch (e) {
      //print("Erro ao desvincular caminhão: $e");
      return false;
    }
  }

  Future<void> sincronizarCaminhoes() async {
    //print("✅ Sistema de splash iniciado!");
    final usuario = await _dbHelper.buscarUsuarioLocal();
    final token = usuario?['token'];

    if (token == null || token.isEmpty) {
      //print("🔒 Token não encontrado. Faça login primeiro.");
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
        //print(dados);
        await _dbHelper.atualizarCaminhoes(
          List<Map<String, dynamic>>.from(dados),
        );
        //print("✅ Caminhões sincronizados com sucesso!");
      } else if (response.statusCode == 401) {
        //print("🔒 Token inválido ou expirado. Faça login novamente.");
      } else {
        //print("⚠️ Erro ao buscar caminhões da API: ${response.statusCode}");
      }
    } catch (e) {
      //print("📴 Sem conexão, usando dados locais: $e");
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
      //print("Erro na requisição de troca de veículo: $e");
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

    //print("GPS ativo: $gpsAtivo");
  }

  void _logout() async {
    await _dbHelper.limparUsuarios();
    if (!mounted) return;
    //await ForegroundServiceHelper.stopLocationService();
    await iniciarServico(usuarioToken: '', caminhaoId: 0);
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
                        // Atualiza SQLite local
                        await _dbHelper.atualizarCaminhaoVinculado(caminhao);

                        // Atualiza UI com dados do novo caminhão
                        setState(() {
                          userCaminhao = caminhao['nome'];
                          userCaminhaoCor = caminhao['cor'];
                          userCaminhaoPlaca = caminhao['placa'];
                          userIdCaminhao = caminhao['id'];
                        });

                        // Recarrega entregas usando o novo caminhão
                        await _carregarEntregas();

                        // Inicia serviço de localização com caminhão atualizado
                        await iniciarServico(
                          usuarioToken: usuario?['token'] ?? '',
                          caminhaoId: userIdCaminhao ?? 0,
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
                    await iniciarServico(usuarioToken: '', caminhaoId: 0);

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

  Widget _statusCard(String label, String valor, IconData icon) {
    const double cardHeight = 70;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      height: cardHeight,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(2, 2)),
        ],
      ),
      child: Row(
        children: [
          // Parte branca (texto + ícone principal)
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

          // Faixa verde lateral
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
            child: const Icon(Icons.more_horiz, color: Colors.white, size: 26),
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
                                  //print("entrando nas entregas com o id do caminhão: ${userIdCaminhao!}");
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
