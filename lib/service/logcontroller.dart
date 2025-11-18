import 'dart:async';

class LogController {
  static final LogController instance = LogController._internal();
  LogController._internal();

  final List<String> _buffer = []; // salva histórico

  final _logStream = StreamController<String>.broadcast();

  Stream<String> get stream => _logStream.stream;

  List<String> get buffer => List.unmodifiable(_buffer);

  void addLog(String log) {
    _buffer.add(log);
    _logStream.add(log);
    //print("📌 LOG ADD $log");
  }

  void dispose() {
    _logStream.close();
  }
}
