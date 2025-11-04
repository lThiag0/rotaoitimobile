import 'package:android_intent_plus/android_intent.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:rotaoitimobile/db/db_helper.dart';

class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage>
    with SingleTickerProviderStateMixin {
  final DBHelper _dbHelper = DBHelper();
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..forward();

    _fadeAnimation = CurvedAnimation(parent: _controller, curve: Curves.easeIn);

    _initApp();
  }

  Future<void> _initApp() async {
    await pedirPermissoes();

    // só continua depois que permissões estiverem ok
    if (!mounted) return;
    await _checkLogin();
  }

  Future<void> pedirPermissoes() async {
    bool todasConcedidas = false;

    while (!todasConcedidas) {
      // Localização
      if (!await Permission.location.isGranted) {
        await Permission.location.request();
      }

      // Câmera
      if (!await Permission.camera.isGranted) {
        await Permission.camera.request();
      }

      // Notificações
      if (!await Permission.notification.isGranted) {
        await Permission.notification.request();
      }

      // Verifica se todas foram concedidas
      todasConcedidas =
          await Permission.location.isGranted &&
          await Permission.camera.isGranted &&
          await Permission.notification.isGranted;

      if (!todasConcedidas) {
        // Mostra alerta e força usuário a conceder ou sair
        bool abrirConfiguracoes =
            await showDialog(
              // ignore: use_build_context_synchronously
              context: context,
              barrierDismissible: false,
              builder: (context) => AlertDialog(
                title: const Text("Permissões necessárias"),
                content: const Text(
                  "Este aplicativo precisa de todas as permissões (Localização, Câmera e Notificações) para funcionar corretamente.",
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    child: const Text("Abrir configurações"),
                  ),
                ],
              ),
            ) ??
            false;

        if (abrirConfiguracoes) {
          await openAppSettings();
        } else {
          // fecha o app

          Future.delayed(Duration.zero, () {
            if (!mounted) return;
            Navigator.of(context).pop();
          });
          return;
        }
      }
    }
  }

  Future<void> disableBatteryOptimization() async {
    final intent = AndroidIntent(
      action: 'android.settings.IGNORE_BATTERY_OPTIMIZATION_SETTINGS',
    );
    await intent.launch();
  }

  Future<void> _checkLogin() async {
    final usuario = await _dbHelper.buscarUsuarioLocal();

    await Future.delayed(const Duration(seconds: 2)); // tempo do splash

    if (!mounted) return;

    if (usuario != null) {
      Navigator.pushReplacementNamed(context, '/home');
    } else {
      Navigator.pushReplacementNamed(context, '/login');
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5E6D3),
      body: Center(
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.local_shipping_rounded,
                color: const Color(0xFF4B3832),
                size: 80,
              ),
              const SizedBox(height: 16),
              Text(
                "Rota Oiti",
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF4B3832),
                ),
              ),
              const SizedBox(height: 30),
              const CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF8B5E3C)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
