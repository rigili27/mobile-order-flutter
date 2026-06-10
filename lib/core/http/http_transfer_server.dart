import 'dart:io';
import '../database/database_file_manager.dart';
import '../database/orden_preparacion_database_helper.dart';

/// Minimal HTTP server that lets the PC exchange the SQLite database with the
/// device over local WiFi using only a web browser — no FTP, no firewall config.
///
/// GET  /            → HTML page with download link + upload form
/// GET  /moviles.db  → streams a copy of the active DB (export)
/// POST /upload      → receives raw bytes, validates and imports as new DB
class HttpTransferServer {
  static const defaultPort = 8080;

  HttpServer? _server;

  bool get isRunning => _server != null;

  String _pcPath = 'C:/ftp';
  String _vendorName = '';
  String _appVersion = '';
  bool _ordenPreparacion = false;

  Future<void> start({
    int port = defaultPort,
    String pcPath = 'C:/ftp',
    String vendorName = '',
    String appVersion = '',
    bool ordenPreparacion = false,
    Future<void> Function()? onImportSuccess,
  }) async {
    if (_server != null) return;
    _pcPath = pcPath;
    _vendorName = vendorName;
    _appVersion = appVersion;
    _ordenPreparacion = ordenPreparacion;
    _server = await HttpServer.bind(InternetAddress.anyIPv4, port);
    _server!.listen((req) => _handle(req, onImportSuccess));
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }

  // ── request handler ───────────────────────────────────────────────────────

  Future<void> _handle(
      HttpRequest req, Future<void> Function()? onImportSuccess) async {
    try {
      final path = req.uri.path;
      if (req.method == 'GET' && path == '/') {
        await _serveHtml(req);
      } else if (req.method == 'GET' && path == '/moviles.db') {
        await _handleDownload(req);
      } else if (req.method == 'GET' && path == '/backup.db') {
        await _handleBackupDownload(req);
      } else if (req.method == 'GET' && path == '/orden_preparacion.db') {
        if (!_ordenPreparacion) {
          req.response.statusCode = HttpStatus.notFound;
          await req.response.close();
          return;
        }
        await _handleOrdenPreparacionDownload(req);
      } else if (req.method == 'POST' && path == '/upload') {
        await _handleUpload(req, onImportSuccess);
      } else {
        req.response.statusCode = HttpStatus.notFound;
        await req.response.close();
      }
    } catch (_) {
      try {
        req.response.statusCode = HttpStatus.internalServerError;
        await req.response.close();
      } catch (_) {}
    }
  }

  Future<void> _serveHtml(HttpRequest req) async {
    req.response.headers.contentType = ContentType.html;
    req.response.write(_buildHtml(_pcPath, _vendorName, _appVersion, _ordenPreparacion));
    await req.response.close();
  }

  Future<void> _handleDownload(HttpRequest req) async {
    final activePath = await DatabaseFileManager.instance.activePath;
    if (!await File(activePath).exists()) {
      req.response.statusCode = HttpStatus.serviceUnavailable;
      req.response.headers.contentType = ContentType.text;
      req.response.write('Sin base de datos. Enviá una desde la PC primero.');
      await req.response.close();
      return;
    }
    final file = await DatabaseFileManager.instance.prepareExport();
    req.response.headers
      ..set(HttpHeaders.contentTypeHeader, 'application/octet-stream')
      ..set('Content-Disposition', 'attachment; filename="moviles.db"')
      ..contentLength = await file.length();
    await req.response.addStream(file.openRead());
    await req.response.close();
  }

  Future<void> _handleBackupDownload(HttpRequest req) async {
    final backupPath = await DatabaseFileManager.instance.backupPath;
    final backupFile = File(backupPath);
    if (!await backupFile.exists()) {
      req.response.statusCode = HttpStatus.notFound;
      req.response.headers.contentType = ContentType.text;
      req.response.write('No hay base de datos de respaldo disponible.');
      await req.response.close();
      return;
    }
    req.response.headers
      ..set(HttpHeaders.contentTypeHeader, 'application/octet-stream')
      ..set('Content-Disposition', 'attachment; filename="backup_moviles.db"')
      ..contentLength = await backupFile.length();
    await req.response.addStream(backupFile.openRead());
    await req.response.close();
  }

