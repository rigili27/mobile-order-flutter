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
| `cta_cte` | `true` / *(ausente o `false`)* | `true` → habilita cobranza por cuenta corriente **solo en Pedidos** (no en Orden de Preparación): selector "Tipo de venta" (C/E/T, default C) en crear pedido, que al guardar sincroniza un movimiento en `PedMCCte` (importe negativo si C, positivo si E/T); también habilita el botón "Nuevo movimiento de cuenta corriente" en el detalle de Cliente para altas manuales; ausente/`false` → oculta todo |
| `api` | `true` / *(ausente o `false`)* | Lo manda el ERP en modo API (`MovilCatalogService`). Confirmación informativa (`Parametros.apiActivo`); el switch real de modo lo decide `ApiConfig.isConfigured()` (prefs `api_base_url`+`api_tenant`). No lo edites a mano. |

> **Modo API:** todos estos flags los administra el ERP en **Preventa → Config. de la app** y llegan en el string `configuracion` del catálogo. La pantalla "Configuración avanzada" de la app queda en **solo lectura**.

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
- **Table names:** `VendMovil`, `CliMovil`, `ArtMovil`, `DepoMovil`, `PedCMovil`, `PedDMovil`, `ParaMovil`, `PedMCCte`
- **`PedMCCte`** (movimientos de cuenta corriente): `ID`, `IDPEDMOVIL` (nullable — null = movimiento manual sin pedido asociado), `CODCLIENTE`, `TIPOVENTA` (`C`/`E`/`T`), `IMPORTE` (negativo = debe, positivo = haber). `PedCMovil.TIPOVENTA` guarda el tipo de venta elegido en el pedido. Ver flag `cta_cte` arriba.
- Active DB lives at `getApplicationDocumentsDirectory()/moviles.db`. Never serve this file directly over the network — always copy to `export.db` first.
- Import sequence: receive → `temp.db` → validate (`SELECT 1 FROM VendMovil`) → backup active → rename temp → reopen. Implemented in `DatabaseFileManager.importFromTemp()`.

