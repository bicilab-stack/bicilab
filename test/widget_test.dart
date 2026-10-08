import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bicilab/screens/welcome_screen.dart';

void main() {
  // El test original (contador) pertenece a la plantilla de Flutter y no
  // aplica: además BiciLabApp inicializa Firebase en main(), no en el widget.
  testWidgets('WelcomeScreen muestra los botones principales', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: WelcomeScreen()));
    expect(find.text('Bienvenido a BiciLab'), findsOneWidget);
    expect(find.text('INICIAR SESION'), findsOneWidget);
    expect(find.text('¡REGISTRESE!'), findsOneWidget);
  });
}
