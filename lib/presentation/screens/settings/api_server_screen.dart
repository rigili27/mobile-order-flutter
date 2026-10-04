import 'package:flutter/material.dart';
import 'api_server_card.dart';

/// Configuración manual del servidor API (URL + código de empresa + login) —
/// alternativa a emparejar por QR.
class ApiServerScreen extends StatelessWidget {
  final Future<void> Function()? onDatabaseReady;

  const ApiServerScreen({super.key, this.onDatabaseReady});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Servidor API')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ApiServerCard(onDatabaseReady: onDatabaseReady),
        ],
      ),
    );
  }
}
