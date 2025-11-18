import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:rotaoitimobile/db/splash.dart';
import 'package:rotaoitimobile/service/logcontroller.dart';
import 'package:rotaoitimobile/ui/abastecimento.dart';
import 'package:rotaoitimobile/ui/home.dart';
import 'package:rotaoitimobile/ui/login.dart';
import 'package:rotaoitimobile/ui/localizacao.dart';
import 'package:rotaoitimobile/ui/info.dart';
import 'package:rotaoitimobile/ui/pendentes.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  const logChannel = MethodChannel("rotaoiti_logs");

  LogController.instance.addLog("📌 SISTEMA DE LOG DO ANDROID INICIADO");
  //print("📌 SISTEMA DE LOG DO ANDROID INICIADO");

  logChannel.setMethodCallHandler((call) async {
    if (call.method == "sendLog") {
      final msg = call.arguments?.toString() ?? "";
      LogController.instance.addLog(msg);
    }
  });

  // Bloquear apenas em portrait (vertical)
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RotaOiti',
      debugShowCheckedModeBanner: false,
      navigatorKey: navigatorKey,
      initialRoute: '/',
      routes: {
        '/': (context) => const SplashPage(),
        '/login': (context) => const LoginPage(),
        '/home': (context) => HomePage(),
        '/localizacao': (context) => LocalizacaoPage(),
        '/info': (context) => InfoPage(),
        '/pendentes': (context) => EntregasPendentesPage(),
        '/abastecimentos': (context) => AbastecimentoPage(),
      },
    );
  }
}
