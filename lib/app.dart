import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'core/api/api_config.dart';
import 'core/database/database_helper.dart';
import 'core/theme/brand_colors.dart';
import 'core/database/orden_preparacion_database_helper.dart';
import 'presentation/providers/api_sync_provider.dart';
import 'presentation/providers/auth_provider.dart';
import 'presentation/providers/ftp_provider.dart';
import 'presentation/providers/orden_preparacion_provider.dart';
import 'presentation/providers/pedido_provider.dart';
import 'presentation/providers/reparto_provider.dart';
import 'presentation/providers/update_provider.dart';
import 'presentation/screens/home/home_screen.dart';
import 'presentation/screens/login/login_screen.dart';
import 'presentation/screens/reparto/reparto_home_screen.dart';
import 'presentation/screens/settings/settings_screen.dart';

/// Navigator raíz de la app. Se usa para forzar la navegación a Login desde
/// callbacks (p. ej. tras recibir una DB por HTTP/FTP) sin depender de un
/// BuildContext local que puede quedar desmontado por un rebuild reactivo
/// de `_AppRoot` (ver `AuthProvider.logout()` + `_onAuthChanged`).
final rootNavigatorKey = GlobalKey<NavigatorState>();

class TomaPedidosApp extends StatelessWidget {
  const TomaPedidosApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => PedidoProvider()),
        ChangeNotifierProvider(create: (_) => OrdenPreparacionProvider()),
        ChangeNotifierProvider(create: (_) => FtpProvider()),
        ChangeNotifierProvider(create: (_) => ApiSyncProvider()),
        ChangeNotifierProvider(create: (_) => RepartoProvider()),
        ChangeNotifierProvider(create: (_) => UpdateProvider()),
      ],
      child: MaterialApp(
        navigatorKey: rootNavigatorKey,
        title: 'Toma Pedidos',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: kLabgeVioleta,
            brightness: Brightness.light,
          ),
          useMaterial3: true,
          appBarTheme: const AppBarTheme(
            backgroundColor: kLabgeNegro,
            foregroundColor: Colors.white,
            elevation: 2,
          ),
          elevatedButtonTheme: ElevatedButtonThemeData(
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(double.infinity, 52),
              textStyle:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
        ),
        home: const _AppRoot(),
      ),
    );
  }
}

class _AppRoot extends StatefulWidget {
  const _AppRoot();

  @override
  State<_AppRoot> createState() => _AppRootState();
}

class _AppRootState extends State<_AppRoot> {
  bool _checking = true;
  DbInitState _dbState = DbInitState.ok;
  String? _dbError;
  bool _esRepartidor = false;

  // Listener directo al ChangeNotifier: más confiable que context.watch dentro
  // de un switch case, donde la suscripción puede no re-registrarse correctamente.
  bool _authListenerRegistered = false;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_authListenerRegistered) {
      _authListenerRegistered = true;
      context.read<AuthProvider>().addListener(_onAuthChanged);
    }
  }

  @override
  void dispose() {
    context.read<AuthProvider>().removeListener(_onAuthChanged);
    super.dispose();
  }

  void _onAuthChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _boot() async {
    final result = await DatabaseHelper.instance.init();
    _dbState = result.state;
    _dbError = result.error;

    // The orden DB auto-creates its tables; init always succeeds.
    await OrdenPreparacionDatabaseHelper.instance.init();

    // El repartidor no tiene base de catálogo (moviles_api.db): su sesión no
    // depende de DbInitState. Se restaura siempre y se rutea a su propio Home.
    _esRepartidor = await ApiConfig.isRepartidor();

    if (result.state == DbInitState.ok || _esRepartidor) {
      if (mounted) await context.read<AuthProvider>().restoreSession();
    }
    if (mounted) setState(() => _checking = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final auth = context.read<AuthProvider>();

    // Modo repartidor: su Home no necesita moviles_api.db.
    if (auth.esRepartidor) {
      return auth.isAuthenticated ? const RepartoHomeScreen() : const LoginScreen();
    }

    switch (_dbState) {
      case DbInitState.noFile:
        return SettingsScreen(
          noDatabase: true,
          onDatabaseReady: _onDatabaseReady,
        );
      case DbInitState.error:
        return SettingsScreen(
          noDatabase: true,
          dbError: _dbError,
          onDatabaseReady: _onDatabaseReady,
        );
      case DbInitState.ok:
        // context.read en vez de watch — el rebuild lo maneja _onAuthChanged.
        final auth = context.read<AuthProvider>();
        return auth.isAuthenticated ? const HomeScreen() : const LoginScreen();
    }
  }

  Future<void> _onDatabaseReady() async {
    final result = await DatabaseHelper.instance.init();
    if (mounted) setState(() { _dbState = result.state; _dbError = result.error; });
  }
}
