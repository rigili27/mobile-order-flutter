import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../data/models/vendedor.dart';
import '../../data/repositories/vendedor_repository.dart';

enum AuthState { initial, loading, authenticated, unauthenticated }

class AuthProvider extends ChangeNotifier {
  final _repo = VendedorRepository();

  static const _keyCodigoVendedor = 'vendedor_codigo';
  static const _adminCodigo = -1;
  static const _adminPassword = 'password';
  static final _adminVendedor =
      Vendedor(codigo: _adminCodigo, nombre: 'Administrador', clave: '');

  Vendedor? _vendedor;
  AuthState _state = AuthState.initial;
  String? _errorMessage;

  Vendedor? get vendedor => _vendedor;
  AuthState get state => _state;
  String? get errorMessage => _errorMessage;
  bool get isAuthenticated => _state == AuthState.authenticated;
  bool get isAdmin => _vendedor?.codigo == _adminCodigo;

  static Vendedor get adminVendedor => _adminVendedor;
  static int get adminCodigo => _adminCodigo;

  Future<void> restoreSession() async {
    _state = AuthState.loading;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    final codigo = prefs.getInt(_keyCodigoVendedor);
    if (codigo == null) {
      _state = AuthState.unauthenticated;
      notifyListeners();
      return;
    }
    if (codigo == _adminCodigo) {
      _vendedor = _adminVendedor;
    } else {
      _vendedor = await _repo.findByCodigo(codigo);
    }
    _state = _vendedor != null ? AuthState.authenticated : AuthState.unauthenticated;
    notifyListeners();
  }

  /// Login con un Vendedor seleccionado del dropdown + contraseña ingresada.
  ///
  /// Reglas:
  /// - Vendedor admin (codigo=-1): requiere password == 'password'
  /// - Clave vacía en DB: acepta cualquier contraseña (incluso vacía)
  /// - Clave no vacía: debe coincidir exactamente
  Future<bool> loginVendor(Vendedor vendor, String inputPassword) async {
    _state = AuthState.loading;
    _errorMessage = null;
    notifyListeners();

    bool valid;
    if (vendor.codigo == _adminCodigo) {
      valid = inputPassword == _adminPassword;
    } else {
      final dbVendor = await _repo.findByCodigo(vendor.codigo);
      if (dbVendor == null) {
        _setError('Vendedor no encontrado en la base de datos.');
        return false;
      }
      final clave = dbVendor.clave.trim();
      valid = clave.isEmpty || inputPassword.trim() == clave;
      if (valid) _vendedor = dbVendor;
    }

    if (valid) {
      _vendedor ??= vendor;
      _state = AuthState.authenticated;
      await _persistSession(_vendedor!.codigo);
      notifyListeners();
      return true;
    } else {
      _setError('Clave incorrecta.');
      return false;
    }
  }

  Future<void> logout() async {
    // Actualizar estado primero → UI reacciona de inmediato.
    _vendedor = null;
    _state = AuthState.unauthenticated;
    notifyListeners();
    // Limpiar sesión persistida en background (no bloquea la navegación).
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyCodigoVendedor);
  }

  Future<void> _persistSession(int codigo) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyCodigoVendedor, codigo);
  }

  void _setError(String msg) {
    _state = AuthState.unauthenticated;
    _errorMessage = msg;
    notifyListeners();
  }
}
