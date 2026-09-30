// Copiado idéntico en las tres apps (test/update/): ver lib/core/update/.

import 'package:mobile_order_flutter/core/update/update_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'update_client_test.dart' show latestJson;
import 'update_controller_test.dart' show controllerFor;

void main() {
  Widget appWith(Widget Function(GlobalKey<NavigatorState> key, Widget child) gate) {
    final key = GlobalKey<NavigatorState>();
    return MaterialApp(
      navigatorKey: key,
      builder: (context, child) => gate(key, child!),
      home: const Scaffold(body: Text('Pantalla de la app')),
    );
  }

  testWidgets('muestra el aviso arriba de la app', (tester) async {
    final updates = controllerFor(latestJson());
    await tester.runAsync(updates.check);

    await tester.pumpWidget(appWith((key, child) => UpdateGate(controller: updates, navigatorKey: key, child: child)));

    expect(find.text('Nueva versión 2.1.0 disponible'), findsOneWidget);
    expect(find.text('Pantalla de la app'), findsOneWidget);

    await tester.tap(find.text('Más tarde'));
    await tester.pump();
    expect(find.text('Nueva versión 2.1.0 disponible'), findsNothing);
  });

  testWidgets('ocupada: el botón se deshabilita, o el aviso se oculta si así se pidió', (tester) async {
    final updates = controllerFor(latestJson(), isBusy: () => true);
    await tester.runAsync(updates.check);

    await tester.pumpWidget(appWith((key, child) => UpdateGate(controller: updates, navigatorKey: key, child: child)));
    expect(find.text('Hay una firma en curso.'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Actualizar')).onPressed, isNull);

    await tester.pumpWidget(appWith((key, child) => UpdateGate(controller: updates, navigatorKey: key, hideBannerWhileBusy: true, child: child)));
    expect(find.text('Nueva versión 2.1.0 disponible'), findsNothing);
  });

  testWidgets('por debajo de la versión mínima bloquea la app', (tester) async {
    final updates = controllerFor(latestJson(mandatory: true));
    await tester.runAsync(updates.check);

    await tester.pumpWidget(appWith((key, child) => UpdateGate(controller: updates, navigatorKey: key, child: child)));

    expect(find.text('Hay que actualizar la app'), findsOneWidget);
    expect(find.text('Pantalla de la app'), findsNothing);
    expect(find.text('Actualizar ahora'), findsOneWidget);
  });
}