### Sync options (all functional)
- **FTP client** (`FtpClientService`): device connects to a PC-side FTP server. Uses **ACTIVE mode** (device opens listening socket, sends PORT command) to bypass Windows Firewall blocking PASV ports. Default port 2221.
- **HTTP server** (`HttpTransferServer`): device runs HTTP on port 8080. PC uses a browser. `GET /moviles.db` downloads, `POST /upload` uploads. No auth. The HTML page has a JS confirmation modal before upload.
- **API (GestionERP)** (`lib/core/api/`): si `ApiConfig.isConfigured()` (prefs `api_base_url` + `api_tenant`) la app opera en "modo API" (`AppMode.isApi`, cacheado, refrescado en `main.dart` y al cambiar la config). `PreventaApi` habla con `<baseUrl>/api/<tenant>` (token Sanctum en `api_token`). **Base paralela**: en modo API la base activa es `moviles_api.db` (y `backup_moviles_api.db` / `temp_moviles_api.db`), separada de la `moviles.db` de WiFi — `DatabaseHelper.dbPath` y `DatabaseFileManager` son mode-aware; cambiar de modo cierra la base (`ApiConfig._aplicarCambioDeModo`) y la próxima apertura apunta al archivo del otro modo, sin destruir datos. `CatalogImporter` vuelca `GET /catalogo` en las tablas `*Movil` de `moviles_api.db` (DELETE+INSERT por tabla, sin tocar `PedCMovil`/`PedDMovil`/`PedMCCte`; si no existe copia el de assets para el esquema). Los pedidos guardados se encolan en `movil_sync.db` (`SyncStateDatabaseHelper`, tabla `pedido_outbox`, `uuid` de idempotencia) y se suben con `POST /pedidos` → Presupuesto en Borrador en el ERP. `ApiSyncProvider` orquesta todo (incluye `advertencias` de la última sync); UI en `settings/api_server_card.dart`. Login por **usuario o email** + password (`AuthProvider.loginConApi`) en vez del dropdown de vendedor. En Configuración, modo API oculta la sección "Transferencia WiFi" y "Compartir base de datos".
- **Listas de precio (modo API)**: los 3 slots `PREVTAPUB1/2/3` los elige el backend (`MovilCatalogService`) con las listas que más usan los clientes del vendedor; si un cliente usa una 4ª lista, `advertencias` lo reporta. La app no cambia (`Articulo.precioParaLista`).
- **Cobranzas (modo API)**: `movil_sync.db` v2 agrega `cobranza_local` (la cobranza registrada en la calle + firma BLOB, detalle de cheque/transferencia en `detalle_json`) y `cobranza_outbox` (`uuid` de idempotencia, `receipt_id`, estado). `CobranzaRepository` hace el CRUD; `ApiSyncProvider.subirCobranza(idLocal)` encola + `POST /cobranzas` → `Receipt` en Borrador en Tesorería (administración lo confirma en Preventa → Cobranzas). Pantallas en `lib/presentation/screens/cobranzas/` (`CobranzasScreen` listado con chip de sync + "Reintentar"; `NuevaCobranzaScreen` con selector de forma de pago y campos condicionales cheque/transferencia + firma). El menú "Cobranzas" del Home y el botón del detalle de Cliente aparecen solo con `cta_cte=true` **y** modo API; en modo WiFi el detalle de Cliente sigue con el bottom sheet de `PedMCCte` local.
- **Cta cte en la app (modo API)**: `CuentaCorrienteRepository.getVistaByCliente/getVistaAll` combina los `PedMCCte` con las `cobranza_local` (incluso sin confirmar) en `MovimientoCtaCteVista` (`lib/data/models/`), con `estadoSync` leído del `cobranza_outbox` (`sincronizado` ⇒ "sin confirmar" porque el ERP la tiene en Borrador). El detalle de cliente muestra "Saldo confirmado" + "Cobranzas sin confirmar" + "Saldo proyectado".
- **QR de acceso (modo API)**: `LoginScreen` → "Escanear QR de acceso" → `QrPairingScreen` (`mobile_scanner`, parsea el JSON `{v,url,tenant,code,...}`) → `AuthProvider.adoptarSesionQr` (`PreventaApi.pairWithCode` → `POST /pair` → persiste `api_base_url`+`api_tenant`+`api_token` + `_persistSession`) → sync catálogo → Home. Sin login manual. Si la sync falla, la pantalla lo muestra con "Reintentar" / "Entrar igual".
- **Auto-sync (modo API)**: `ApiSyncProvider.autoSync({force})` sincroniza el catálogo si hay sesión y `ApiConfig.lastSync()` es más viejo que `autoSyncInterval` (15 min) o null. `HomeScreen` (con `WidgetsBindingObserver`) lo llama en `initState` y en `AppLifecycleState.resumed`; al terminar recarga los flags de config. `LoginScreen` y `QrPairingScreen` chequean el resultado de `sincronizarCatalogo()` y avisan si falló.
- **Altas de cliente / artículo (modo API, online obligatorio)**: `ApiSyncProvider.crearCliente(...)` / `crearArticulo(...)` → `POST /clientes` / `/articulos` → inserta en `CliMovil` / `ArtMovil` con el código real devuelto + registra en `cliente_outbox` / `articulo_outbox` (`movil_sync.db` v3). `NuevoClienteScreen` (FAB en `ClientesScreen`); `showNuevoArticuloDialog` (`lib/presentation/screens/articulos/nuevo_articulo_dialog.dart`) desde `ArticulosScreen` (FAB) y desde `_AddProductoSheet` del alta de pedido (botón "Artículo nuevo"). `Articulo.pendiente` (columna `ArtMovil.PENDIENTE`, la agrega `CatalogImporter._ensureApiSchema`) muestra un badge; las líneas de pedido pueden referenciar un artículo pendiente.
- **Funciones habilitadas por vendedor**: `Parametros` suma 7 getters (`permitePedidos`, `permiteCobranzas`, `permiteAltaClientes`, `permiteAltaArticulos`, `permiteVerPrecios`, `permiteStock`, `permiteGenerarCompra`) leídos del `configuracion` — el ERP los manda siempre explícitos (`clave=true`/`clave=false`), a diferencia de los flags viejos que solo aparecen cuando están prendidos; ausencia de clave (base vieja sin resincronizar) cae al mismo default que el backend. Gatean: FAB "Nuevo Pedido" y card "Cobranzas" del Home, FAB "Nuevo cliente" (`ClientesScreen`), FAB "Nuevo artículo" (`ArticulosScreen` + sheet del pedido), y las cards nuevas "Stock"/"Órdenes de compra". `permiteVerPrecios` solo oculta montos en la UI (ej. `_ArticuloTile`), el pedido se sigue armando igual.
- **Stock ("controlar stock") y órdenes de compra (modo API, online obligatorio, gateadas por flag)**: `movil_sync.db` v4 agrega `ajuste_stock_local`/`_outbox` y `orden_compra_local`/`_outbox` (mismo esqueleto que cliente/artículo — se guardan localmente solo si el POST al ERP tuvo éxito). `ApiSyncProvider.crearAjusteStock(...)` (`POST stock/ajustes` → `{id, diferenciaSugerida}`) y `crearOrdenCompra(...)` (`POST ordenes-compra`). Pantallas en `lib/presentation/screens/stock/` (`AjustesStockScreen` + `NuevoAjusteStockScreen`: artículo por buscador/escaneo + depósito de `DepositoRepository.getAll()` + cantidad contada) y `lib/presentation/screens/compras/` (`OrdenesCompraScreen` + `NuevaOrdenCompraScreen`: proveedor de `ProveedorRepository`/`ProvMovil` o texto libre + N renglones artículo/cantidad/costo estimado). Ambas quedan **pendientes de confirmar/aprobar** en el ERP (Preventa → Ajustes de stock / Órdenes de compra de la app) — la app nunca ve el resultado final, solo que se envió.

Prefs del modo API: `api_base_url`, `api_tenant`, `api_token`, `api_last_sync`.

### State management
Providers in `MultiProvider` (see `app.dart`):
- `AuthProvider` — session, login/logout, admin override (`codigo=-1`, password `"password"`), `loginConApi()` para modo API
- `PedidoProvider` — order being built in memory; `guardar()` writes both header and lines to DB
- `FtpProvider` — FTP connection state and operations
- `ApiSyncProvider` — sincronización de catálogo, subida de pedidos y cobranzas, altas de cliente/artículo en modo API (`subirPedido`, `subirCobranza`, `reintentar*`, `crearCliente`, `crearArticulo`, getters `pendientes` / `cobranzasPendientes`)

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
