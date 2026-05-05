import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:network_info_plus/network_info_plus.dart';

/// FTP client with automatic mode negotiation.
///
/// Tries ACTIVE mode (PORT) first — avoids Windows Firewall blocking inbound
/// PASV ports on the PC.  Falls back to PASSIVE (PASV) automatically if the
/// server rejects the PORT command.
class FtpClientService {
  final String host;
  final int port;
  final String username;
  final String password;

  Socket? _ctrl;
  StreamSubscription? _sub;

  // Once PORT is rejected once, stay in passive mode for the session.
  bool _usePassive = false;

  // Producer-consumer buffer: lines that arrive before anyone awaits are not
  // silently dropped.
  final _lineBuffer = <String>[];
  final _lineWaiters = <Completer<String>>[];

  static const _timeout = Duration(seconds: 30);

  FtpClientService._({
    required this.host,
    required this.port,
    required this.username,
    required this.password,
  });

  /// Parse "192.168.1.100:2221" or "192.168.1.100" (default port 2221).
  factory FtpClientService.fromAddress(
      String address, String username, String password) {
    final parts = address.split(':');
    final h = parts[0].trim();
    final p = parts.length > 1 ? (int.tryParse(parts[1].trim()) ?? 2221) : 2221;
    return FtpClientService._(host: h, port: p, username: username, password: password);
  }

  Future<void> connect() async {
    try {
      _ctrl = await Socket.connect(host, port, timeout: _timeout);
    } on SocketException catch (e) {
      throw FtpException(
        'No se pudo conectar a $host:$port. '
        'Verificá que el servidor FTP esté corriendo en la PC y que estén '
        'en la misma red WiFi. (${e.message})',
      );
    }

    _sub = _ctrl!
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
          (line) {
            if (_lineWaiters.isNotEmpty) {
              _lineWaiters.removeAt(0).complete(line);
            } else {
              _lineBuffer.add(line);
            }
          },
          onError: (e) {
            for (final c in _lineWaiters) {
              if (!c.isCompleted) c.completeError(e);
            }
            _lineWaiters.clear();
          },
          cancelOnError: false,
        );