  Future<void> _handleOrdenPreparacionDownload(HttpRequest req) async {
    final ordenPath = await OrdenPreparacionDatabaseHelper.instance.dbPath;
    final ordenFile = File(ordenPath);
    if (!await ordenFile.exists()) {
      req.response.statusCode = HttpStatus.notFound;
      req.response.headers.contentType = ContentType.text;
      req.response.write('No hay órdenes de preparación disponibles.');
      await req.response.close();
      return;
    }
    req.response.headers
      ..set(HttpHeaders.contentTypeHeader, 'application/octet-stream')
      ..set('Content-Disposition',
          'attachment; filename="moviles_orden_preparacion.db"')
      ..contentLength = await ordenFile.length();
    await req.response.addStream(ordenFile.openRead());
    await req.response.close();
  }

  Future<void> _handleUpload(
      HttpRequest req, Future<void> Function()? onImportSuccess) async {
    final bytes = await req.fold<List<int>>(
        [], (buf, chunk) => buf..addAll(chunk));

    final tempPath = await DatabaseFileManager.instance.tempPath;
    await File(tempPath).writeAsBytes(bytes);

    final result = await DatabaseFileManager.instance.importFromTemp();
    if (result.ok) {
      req.response.statusCode = HttpStatus.ok;
      req.response.write('ok');
      await req.response.close();
      if (onImportSuccess != null) await onImportSuccess();
    } else {
      req.response.statusCode = HttpStatus.badRequest;
      req.response.write(result.errorMessage ?? 'Error al importar');
      await req.response.close();
    }
  }
}

// ── HTML served to the PC browser ─────────────────────────────────────────────

String _buildHtml(String pcPath, String vendorName, String appVersion, bool ordenPreparacion) => '''<!DOCTYPE html>
<html lang="es">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Toma Pedidos — Transferencia de Base de Datos</title>
<style>
  *{box-sizing:border-box}
  body{font-family:sans-serif;max-width:540px;margin:48px auto;padding:16px;color:#333}
  h1{color:#1565C0;margin-bottom:8px}
  .vendor-badge{background:#e3f2fd;color:#0d47a1;border:1px solid #90caf9;
                border-radius:8px;padding:10px 14px;margin-bottom:24px;
                font-size:.95rem;font-weight:600}
  .card{border:1px solid #ddd;border-radius:10px;padding:20px;margin-bottom:20px}
  h2{margin:0 0 12px;font-size:1rem;color:#555}
  .btn{display:block;width:100%;padding:12px;background:#1565C0;color:#fff;
       border:none;border-radius:6px;font-size:1rem;cursor:pointer;
       text-align:center;text-decoration:none}
  .btn:hover{background:#0d47a1}
  .btn-green{background:#2e7d32}.btn-green:hover{background:#1b5e20}
  .btn-amber{background:#e65100}.btn-amber:hover{background:#bf360c}
  input[type=file]{display:block;width:100%;padding:8px;margin-bottom:12px;
                   border:1px solid #ccc;border-radius:4px}
  #msg{margin-top:12px;padding:10px;border-radius:6px;display:none;font-size:.9rem}
  .ok{background:#e8f5e9;color:#2e7d32;border:1px solid #a5d6a7}
  .err{background:#ffebee;color:#c62828;border:1px solid #ef9a9a}
  .loading{background:#e3f2fd;color:#1565C0;border:1px solid #90caf9}
  /* modal */
  #overlay{display:none;position:fixed;inset:0;background:rgba(0,0,0,.5);
            align-items:center;justify-content:center;z-index:100}
  #overlay.show{display:flex}
  #modal{background:#fff;border-radius:12px;padding:24px;max-width:420px;
         width:90%;box-shadow:0 4px 24px rgba(0,0,0,.25)}
  #modal h3{margin:0 0 12px;color:#b71c1c;font-size:1.1rem}
  #modal p{margin:0 0 20px;font-size:.9rem;line-height:1.5}
  .modal-btns{display:flex;gap:10px;justify-content:flex-end}
  .modal-btns button{padding:9px 20px;border:none;border-radius:6px;
                     font-size:.95rem;cursor:pointer}
  #btn-cancel{background:#eee;color:#333}#btn-cancel:hover{background:#ddd}
  #btn-confirm{background:#c62828;color:#fff}#btn-confirm:hover{background:#b71c1c}
</style>
</head>
<body>
<h1>Toma Pedidos — Transferencia DB</h1>
<div class="vendor-badge">📱 Conectado al celular de ${vendorName.isNotEmpty ? vendorName : 'vendedor desconocido'}</div>

<div class="card">
  <h2>📥 Descargar base de datos del celular → PC</h2>
  <a class="btn" href="/moviles.db" download="moviles.db">Descargar moviles.db</a>
</div>

<div class="card">
  <h2>💾 Descargar base de datos de respaldo → PC</h2>
  <a class="btn btn-amber" href="/backup.db" download="backup_moviles.db">Descargar backup_moviles.db</a>
</div>

${ordenPreparacion ? '''<div class="card">
  <h2>📋 Descargar órdenes de preparación → PC</h2>
  <a class="btn" style="background:#6a1b9a" href="/orden_preparacion.db" download="moviles_orden_preparacion.db">Descargar moviles_orden_preparacion.db</a>
