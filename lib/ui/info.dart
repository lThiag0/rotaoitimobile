import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:rotaoitimobile/class/classgerais.dart';
import 'package:rotaoitimobile/db/db_helper.dart';
import 'package:rotaoitimobile/service/update.dart';

class InfoPage extends StatefulWidget {
  const InfoPage({super.key});

  @override
  State<InfoPage> createState() => _InfoPageState();
}

class _InfoPageState extends State<InfoPage> {
  final DBHelper _dbHelper = DBHelper();
  final updater = UpdateApp();
  String currentVersion = "";
  Map<String, dynamic>? usuario;

  @override
  void initState() {
    super.initState();
    _loadUsuario();
    _loadAppVersion();
  }

  Future<void> _loadAppVersion() async {
    final info = await PackageInfo.fromPlatform();
    setState(() {
      currentVersion = info.version;
    });
  }

  Future<void> _loadUsuario() async {
    final data = await _dbHelper.buscarUsuarioLogado();
    setState(() {
      usuario = data;
    });
  }

  // Estilo padrão para botões
  ButtonStyle _buttonStyle(Color color) {
    return ElevatedButton.styleFrom(
      backgroundColor: color,
      padding: const EdgeInsets.symmetric(vertical: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.begeClaro,
      body: Column(
        children: [
          // Topo
          Container(
            height: 180,
            width: double.infinity,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [AppColors.verdeEscuro, AppColors.verdeNatural],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(30)),
            ),
            child: const Center(
              child: Text(
                "Informações do App",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Conteúdo scrollável
          Expanded(
            child: usuario == null
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    children: [
                      _buildCard(
                        title: "Usuário Logado",
                        content:
                            "Nome: ${usuario!['nome']}\nEmail: ${usuario!['email']}",
                        icon: Icons.person,
                      ),
                      _buildCard(
                        title: "Versão do App",
                        content: currentVersion,
                        icon: Icons.info,
                      ),
                      _buildCard(
                        title: "Instruções",
                        content:
                            "• O app envia a localização em tempo real.\n"
                            "• Certifique-se de que a internet esteja ativa.",
                        icon: Icons.help_outline,
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                        },
                        icon: const Icon(
                          Icons.arrow_back,
                          size: 30,
                          color: Colors.white,
                        ),
                        label: const Text(
                          "Voltar",
                          style: TextStyle(fontSize: 18, color: Colors.white),
                        ),
                        style: _buttonStyle(
                          const Color.fromARGB(255, 115, 117, 114),
                        ),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: () => updater.checkForUpdate(context),
                        icon: const Icon(
                          Icons.update,
                          size: 30,
                          color: Colors.white,
                        ),
                        label: const Text(
                          "Verificar Atualização",
                          style: TextStyle(fontSize: 18, color: Colors.white),
                        ),
                        style: _buttonStyle(Colors.blueAccent),
                      ),
                      const SizedBox(height: 16),
                    ],
                  ),
          ),

          // Rodapé fixo com créditos
          SafeArea(
            top: false,
            child: Container(
              width: double.infinity,
              color: AppColors.verdeEscuro,
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Center(
                child: RichText(
                  textAlign: TextAlign.center,
                  text: TextSpan(
                    style: const TextStyle(
                      color: Color(0xFFFFFFFF),
                      fontSize: 14,
                    ),
                    children: [
                      const TextSpan(text: "Desenvolvido com ❤️ por "),
                      TextSpan(
                        text: "Thiago Araujo",
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: AppColors.begeClaro,
                        ),
                      ),
                      const TextSpan(
                        text: "\nProjeto interno da Madeireira Oiti – 2025",
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCard({
    required String title,
    required String content,
    required IconData icon,
  }) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 6,
      margin: const EdgeInsets.symmetric(vertical: 8),
      color: Colors.white,
      shadowColor: Colors.green.withValues(alpha: 0.3),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.green.withValues(alpha: 0.1),
              ),
              padding: const EdgeInsets.all(12),
              child: Icon(icon, size: 30, color: Colors.green),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(content, style: const TextStyle(fontSize: 16)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