    await _expectCode(220);
    await _cmd('USER $username');
    try {
      await _expectCode(331);
    } on FtpException {
      throw FtpException('El servidor no aceptó el usuario "$username".');
    }
    await _cmd('PASS $password');
    try {
      await _expectCode(230);
    } on FtpException {
      throw FtpException(
          'Credenciales incorrectas. Verificá usuario y contraseña.');
    }
    await _cmd('TYPE I');
    await _expectCode(200);
  }

  /// Connect, list root, disconnect.  Throws [FtpException] on failure.
  Future<void> testConnection() async {
    try {
      await connect();
      await _transfer(
        command: 'LIST',
        work: (data) async => await data.drain<void>(),
      );
    } finally {
      await disconnect();
    }
  }

  Future<void> downloadFile(String remote, String localPath) async {
    await _transfer(
      command: 'RETR $remote',
      work: (data) async {
        final sink = File(localPath).openWrite();
        try {
          await sink.addStream(data.cast<List<int>>());
        } finally {
          await sink.close();
        }
      },
    );
  }

  Future<void> uploadFile(String localPath, String remote) async {
    await _transfer(
      command: 'STOR $remote',
      work: (data) => data.addStream(File(localPath).openRead()),
    );
  }

  Future<void> disconnect() async {
    try {
      await _cmd('QUIT');
    } catch (_) {}
    await _sub?.cancel();
    await _ctrl?.close();
    _ctrl = null;
  }

  // ── data channel ──────────────────────────────────────────────────────────

  Future<void> _transfer({
    required String command,
    required Future<void> Function(Socket data) work,
  }) async {
    if (!_usePassive) {
      try {
        await _transferActive(command: command, work: work);
        return;
      } on _PortRejected {
        _usePassive = true;
      }
    }
    await _transferPassive(command: command, work: work);
  }

  Future<void> _transferActive({
    required String command,
    required Future<void> Function(Socket data) work,
  }) async {
    final serverSock = await _setupPort(); // throws _PortRejected if PORT rejected
    try {
      await _cmd(command);
      final dataFuture = serverSock.first.timeout(
        _timeout,
        onTimeout: () => throw FtpException(
          'Timeout: el servidor no abrió la conexión de datos activa. '
          'Revisá que el firewall no bloquee conexiones entrantes al celular.',
        ),
      );
      await _expect1xx();
      final data = await dataFuture;
      try {
        await work(data);
      } finally {
        await data.close();
      }
      await _expectCode(226);
    } finally {
      await serverSock.close();
    }
  }

  Future<void> _transferPassive({
    required String command,
    required Future<void> Function(Socket data) work,
  }) async {
    await _cmd('PASV');
    final resp = await _readFinal();
    final (pasvHost, pasvPort) = _parsePasv(resp);
    await _cmd(command);
    await _expect1xx();
    final data = await Socket.connect(pasvHost, pasvPort, timeout: _timeout);
    try {
      await work(data);
    } finally {
      await data.close();
    }
    await _expectCode(226);
  }

  /// Opens a local ServerSocket, sends PORT, expects 200.
  /// Throws [_PortRejected] if the server rejects PORT.
  Future<ServerSocket> _setupPort() async {
    final rawIp = await NetworkInfo().getWifiIP();
    final myIp = rawIp?.trim();
    if (myIp == null || myIp.isEmpty) {
      throw FtpException(
        'Sin IP WiFi. Verificá que el WiFi esté activo y conectado '
        'a la misma red que la PC.',
      );
    }
    final serverSock = await ServerSocket.bind(InternetAddress.anyIPv4, 0);
    final p1 = serverSock.port ~/ 256;
    final p2 = serverSock.port % 256;
    await _cmd('PORT ${myIp.replaceAll('.', ',')},$p1,$p2');
    try {
      await _expectCode(200);
    } on FtpException {
      await serverSock.close();
      throw _PortRejected();
    }
    return serverSock;
  }

  (String, int) _parsePasv(String resp) {
    final m = RegExp(r'\((\d+),(\d+),(\d+),(\d+),(\d+),(\d+)\)').firstMatch(resp);
    if (m == null) throw FtpException('Respuesta PASV inválida: $resp');
    final ip = '${m[1]}.${m[2]}.${m[3]}.${m[4]}';
    final p = int.parse(m[5]!) * 256 + int.parse(m[6]!);
    return (ip, p);
  }

  // ── control channel helpers ───────────────────────────────────────────────

  Future<void> _cmd(String s) async => _ctrl!.write('$s\r\n');

  Future<void> _expectCode(int code) async {
    final line = await _readFinal();
    if (!line.startsWith('$code')) {
      throw FtpException('Error del servidor: $line');
    }
  }

  Future<void> _expect1xx() async {
    final line = await _readFinal();
    if (line.isEmpty || line[0] != '1') {
      throw FtpException('Error al iniciar transferencia: $line');
    }
  }

  // Reads lines until "NNN " (space at index 3) — final line of multi-line response.
  Future<String> _readFinal() async {
    String line;
    do {
      line = await _nextLine();
    } while (line.length < 4 || line[3] != ' ');
    return line;
  }

  Future<String> _nextLine() {
    if (_lineBuffer.isNotEmpty) return Future.value(_lineBuffer.removeAt(0));
    final c = Completer<String>();
    _lineWaiters.add(c);
    return c.future.timeout(
      _timeout,
      onTimeout: () => throw FtpException(
          'Timeout: el servidor FTP no respondió en ${_timeout.inSeconds} segundos.'),
    );
  }
}

class FtpException implements Exception {
  final String message;
  const FtpException(this.message);
  @override
  String toString() => message;
}

class _PortRejected implements Exception {}
