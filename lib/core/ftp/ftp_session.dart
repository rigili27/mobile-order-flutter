import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../../core/database/database_file_manager.dart';

class FtpSession {
  final Socket socket;
  final String username;
  final String password;
  final DatabaseFileManager fileManager;
  final int dataPort;

  bool _authenticated = false;
  bool _awaitingPassword = false;
  ServerSocket? _dataServer;

  static const _crlf = '\r\n';

  FtpSession({
    required this.socket,
    required this.username,
    required this.password,
    required this.fileManager,
    required this.dataPort,
  });

  void handle() {
    _send('220 TomaPedidos FTP Server ready.');
    socket
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
          _onCommand,
          onDone: _cleanup,
          onError: (_) => _cleanup(),
        );
  }

  void _send(String msg) {
    try {
      socket.write('$msg$_crlf');
    } catch (_) {}
  }

  Future<void> _onCommand(String line) async {
    final parts = line.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty) return;
    final cmd = parts[0].toUpperCase();
    final arg = parts.length > 1 ? parts.sublist(1).join(' ') : '';

    switch (cmd) {
      case 'USER':
        _awaitingPassword = arg == username;
        _send('331 Password required for $arg.');
      case 'PASS':
        if (_awaitingPassword && arg == password) {
          _authenticated = true;
          _send('230 User logged in.');
        } else {
          _authenticated = false;
          _send('530 Login incorrect.');
        }
      case 'SYST':
        _send('215 UNIX Type: L8');
      case 'TYPE':
        _send('200 Type set.');
      case 'PWD':
        _send('257 "/" is current directory.');
      case 'CWD':
        _send('250 Directory changed.');
      case 'CDUP':
        _send('250 Directory changed.');
      case 'QUIT':
        _send('221 Goodbye.');
        await _cleanup();
      case 'PASV':
        if (!_authenticated) { _send('530 Not logged in.'); return; }
        await _setupPassive();
      case 'LIST':
        if (!_authenticated) { _send('530 Not logged in.'); return; }
        await _handleList();
      case 'RETR':
        if (!_authenticated) { _send('530 Not logged in.'); return; }
        await _handleRetr(arg);
      case 'STOR':
        if (!_authenticated) { _send('530 Not logged in.'); return; }
        await _handleStor(arg);
      default:
        _send('502 Command not implemented.');
    }
  }

  Future<void> _setupPassive() async {
    await _dataServer?.close();
    _dataServer = await ServerSocket.bind(InternetAddress.anyIPv4, dataPort);
    final ip = socket.address.address.replaceAll('.', ',');
    final p1 = dataPort >> 8;
    final p2 = dataPort & 0xFF;
    _send('227 Entering Passive Mode ($ip,$p1,$p2).');
  }

  Future<Socket?> _acceptDataConnection() async {
    if (_dataServer == null) return null;
    final completer = Completer<Socket>();
    late StreamSubscription sub;
    sub = _dataServer!.listen((s) {
      sub.cancel();
      completer.complete(s);
    });
    try {
      return await completer.future.timeout(const Duration(seconds: 10));
    } catch (_) {
      return null;
    }
  }

  Future<void> _handleList() async {
    _send('150 Opening data connection for directory listing.');
    final conn = await _acceptDataConnection();
    if (conn == null) { _send('425 No data connection.'); return; }

    try {
      final activeFile = File(await fileManager.activePath);
      final lines = StringBuffer();

      if (await activeFile.exists()) {
        final stat = await activeFile.stat();
        lines.writeln(_formatListEntry('moviles.db', stat.size));
      }

      conn.write(lines.toString());
      await conn.flush();
    } finally {
      await conn.close();
    }
    _send('226 Transfer complete.');
  }

  Future<void> _handleRetr(String filename) async {
    final activeFile = File(await fileManager.activePath);
    if (!await activeFile.exists()) {
      _send('550 File not found.');
      return;
    }

    File exportFile;
    try {
      exportFile = await fileManager.prepareExport();
    } catch (_) {
      _send('550 Error al preparar el archivo para descarga.');
      return;
    }

    _send('150 Opening data connection for moviles.db.');
    final conn = await _acceptDataConnection();
    if (conn == null) { _send('425 No data connection.'); return; }

    try {
      await exportFile.openRead().pipe(conn);
    } finally {
      await conn.close();
    }
    _send('226 Transfer complete.');
  }

  Future<void> _handleStor(String filename) async {
    _send('150 Opening data connection for $filename.');
    final conn = await _acceptDataConnection();
    if (conn == null) { _send('425 No data connection.'); return; }

    final tempPath = await fileManager.tempPath;
    final output = File(tempPath).openWrite();

    try {
      await output.addStream(conn.cast<List<int>>());
    } finally {
      await conn.close();
      await output.close();
    }

    final result = await fileManager.importFromTemp();
    if (result.ok) {
      _send('226 Transfer complete. Database imported successfully.');
    } else {
      _send('550 Import failed: ${result.errorMessage}');
    }
  }

  String _formatListEntry(String name, int size) {
    final now = DateTime.now();
    final month = _monthAbbr(now.month);
    final day = now.day.toString().padLeft(2);
    final time = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    return '-rw-r--r-- 1 ftp ftp $size $month $day $time $name';
  }

  String _monthAbbr(int m) =>
      const ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'][m - 1];

  Future<void> _cleanup() async {
    try { socket.destroy(); } catch (_) {}
    await _dataServer?.close();
    _dataServer = null;
  }
}
