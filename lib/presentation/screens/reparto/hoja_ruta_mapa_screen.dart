import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../../core/nav_launcher.dart';
import '../../../data/models/reparto_models.dart';
import '../../providers/reparto_provider.dart';
import 'parada_screen.dart';

/// Mapa de la hoja de ruta (OpenStreetMap, gratis, sin API key — igual que
/// el ERP). Recorrido optimizado + paradas numeradas + posición del
/// repartidor. Cada parada abre un panel con "Navegar" (ruteo externo).
class HojaRutaMapaScreen extends StatefulWidget {
  const HojaRutaMapaScreen({super.key, required this.hojaId});

  final int hojaId;

  @override
  State<HojaRutaMapaScreen> createState() => _HojaRutaMapaScreenState();
}

class _HojaRutaMapaScreenState extends State<HojaRutaMapaScreen> {
  final _map = MapController();
  LatLng? _yo;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ubicarme();
      _ajustarVista();
    });
  }

  HojaRuta? get _hoja =>
      context.read<RepartoProvider>().hojas.where((h) => h.id == widget.hojaId).firstOrNull;

  List<LatLng> get _paradasLatLng => [
        for (final p in _hoja?.paradas ?? const <Parada>[])
          if (p.lat != null && p.lng != null) LatLng(p.lat!, p.lng!),
      ];

  Future<void> _ubicarme({bool centrar = false}) async {
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) return;
      final pos = await Geolocator.getCurrentPosition();
      if (!mounted) return;
      setState(() => _yo = LatLng(pos.latitude, pos.longitude));
      if (centrar && _yo != null) _map.move(_yo!, 15);
    } catch (_) {}
  }

  void _ajustarVista() {
    final puntos = [..._paradasLatLng, if (_yo != null) _yo!];
    if (puntos.isEmpty) return;
    if (puntos.length == 1) {
      _map.move(puntos.first, 14);
      return;
    }
    _map.fitCamera(CameraFit.coordinates(
      coordinates: puntos,
      padding: const EdgeInsets.all(48),
      maxZoom: 16,
    ));
  }

  void _abrirParada(Parada p) {
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${p.orden}. ${p.cliente}',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              if (p.direccion != null && p.direccion!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(p.direccion!, style: const TextStyle(color: Colors.grey)),
                ),
              const SizedBox(height: 8),
              Text('Estado: ${Parada.estadoLabel(p.estado)}',
                  style: const TextStyle(fontSize: 13)),
              const SizedBox(height: 16),
              Row(
                children: [
                  if (p.lat != null && p.lng != null)
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () async {
                          Navigator.pop(context);
                          final ok = await abrirNavegacion(p.lat!, p.lng!, etiqueta: p.cliente);
                          if (!ok && mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                                content: Text('No hay una app de mapas para navegar.')));
                          }
                        },
                        icon: const Icon(Icons.navigation),
                        label: const Text('Navegar'),
                      ),
                    ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        Navigator.push(context,
                            MaterialPageRoute(builder: (_) => ParadaScreen(paradaId: p.id)));
                      },
                      icon: const Icon(Icons.list_alt),
                      label: const Text('Ver parada'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    context.watch<RepartoProvider>(); // redibuja al sincronizar
    final hoja = _hoja;

    if (hoja == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Mapa')),
        body: const Center(child: Text('La hoja ya no está disponible.')),
      );
    }

    final paradasConCoords = [
      for (final p in hoja.paradas)
        if (p.lat != null && p.lng != null) p,
    ];
    final recorrido = [
      for (final pt in hoja.recorrido)
        if (pt.length >= 2) LatLng(pt[0], pt[1]),
    ];

    final centroInicial = _paradasLatLng.isNotEmpty
        ? _paradasLatLng.first
        : const LatLng(-34.6037, -58.3816);

    return Scaffold(
      appBar: AppBar(
        title: Text('Mapa · Hoja Nº ${hoja.id}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.my_location),
            tooltip: 'Mi ubicación',
            onPressed: () => _ubicarme(centrar: true),
          ),
        ],
      ),
      body: FlutterMap(
        mapController: _map,
        options: MapOptions(
          initialCenter: centroInicial,
          initialZoom: 12,
        ),
        children: [
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'com.labge.tomapedidos',
            maxZoom: 19,
          ),
          if (recorrido.length > 1)
            PolylineLayer(polylines: [
              Polyline(points: recorrido, strokeWidth: 4, color: const Color(0xB32A78D6)),
            ]),
          MarkerLayer(markers: [
            for (final p in paradasConCoords)
              Marker(
                point: LatLng(p.lat!, p.lng!),
                width: 34,
                height: 34,
                child: GestureDetector(
                  onTap: () => _abrirParada(p),
                  child: _PinNumerado(
                    numero: p.orden,
                    color: p.resuelta ? Colors.green : const Color(0xFF2A78D6),
                  ),
                ),
              ),
            if (_yo != null)
              Marker(
                point: _yo!,
                width: 22,
                height: 22,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.blueAccent,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 3),
                  ),
                ),
              ),
          ]),
          const RichAttributionWidget(attributions: [
            TextSourceAttribution('OpenStreetMap contributors'),
          ]),
        ],
      ),
    );
  }
}

class _PinNumerado extends StatelessWidget {
  const _PinNumerado({required this.numero, required this.color});

  final int numero;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 4)],
      ),
      child: Text('$numero',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
    );
  }
}
