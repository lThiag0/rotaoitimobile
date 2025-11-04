import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:rotaoitimobile/class/classgerais.dart';

class LocalizacaoPage extends StatefulWidget {
  const LocalizacaoPage({super.key});

  @override
  State<LocalizacaoPage> createState() => _LocalizacaoPageState();
}

class _LocalizacaoPageState extends State<LocalizacaoPage> {
  final MapController _mapController = MapController();
  LatLng? _currentPosition;
  late StreamSubscription<Position> _positionStream;
  Marker? _truckMarker;
  bool _mapReady = false;
  String _status = "Aguardando GPS...";

  @override
  void initState() {
    super.initState();
    _verificarPermissoes();
  }

  Future<void> _verificarPermissoes() async {
    bool servicoAtivo = await Geolocator.isLocationServiceEnabled();
    LocationPermission permissao = await Geolocator.checkPermission();
    if (permissao == LocationPermission.denied) {
      permissao = await Geolocator.requestPermission();
    }
    if (!servicoAtivo ||
        permissao == LocationPermission.denied ||
        permissao == LocationPermission.deniedForever) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Permissão de localização negada")),
      );
      return;
    }
    _iniciarRastreamento();
  }

  void _iniciarRastreamento() async {
    // Posição inicial
    //Position pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);_updatePosition(pos);

    Position pos = await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.best,),);

    _updatePosition(pos);

    // Stream de posição
    _positionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
      ),
    ).listen((Position pos) {
      _updatePosition(pos);
    });
  }

  void _updatePosition(Position pos) {
    final newPosition = LatLng(pos.latitude, pos.longitude);

    setState(() {
      _currentPosition = newPosition;
      _truckMarker = Marker(
        point: newPosition,
        width: 60,
        height: 60,
        child: Image.asset('assets/truck_icon.png', width: 50, height: 50),
      );
      _status = "GPS ativo ✅";
    });

    if (_mapReady && _currentPosition != null) {
      _mapController.move(newPosition, 17);
    }
  }

  @override
  void dispose() {
    _positionStream.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Localização em Tempo Real"),
        backgroundColor: AppColors.verdeEscuro,
      ),
      body: Stack(
        children: [
          _currentPosition == null
              ? const Center(child: CircularProgressIndicator())
              : FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: _currentPosition ?? LatLng(-2.9057, -41.7759),
                    initialZoom: 17.0,
                    maxZoom: 19.0,
                    minZoom: 3.0,
                    onMapReady: () {
                      setState(() => _mapReady = true);
                      if (_currentPosition != null) {
                        _mapController.move(_currentPosition!, 17);
                      }
                    },
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.example.rotaoitimobile',
                    ),
                    if (_truckMarker != null)
                      MarkerLayer(markers: [_truckMarker!]),
                  ],
                ),
          Positioned(
            bottom: 16,
            left: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _status,
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
