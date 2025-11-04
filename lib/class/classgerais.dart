import 'dart:ui';

class AppColors {
  static const verdeNatural = Color(0xFFA4B494);
  static const verdeEscuro = Color(0xFF8DA084);
  static const begeMadeira = Color(0xFFDCC5A1);
  static const begeClaro = Color(0xFFEFE6D5);
  static const marromEscuro = Color(0xFF4B3832);
  static const pendente = Color(0xFFFFA500);
  static const concluida = Color(0xFF4CAF50);
  static const cancelada = Color(0xFFDD1616);
}

class Caminhao {
  final int id;
  final String nome;
  final String cor;
  final String placa;
  final String departamento;
  final int? userId;

  Caminhao({
    required this.id,
    required this.nome,
    required this.cor,
    required this.placa,
    required this.departamento,
    this.userId,
  });

  factory Caminhao.fromJson(Map<String, dynamic> json) {
    return Caminhao(
      id: json['id'],
      nome: json['nome'],
      cor: json['cor'],
      placa: json['placa'],
      departamento: json['departamento'],
      userId: json['user_id'],
    );
  }
}

class Entrega {
  int id;
  int nrEntrega;
  String cliente;
  String endereco;
  String bairro;
  String cidade;
  String estado;
  String telefone;
  String vendedor;
  String status;
  String? latitude;
  String? longitude;
  Caminhao? caminhao;
  String? obs;
  List<String> fotos;

  Entrega({
    required this.id,
    required this.nrEntrega,
    required this.cliente,
    required this.endereco,
    required this.bairro,
    required this.cidade,
    required this.estado,
    required this.telefone,
    required this.vendedor,
    required this.status,
    this.latitude,
    this.longitude,
    this.caminhao,
    this.obs,
    List<String>? fotos,
  }) : fotos = fotos ?? [];

  factory Entrega.fromJson(Map<String, dynamic> json) {
    return Entrega(
      id: json['id'] as int,
      nrEntrega: json['numero_pedido'] ?? 0,
      cliente: json['cliente'] ?? '',
      endereco: json['endereco'] ?? '',
      bairro: json['bairro'] ?? '',
      cidade: json['cidade'] ?? '',
      estado: json['estado'] ?? '',
      telefone: json['telefone'] ?? '',
      vendedor: json['vendedor'] ?? '',
      status: json['status'] ?? '',
      latitude: json['latitude']?.toString(),
      longitude: json['longitude']?.toString(),
      obs: json['obs']?.toString() ?? '',
      fotos: (json['fotos'] != null)
          ? List<String>.from(json['fotos'] as List)
          : [],
      caminhao: json['caminhao'] != null
          ? Caminhao.fromJson(json['caminhao'])
          : null,
    );
  }

  // Converter para JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'numero_pedido': nrEntrega,
      'cliente': cliente,
      'endereco': endereco,
      'bairro': bairro,
      'cidade': cidade,
      'estado': estado,
      'telefone': telefone,
      'vendedor': vendedor,
      'status': status,
      'latitude': latitude,
      'longitude': longitude,
      'obs': obs,
      'fotos': fotos,
    };
  }
}

class Abastecimento {
  final int? id;
  final int caminhaoId;
  final String motorista;
  final double litros;
  final double valor;
  final double valorTotal;
  final String posto;
  final String? obs;
  final DateTime dataHora;
  final bool enviado;
  final String? fotoPlaca;
  final String? fotoBomba;
  final String? fotoOdometro;
  final String? fotoMarcadorCombustivel;
  final String? fotoTalao;
  final String? fotoCupom;

  Abastecimento({
    this.id,
    required this.caminhaoId,
    required this.motorista,
    required this.litros,
    required this.valor,
    required this.valorTotal,
    required this.posto,
    this.obs,
    required this.dataHora,
    this.enviado = false,
    this.fotoPlaca,
    this.fotoBomba,
    this.fotoOdometro,
    this.fotoMarcadorCombustivel,
    this.fotoTalao,
    this.fotoCupom,
  });

  factory Abastecimento.fromJson(Map<String, dynamic> json) {
    return Abastecimento(
      id: json['id'],
      caminhaoId: json['caminhao_id'],
      motorista: json['motorista'] ?? '',
      litros: (json['litros'] ?? 0).toDouble(),
      valor: (json['valor_litro'] ?? 0).toDouble(),
      valorTotal: (json['valor_total'] ?? 0).toDouble(),
      posto: json['posto'] ?? '',
      obs: json['obs'] ?? '',
      dataHora: DateTime.parse(json['dataHora']),
      enviado: json['enviado'] == 1,
      fotoPlaca: json['foto_placa'],
      fotoBomba: json['foto_bomba'],
      fotoOdometro: json['foto_odometro'],
      fotoMarcadorCombustivel: json['foto_marcador_combustivel'],
      fotoTalao: json['foto_talao'],
      fotoCupom: json['foto_cupom'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'caminhao_id': caminhaoId,
      'motorista': motorista,
      'litros': litros,
      'valor_litro': valor,
      'valor_total': valorTotal,
      'posto': posto,
      'obs': obs,
      'dataHora': dataHora.toIso8601String(),
      'enviado': enviado ? 1 : 0,
      'foto_placa': fotoPlaca,
      'foto_bomba': fotoBomba,
      'foto_odometro': fotoOdometro,
      'foto_marcador_combustivel': fotoMarcadorCombustivel,
      'foto_talao': fotoTalao,
      'foto_cupom': fotoCupom,
    };
  }
}
