import 'dart:async';

import 'package:flutter/material.dart';
import 'package:rotaoitimobile/class/classgerais.dart';
import 'package:rotaoitimobile/service/logcontroller.dart';

class LogScreen extends StatefulWidget {
  const LogScreen({super.key});

  @override
  State<LogScreen> createState() => _LogScreenState();
}

class _LogScreenState extends State<LogScreen> {
  final List<String> _logs = [];
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();

    //print("🔥 Tela de LOG aberta!");

    _logs.addAll(LogController.instance.buffer);

    LogController.instance.stream.listen((msg) {
      setState(() {
        _logs.add(msg);
      });

      // auto scroll
      Future.delayed(const Duration(milliseconds: 100), () {
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Logs do Sistema"),
        backgroundColor: AppColors.verdeEscuro,
      ),
      body: Container(
        color: Colors.black,
        child: ListView.builder(
          controller: _scrollController,
          itemCount: _logs.length,
          itemBuilder: (context, index) {
            return Text(
              _logs[index],
              style: const TextStyle(
                color: Colors.greenAccent,
                fontFamily: "monospace",
                fontSize: 14,
              ),
            );
          },
        ),
      ),
    );
  }
}
