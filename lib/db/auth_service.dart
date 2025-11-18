import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:connectivity_plus/connectivity_plus.dart';
import 'db_helper.dart';

class AuthService {
  final DBHelper _dbHelper = DBHelper();
  final String apiUrl = "https://srv962439.hstgr.cloud";

  String hashSenha(String senha) {
    return sha256.convert(utf8.encode(senha)).toString();
  }

  Future<bool> login(String email, String senha) async {
    final conexao = await Connectivity().checkConnectivity();

    if (conexao != ConnectivityResult.none) {
      // ONLINE
      final res = await http.post(
        Uri.parse("$apiUrl/api/login"),
        body: {"email": email, "password": senha},
      );

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final user = data["user"];

        await _dbHelper.salvarUsuario({
          "nome": data["user"]["name"],
          "id_usuario": data["user"]["id"],
          "email": email,
          "senha_hash": hashSenha(senha),
          "token": data["token"],
          "caminhao_id": user["caminhao_id"] ?? data["caminhao_id"],
          "caminhao_nome": user["caminhao_nome"] ?? data["caminhao_nome"],
          "caminhao_cor": user["caminhao_cor"] ?? data["caminhao_cor"],
          "caminhao_placa": user["caminhao_placa"] ?? data["caminhao_placa"],
        });

        //print("Json: ${res.body}");

        return true;
      } else {
        return false;
      }
    } else {
      // OFFLINE
      final usuario = await _dbHelper.buscarUsuario(email);
      if (usuario != null && usuario["senha_hash"] == hashSenha(senha)) {
        return true;
      }
      return false;
    }
  }
}
