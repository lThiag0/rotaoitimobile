import 'dart:convert';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:rotaoitimobile/db/auth_service.dart';
import 'package:url_launcher/url_launcher.dart';

class UpdateApp { 
  final AuthService _authService = AuthService();
  
  Future<void> checkForUpdate(BuildContext context) async {
    final info = await PackageInfo.fromPlatform();
    final currentVersion = info.version;
    final conexao = await Connectivity().checkConnectivity();

    if (conexao != ConnectivityResult.none) {
      try {
        final response = await http.get(
          Uri.parse("${_authService.apiUrl}/api/app/atualizacao?platform=android"),
        );
        if (response.statusCode == 200) {
          final data = json.decode(response.body)['data'];
          final latestVersion = data['version'];
          final mandatory = (data['mandatory'] ?? false) == 1;
          final url = data['url'] ?? '';

          if (_isVersionOutdated(currentVersion, latestVersion)) {
            // ignore: use_build_context_synchronously
            _showUpdateDialog(context, latestVersion, url, mandatory);
          } else {
            // ignore: use_build_context_synchronously
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('App está atualizado')),
            );
          }
        } else {
          // ignore: use_build_context_synchronously
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Nenhuma versão encontrada')),
          );
        }
      } catch (e) {
        final msg = e is SocketException
          ? 'Sem conexão com a internet'
          : 'Erro: $e';
        // ignore: use_build_context_synchronously
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg)),
        );
      }
    } 
  }

  Future<void> checkForUpdateSemInfo(BuildContext context) async {
    final info = await PackageInfo.fromPlatform();
    final currentVersion = info.version;

    try {
      final response = await http.get(
        Uri.parse("${_authService.apiUrl}/api/app/atualizacao?platform=android"),
      );
      if (response.statusCode == 200) {
        final data = json.decode(response.body)['data'];
        final latestVersion = data['version'];
        final mandatory = (data['mandatory'] ?? false) == 1;
        final url = data['url'] ?? '';

        if (_isVersionOutdated(currentVersion, latestVersion)) {
          // ignore: use_build_context_synchronously
          _showUpdateDialog(context, latestVersion, url, mandatory);
        } 
      }
    } catch (e) {
      final msg = e is SocketException
        ? 'Sem conexão com a internet'
        : 'Erro: $e';
      // ignore: use_build_context_synchronously
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Erro ao tenta atualizar o app: $msg")),
      );
    }

  }

  // compara versões simples
  bool _isVersionOutdated(String current, String latest) {
    List<int> curr = current.split('.').map(int.parse).toList();
    List<int> lat = latest.split('.').map(int.parse).toList();

    for (int i = 0; i < lat.length; i++) {
      if (i >= curr.length || curr[i] < lat[i]) return true;
      if (curr[i] > lat[i]) return false;
    }
    return false;
  }

  void _showUpdateDialog(BuildContext context, String version, String url, bool mandatory) {
    showDialog(
      context: context,
      barrierDismissible: !mandatory,
      builder: (_) => AlertDialog(
        title: Text('Nova versão disponível: $version'),
        content: const Text('Deseja atualizar agora?'),
        actions: [
          if (!mandatory)
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Depois'),
            ),
          TextButton(
            onPressed: () async {
              final uri = Uri.parse(url);
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              } else {
                // ignore: use_build_context_synchronously
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Não foi possível abrir o link')),
                );
              }
            },
            child: const Text('Atualizar'),
          ),
        ],
      ),
    );
  }
}