import 'dart:async';
import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../class/classgerais.dart';

class DBHelper {
  static final DBHelper _instance = DBHelper._internal();
  factory DBHelper() => _instance;
  DBHelper._internal();

  static Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDB();
    return _db!;
  }

  Future<Database> _initDB() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'rotaoiti.db');
    //await deleteDatabase(path);

    return await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE usuarios (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            nome TEXT,
            email TEXT UNIQUE,
            senha_hash TEXT,
            token TEXT,
            id_usuario INTEGER,
            caminhao_id INTEGER,
            caminhao_nome TEXT,
            caminhao_cor TEXT,
            caminhao_placa TEXT
          )
        ''');

        await db.execute('''
          CREATE TABLE entregas_pendentes (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            entrega_id INTEGER UNIQUE,
            numero_pedido INTEGER UNIQUE,
            cliente TEXT,
            endereco TEXT,
            bairro TEXT,
            cidade TEXT,
            estado TEXT,
            telefone TEXT,
            vendedor TEXT,
            status TEXT,
            obs TEXT,
            latitude REAL,
            longitude REAL,
            fotos TEXT,
            enviado INTEGER DEFAULT 0,
            enviando INTEGER DEFAULT 0
          )
        ''');

        await db.execute('''
          CREATE TABLE entregas_offline (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            entrega_id INTEGER UNIQUE,
            numero_pedido INTEGER UNIQUE,
            cliente TEXT,
            endereco TEXT,
            bairro TEXT,
            cidade TEXT,
            estado TEXT,
            telefone TEXT,
            vendedor TEXT,
            status TEXT,
            obs TEXT,
            latitude F,
            longitude REAL,
            fotos TEXT,
            enviado INTEGER DEFAULT 0,
            enviando INTEGER DEFAULT 0
          )
        ''');

        await db.execute('''
          CREATE TABLE entregas(
            id INTEGER PRIMARY KEY,
            dados TEXT
          )
        ''');

        await db.execute('''
          CREATE TABLE localizacoes_pendentes (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            latitude REAL,
            longitude REAL,
            data TEXT
          )
        ''');

        await db.execute('''
          CREATE TABLE IF NOT EXISTS paradas_offline (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              caminhao_id INTEGER NOT NULL,
              latitude REAL NOT NULL,
              longitude REAL NOT NULL,
              inicio_parada TEXT NOT NULL,
              fim_parada TEXT NOT NULL,
              enviado INTEGER DEFAULT 0
          )
        ''');

        await db.execute('''
          CREATE TABLE IF NOT EXISTS abastecimentos_offline (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              caminhao_id INTEGER,
              departamento TEXT,
              motorista TEXT,
              combustivel TEXT,
              litros REAL,
              valor_litro REAL,
              valor_total REAL,
              odometro REAL,
              posto TEXT,
              data_hora TEXT,
              latitude REAL,
              longitude REAL,
              obs TEXT,
              foto_placa TEXT,
              foto_bomba TEXT,
              foto_odometro TEXT,
              foto_marcador_combustivel TEXT,
              foto_talao TEXT,
              foto_cupom TEXT,
              enviado INTEGER DEFAULT 0,
              enviando INTEGER DEFAULT 0
          )
        ''');

        await db.execute('''
          CREATE TABLE IF NOT EXISTS caminhoes (
            id INTEGER PRIMARY KEY,
            nome TEXT,
            cor TEXT,
            rastreamento_ligado INTEGER,
            placa TEXT,
            departamento TEXT,
            empresa TEXT,
            cnpj TEXT,
            user_id INTEGER,
            horario_rastreamento TEXT,
            dias_rastreamento TEXT,
            parada_longa_minutos INTEGER,
            garagem_latitude REAL,
            garagem_longitude REAL
          )
        ''');
      },
    );
  }

  // ---------------- Usuários ----------------
  Future<void> salvarUsuario(Map<String, dynamic> usuario) async {
    final db = await database;
    final dados = {
      ...usuario,
      'caminhao_id': usuario['caminhao_id'],
      'caminhao_nome': usuario['caminhao_nome'],
      'caminhao_cor': usuario['caminhao_cor'],
      'caminhao_placa': usuario['caminhao_placa'],
    };
    await db.insert(
      'usuarios',
      dados,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<Map<String, dynamic>?> buscarUsuario(String email) async {
    final db = await database;
    final res = await db.query(
      'usuarios',
      where: 'email = ?',
      whereArgs: [email],
    );
    if (res.isNotEmpty) return res.first;
    return null;
  }

  Future<Map<String, dynamic>?> buscarUsuarioLocal() async {
    final db = await database;
    final res = await db.query('usuarios', orderBy: 'id DESC', limit: 1);
    if (res.isNotEmpty) return res.first;
    return null;
  }

  Future<Map<String, dynamic>?> buscarUsuarioLogado() async {
    final db = await database;
    final res = await db.query(
      'usuarios',
      orderBy: 'id_usuario DESC',
      limit: 1,
    );
    if (res.isNotEmpty) return res.first;
    return null;
  }

  Future<void> limparUsuarios() async {
    final db = await database;
    await db.delete('usuarios');
  }

  // ---------------- Entregas ----------------

  Future<void> salvarEntregasPendentes(
    List<Map<String, dynamic>> entregas, {
    bool replace = false,
  }) async {
    final db = await database;

    if (replace) {
      await db.delete('entregas_pendentes');
    }

    final batch = db.batch();
    for (var e in entregas) {
      batch.insert(
        'entregas_pendentes',
        e,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<void> salvarEntregaOffline(Map<String, dynamic> entrega) async {
    final db = await database;

    final dados = {
      ...entrega,
      'obs': entrega['obs']?.toString() ?? '',
      'latitude': entrega['latitude']?.toString() ?? '',
      'longitude': entrega['longitude']?.toString() ?? '',
      'fotos': jsonEncode(entrega['fotos'] ?? []),
      'enviado': entrega['enviado'] ?? 0,
      'enviando': entrega['enviando'] ?? 0,
    };

    await db.insert(
      'entregas_offline',
      dados,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    if (entrega['entrega_id'] != null) {
      await db.delete(
        'entregas_pendentes',
        where: 'entrega_id = ?',
        whereArgs: [entrega['entrega_id']],
      );
    }
  }

  Future<void> deletarEntregaOffline(int entregaId) async {
    final db = await database;
    await db.delete(
      'entregas_offline',
      where: 'entrega_id = ?',
      whereArgs: [entregaId],
    );
  }

  Future<List<Entrega>> buscarEntregasPendentes() async {
    final db = await database;
    final res = await db.query(
      'entregas_pendentes',
      where:
          'enviado = ? AND (enviando IS NULL OR enviando = 0) AND (status = ? OR status = ?)',
      whereArgs: [0, 'concluida', 'parcial'],
    );

    return res.map((map) {
      List<String> fotos = [];
      if (map['fotos'] != null && map['fotos'].toString().isNotEmpty) {
        try {
          fotos = List<String>.from(jsonDecode(map['fotos'] as String));
        } catch (_) {
          fotos = [];
        }
      }
      return Entrega(
        id: map['entrega_id'] as int,
        nrEntrega: int.tryParse(map['numero_pedido']?.toString() ?? '0') ?? 0,
        cliente: map['cliente']?.toString() ?? '',
        endereco: map['endereco']?.toString() ?? '',
        bairro: map['bairro']?.toString() ?? '',
        cidade: map['cidade']?.toString() ?? '',
        estado: map['estado']?.toString() ?? '',
        telefone: map['telefone']?.toString() ?? '',
        vendedor: map['vendedor']?.toString() ?? '',
        status: map['status']?.toString() ?? 'pendente',
        latitude: map['latitude']?.toString(),
        longitude: map['longitude']?.toString(),
        obs: map['obs']?.toString() ?? '',
        fotos: fotos,
        caminhao: null,
      );
    }).toList();
  }

  Future<List<Entrega>> buscarEntregasOffline() async {
    final db = await database;
    final res = await db.query(
      'entregas_offline',
      where:
          'enviado = ? AND (enviando IS NULL OR enviando = 0) AND (status = ? OR status = ?)',
      whereArgs: [0, 'concluida', 'parcial'],
    );

    return res.map((map) {
      List<String> fotos = [];
      if (map['fotos'] != null && map['fotos'].toString().isNotEmpty) {
        try {
          fotos = List<String>.from(jsonDecode(map['fotos'] as String));
        } catch (_) {
          fotos = [];
        }
      }
      return Entrega(
        id: map['entrega_id'] as int,
        nrEntrega: int.tryParse(map['numero_pedido']?.toString() ?? '0') ?? 0,
        cliente: map['cliente']?.toString() ?? '',
        endereco: map['endereco']?.toString() ?? '',
        bairro: map['bairro']?.toString() ?? '',
        cidade: map['cidade']?.toString() ?? '',
        estado: map['estado']?.toString() ?? '',
        telefone: map['telefone']?.toString() ?? '',
        vendedor: map['vendedor']?.toString() ?? '',
        status: map['status']?.toString() ?? 'pendente',
        latitude: map['latitude']?.toString(),
        longitude: map['longitude']?.toString(),
        obs: map['obs']?.toString() ?? '',
        fotos: fotos,
        caminhao: null,
      );
    }).toList();
  }

  Future<List<Entrega>> buscarTodasEntregas() async {
    final db = await database;
    final res = await db.query('entregas_pendentes');

    return res.map((map) {
      List<String> fotos = [];
      if (map['fotos'] != null && map['fotos'].toString().isNotEmpty) {
        try {
          fotos = List<String>.from(jsonDecode(map['fotos'] as String));
        } catch (_) {
          fotos = [];
        }
      }
      return Entrega(
        id: map['entrega_id'] as int,
        nrEntrega: int.tryParse(map['numero_pedido']?.toString() ?? '0') ?? 0,
        cliente: map['cliente']?.toString() ?? '',
        endereco: map['endereco']?.toString() ?? '',
        bairro: map['bairro']?.toString() ?? '',
        cidade: map['cidade']?.toString() ?? '',
        estado: map['estado']?.toString() ?? '',
        telefone: map['telefone']?.toString() ?? '',
        vendedor: map['vendedor']?.toString() ?? '',
        status: (map['enviado'] == 1
            ? 'concluida'
            : map['status']?.toString() ?? 'pendente'),
        latitude: map['latitude']?.toString(),
        longitude: map['longitude']?.toString(),
        fotos: fotos,
        caminhao: null,
      );
    }).toList();
  }

  Future<void> salvarEntregas(List<Entrega> entregas) async {
    final db = await database;
    await db.delete('entregas');
    for (var entrega in entregas) {
      await db.insert('entregas', {
        'dados': jsonEncode(entrega.toJson()),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }

  Future<List<Entrega>> buscarEntregas() async {
    final db = await database;
    final result = await db.query('entregas');

    return result.map((e) {
      final data = jsonDecode(e['dados'] as String) as Map<String, dynamic>;
      return Entrega.fromJson(data);
    }).toList();
  }

  Future<void> salvarOuAtualizarEntregas(
    List<Map<String, dynamic>> entregas,
  ) async {
    final db = await database;
    for (var e in entregas) {
      await db.insert(
        'entregas_offline',
        e,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  }

  // ---------------- Marcação de envio ----------------
  Future<void> marcarEntregaEnviando(int entregaId) async {
    final db = await database;
    await db.update(
      'entregas_offline',
      {'enviando': 1},
      where: 'entrega_id = ?',
      whereArgs: [entregaId],
    );
  }

  Future<void> marcarEntregaEnviada(int entregaId) async {
    final db = await database;
    await db.update(
      'entregas_offline',
      {'enviado': 1, 'enviando': 0},
      where: 'entrega_id = ?',
      whereArgs: [entregaId],
    );
  }

  Future<void> marcarEntregaFalha(int entregaId) async {
    final db = await database;
    await db.update(
      'entregas_offline',
      {'enviando': 0},
      where: 'entrega_id = ?',
      whereArgs: [entregaId],
    );
  }

  // Salvar localização pendente
  Future<void> salvarLocalizacaoPendente(double lat, double lng) async {
    final db = await database;
    await db.insert('localizacoes_pendentes', {
      'latitude': lat,
      'longitude': lng,
      'data': DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // Buscar localizações pendentes
  Future<List<Map<String, dynamic>>> buscarLocalizacoesPendentes() async {
    final db = await database;
    return await db.query('localizacoes_pendentes', orderBy: "data ASC");
  }

  // Remover localização enviada
  Future<void> removerLocalizacaoPendente(int id) async {
    final db = await database;
    await db.delete('localizacoes_pendentes', where: 'id = ?', whereArgs: [id]);
  }

  // ---------------- Abastecimentos Offline ----------------
  Future<void> salvarAbastecimentoOffline(
    Map<String, dynamic> abastecimento,
  ) async {
    final db = await database;

    // Garante que a lista de fotos exista
    final fotos = abastecimento['fotos'] ?? [];

    final dados = {
      'caminhao_id': abastecimento['caminhao_id'],
      'departamento': abastecimento['departamento'],
      'motorista': abastecimento['motorista'],
      'combustivel': abastecimento['combustivel'],
      'litros': double.tryParse(abastecimento['litros'].toString()) ?? 0,
      'valor_litro':
          double.tryParse(abastecimento['valor_litro'].toString()) ?? 0,
      'valor_total':
          double.tryParse(abastecimento['valor_total'].toString()) ?? 0,
      'odometro': double.tryParse(abastecimento['odometro'].toString()) ?? 0,
      'posto': abastecimento['posto'],
      'obs': abastecimento['obs'],
      'data_hora': abastecimento['data_hora'],
      'latitude': abastecimento['latitude'],
      'longitude': abastecimento['longitude'],
      'foto_placa': fotos.isNotEmpty ? fotos[0] : null,
      'foto_bomba': fotos.length > 1 ? fotos[1] : null,
      'foto_odometro': fotos.length > 2 ? fotos[2] : null,
      'foto_marcador_combustivel': fotos.length > 3 ? fotos[3] : null,
      'foto_talao': fotos.length > 4 ? fotos[4] : null,
      'foto_cupom': fotos.length > 5 ? fotos[5] : null,
      'enviado': abastecimento['enviado'] ?? 0,
      'enviando': abastecimento['enviando'] ?? 0,
    };

    await db.insert(
      'abastecimentos_offline',
      dados,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> deletarAbastecimentoOffline(int id) async {
    final db = await database;
    await db.delete('abastecimentos_offline', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Map<String, dynamic>>> buscarAbastecimentosOffline() async {
    final db = await database;
    final res = await db.query(
      'abastecimentos_offline',
      where: 'enviado = ? AND (enviando IS NULL OR enviando = 0)',
      whereArgs: [0],
      orderBy: 'id ASC',
    );

    return res.map((map) {
      if (map['fotos'] != null && map['fotos'].toString().isNotEmpty) {
        map['fotos'] = List<String>.from(jsonDecode(map['fotos'] as String));
      } else {
        map['fotos'] = [];
      }
      return map;
    }).toList();
  }

  Future<void> marcarAbastecimentoEnviando(int id) async {
    final db = await database;
    await db.update(
      'abastecimentos_offline',
      {'enviando': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> marcarAbastecimentoEnviado(int id) async {
    final db = await database;
    await db.update(
      'abastecimentos_offline',
      {'enviado': 1, 'enviando': 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> marcarAbastecimentoFalha(int id) async {
    final db = await database;
    await db.update(
      'abastecimentos_offline',
      {'enviando': 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // ---------------- Caminhões ----------------
  Future<void> salvarCaminhoes(List<Map<String, dynamic>> caminhoes) async {
    final db = await database;
    final batch = db.batch();

    for (var c in caminhoes) {
      batch.insert('caminhoes', {
        'id': c['id'],
        'nome': c['nome'],
        'cor': c['cor'],
        'placa': c['placa'],
        'user_id': c['user_id'],
        'departamento': c['departamento'],
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }

    await batch.commit(noResult: true);
  }

  Future<void> atualizarCaminhoes(List<Map<String, dynamic>> caminhoes) async {
    final db = await database;
    final batch = db.batch();

    // Limpa tabela antes de atualizar (garante consistência)
    await db.delete('caminhoes');

    for (var c in caminhoes) {
      batch.insert('caminhoes', {
        'id': c['id'],
        'nome': c['nome'],
        'cor': c['cor'],
        'rastreamento_ligado': (c['rastreamento_ligado'] == true)
            ? 1
            : 0, // bool → int
        'placa': c['placa'],
        'departamento': c['departamento'],
        'empresa': c['empresa'],
        'cnpj': c['cnpj'],
        'user_id': c['user_id'],
        'horario_rastreamento': c['horario_rastreamento'],
        // converte lista para string JSON
        'dias_rastreamento': jsonEncode(c['dias_rastreamento']),
        'parada_longa_minutos': c['parada_longa_minutos'],
        'garagem_latitude': c['garagem_latitude'],
        'garagem_longitude': c['garagem_longitude'],
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }

    await batch.commit(noResult: true);
  }

  Future<List<Map<String, dynamic>>> buscarCaminhoes() async {
    final db = await database;
    return await db.query('caminhoes', orderBy: 'nome ASC');
  }

  Future<Map<String, dynamic>?> buscarCaminhaoPorUsuario(int userId) async {
    final db = await database;
    final result = await db.query(
      'caminhoes',
      where: 'user_id = ?',
      whereArgs: [userId],
      limit: 1,
    );
    if (result.isNotEmpty) {
      return result.first;
    }
    return null;
  }

  Future<void> limparCaminhoes() async {
    final db = await database;
    await db.delete('caminhoes');
  }

  Future<void> atualizarCaminhaoVinculado(Map<String, dynamic> caminhao) async {
    final db = await database;

    // Pega o usuário logado
    final usuario = await buscarUsuarioLocal();
    if (usuario == null) return;

    final dadosAtualizados = {
      'caminhao_id': caminhao['id'],
      'caminhao_nome': caminhao['nome'],
      'caminhao_cor': caminhao['cor'],
      'caminhao_placa': caminhao['placa'],
    };

    await db.update(
      'usuarios',
      dadosAtualizados,
      where: 'id = ?',
      whereArgs: [usuario['id']],
    );
  }
}