</div>''' : ''}

<div class="card">
  <h2>📤 Enviar base de datos PC → celular</h2>
  <input type="file" id="f" accept=".db">
  <button class="btn btn-green" onclick="confirmUpload()">Enviar al celular</button>
  <div id="msg"></div>
</div>

<!-- Confirmation modal -->
<div id="overlay">
  <div id="modal">
    <h3>⚠ Confirmar reemplazo de base de datos</h3>
    <p>Esta acción reemplazará <strong>todos los datos del celular</strong> con los del archivo seleccionado.<br><br>
    Los pedidos que no hayas exportado <strong>se perderán definitivamente</strong>.<br><br>
    ¿Querés continuar?</p>
    <div class="modal-btns">
      <button id="btn-cancel" onclick="closeModal()">Cancelar</button>
      <button id="btn-confirm" onclick="doUpload()">Sí, reemplazar</button>
    </div>
  </div>
</div>

<script>
function confirmUpload(){
  const file=document.getElementById('f').files[0];
  if(!file){show('Seleccioná un archivo .db primero','err');return;}
  document.getElementById('overlay').classList.add('show');
}
function closeModal(){
  document.getElementById('overlay').classList.remove('show');
}
function doUpload(){
  closeModal();
  const file=document.getElementById('f').files[0];
  if(!file)return;
  show('Enviando...','loading');
  const xhr=new XMLHttpRequest();
  xhr.open('POST','/upload');
  xhr.setRequestHeader('Content-Type','application/octet-stream');
  xhr.onload=()=>{
    if(xhr.status===200)show('✓ Base de datos actualizada correctamente','ok');
    else show('Error: '+xhr.responseText,'err');
  };
  xhr.onerror=()=>show('Error de conexión','err');
  xhr.send(file);
}
function show(msg,cls){
  const el=document.getElementById('msg');
  el.textContent=msg;el.className=cls;el.style.display='block';
}
document.getElementById('overlay').addEventListener('click',function(e){
  if(e.target===this)closeModal();
});
</script>
${appVersion.isNotEmpty ? '<p style="text-align:center;font-size:.75rem;color:#aaa;margin-top:8px">Toma Pedidos $appVersion</p>' : ''}
</body>
</html>''';
