import 'package:connectivity_plus/connectivity_plus.dart';

class ConexaoService {
  static final ConexaoService _instance = ConexaoService._internal();
  factory ConexaoService() => _instance;
  ConexaoService._internal();

  final Connectivity _connectivity = Connectivity();

  void startMonitoring(Function() onInternetAvailable) {
    _connectivity.onConnectivityChanged.listen((ConnectivityResult result) {
      if (result == ConnectivityResult.mobile || result == ConnectivityResult.wifi) {
        onInternetAvailable();
      }
    });
  }
}
