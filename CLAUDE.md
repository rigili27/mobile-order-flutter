# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
# Run on connected Android device
flutter run

# Build release APK
flutter build apk --release

# Analyze (no tests exist in this project)
flutter analyze

# Get dependencies after pubspec changes
flutter pub get
```

## Variables de CONFIGURACION (campo ParaMovil.CONFIGURACION)

Formato: `clave=valor;clave2=valor2` (separador `;`).
Leído y parseado por `Parametros._config` → `Map<String, String>`.
Acceso desde cualquier pantalla vía `ParametrosRepository.simboloMoneda()` (cacheado; se invalida al guardar desde ConfiguracionAvanzadaScreen).

| Variable | Valores | Efecto |
|---|---|---|
| `moneda` | `dolar` / *(ausente)* | `dolar` → muestra `U$S` en todos los totales (pantallas + PDF); ausente/otro → muestra `$` |
| `orden_preparacion` | `true` / *(ausente o `false`)* | `true` → muestra card "Orden de Preparación" en Home, habilita endpoint HTTP `/orden_preparacion.db` y su botón HTML, incluye la DB en compartir y en la lista de archivos; ausente/`false` → oculta todo |
| `tipo_servicio` | `true` / *(ausente o `false`)* | `true` → muestra el selector "Tipo de servicio" en crear pedido y crear orden de preparación; ausente/`false` → oculta el selector |
| `pdf_leyenda_precio_sin_iva` | `true` / *(ausente o `false`)* | `true` → imprime "* Precios sin IVA" al pie del total en el PDF; ausente/`false` → omite la leyenda |
| `nropedido` | `true` / *(ausente o `false`)* | `true` → muestra campo "Nro. Pedido" (numérico, opcional) encima del selector de cliente en crear pedido; ausente/`false` → oculta el campo |

> Al agregar nuevas variables: documentarlas aquí y usar `ParametrosRepository.getCached()` (o `simboloMoneda()`) para acceder al valor sin consultas extra a la DB.

## Architecture

**Flutter + Provider (ChangeNotifier) + sqflite. Offline-first: the entire SQLite DB is replaced wholesale on sync.**

### Startup flow (`app.dart → _AppRoot`)
1. `DatabaseHelper.instance.init()` → returns `DbInitState` (ok / noFile / error)
2. If `noFile` or `error` → show `SettingsScreen(noDatabase: true)` so user can receive a DB via WiFi
3. If `ok` → `AuthProvider.restoreSession()` → show `LoginScreen` or `HomeScreen`
4. `_AppRoot` subscribes to `AuthProvider` via explicit `addListener` (NOT `context.watch`) to avoid rebuild issues when auth state is inside a switch case

### Navigation pattern
`LoginScreen` uses `Navigator.pushReplacement(HomeScreen)` after login. `HomeScreen` uses `Navigator.pushReplacement(LoginScreen)` after logout. `_AppRoot` handles only the cold-start routing.

### Database — critical constraints
- **Never modify the SQLite schema.** The DB is owned by an external system (`moviles.db`). Only read/write rows, never ALTER TABLE or CREATE TABLE.
- **Table names:** `VendMovil`, `CliMovil`, `ArtMovil`, `DepoMovil`, `PedCMovil`, `PedDMovil`, `ParaMovil`
- Active DB lives at `getApplicationDocumentsDirectory()/moviles.db`. Never serve this file directly over the network — always copy to `export.db` first.
- Import sequence: receive → `temp.db` → validate (`SELECT 1 FROM VendMovil`) → backup active → rename temp → reopen. Implemented in `DatabaseFileManager.importFromTemp()`.

### Sync options (both exist, both functional)
- **FTP client** (`FtpClientService`): device connects to a PC-side FTP server. Uses **ACTIVE mode** (device opens listening socket, sends PORT command) to bypass Windows Firewall blocking PASV ports. Default port 2221.
- **HTTP server** (`HttpTransferServer`): device runs HTTP on port 8080. PC uses a browser. `GET /moviles.db` downloads, `POST /upload` uploads. No auth. The HTML page has a JS confirmation modal before upload.

### State management
Three providers in `MultiProvider` (see `app.dart`):
- `AuthProvider` — session, login/logout, admin override (`codigo=-1`, password `"password"`)
- `PedidoProvider` — order being built in memory; `guardar()` writes both header and lines to DB
- `FtpProvider` — FTP connection state and operations

### Price logic
`Articulo` has three price lists (`prevtaPub1/2/3`). `Cliente.nrolPrecios` selects which to default to. `Articulo.precioParaLista(int)` encapsulates the mapping. Line importe = `cantidad × precio × (1 − porDto/100)`.

### Signature storage
Captured as `Uint8List` (JPEG bytes) via the `signature` package. Stored as BLOB in `PedCMovil.FIRMA`. Compatible with the original B4A app.

### PDF generation
`PdfService.generarRemito()` builds an A4 receipt with company header, customer box, line-items table, total, comments, recipient, and signature image. Uses `intl` with `es_AR` locale for currency formatting.

### Admin user
`codigo = -1`, `nombre = "Administrador"`, fixed password `"password"`. Never stored in the DB. `AuthProvider.isAdmin` gates admin-only UI (e.g., DB files section in SettingsScreen).

## Key file locations

| Concern | File |
|---|---|
| DB open/close/validate | `lib/core/database/database_helper.dart` |
| DB import/export/backup | `lib/core/database/database_file_manager.dart` |
| FTP client (active mode) | `lib/core/ftp/ftp_client_service.dart` |
| HTTP sync server | `lib/core/http/http_transfer_server.dart` |
| Order save logic | `lib/presentation/providers/pedido_provider.dart` |
| PDF receipt | `lib/core/services/pdf_service.dart` |
| App root / boot | `lib/app.dart` |
