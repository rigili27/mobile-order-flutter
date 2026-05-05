import 'package:shared_preferences/shared_preferences.dart';
import '../../data/models/vendedor.dart';
import '../../data/repositories/vendedor_repository.dart';

class AuthService {
  AuthService._();
  static final AuthService instance = AuthService._();

  static const _keyCodigoVendedor = 'vendedor_codigo';

  final _repo = VendedorRepository();

  Future<Vendedor?> login(int codigo, String clave) async {
    final vendedor = await _repo.findByCodigo(codigo);
    if (vendedor == null) return null;
    if (vendedor.clave.trim() != clave.trim()) return null;
    await _persistSession(codigo);
    return vendedor;
  }

  Future<Vendedor?> restoreSession() async {
    final prefs = await SharedPreferences.getInstance();
    final codigo = prefs.getInt(_keyCodigoVendedor);
    if (codigo == null) return null;
    return _repo.findByCodigo(codigo);
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyCodigoVendedor);
  }

  Future<void> _persistSession(int codigo) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyCodigoVendedor, codigo);
  }
}
