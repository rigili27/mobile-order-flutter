import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'core/app_mode.dart';
import 'core/database/database_helper.dart';
import 'app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  await AppMode.refresh(); // decide moviles.db vs moviles_api.db antes de abrir
  await DatabaseHelper.instance.init();
  runApp(const TomaPedidosApp());
}
