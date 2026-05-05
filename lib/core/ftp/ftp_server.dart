import 'dart:io';
import '../../core/database/database_file_manager.dart';
import 'ftp_session.dart';

class FtpServer {
  static const controlPort = 51041;
  static const dataPortStart = 51042;
  static const dataPortEnd = 51142;

  final String username;
  final String password;
  final DatabaseFileManager fileManager;

  ServerSocket? _server;
  int _nextDataPort = dataPortStart;

  FtpServer({
    required this.username,
    required this.password,
    required this.fileManager,
  });

  Future<void> start() async {
    _server = await ServerSocket.bind(InternetAddress.anyIPv4, controlPort);
    _server!.listen(_handleConnection, onError: (_) {});
  }

  Future<void> stop() async {
    await _server?.close();
    _server = null;
  }

  void _handleConnection(Socket socket) {
    final dataPort = _allocateDataPort();
    FtpSession(
      socket: socket,
      username: username,
      password: password,
      fileManager: fileManager,
      dataPort: dataPort,
    ).handle();
  }

  int _allocateDataPort() {
    final port = _nextDataPort;
    _nextDataPort = _nextDataPort >= dataPortEnd ? dataPortStart : _nextDataPort + 1;
    return port;
  }
}
