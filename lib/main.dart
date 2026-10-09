import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'firebase_options.dart';
import 'screens/auth_gate.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  runApp(const BiciLabApp());
}

class BiciLabApp extends StatelessWidget {
  const BiciLabApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BiciLab',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        // Mensajes flotantes y spinners en negro: coherentes con la app.
        snackBarTheme: const SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
        ),
        progressIndicatorTheme:
            const ProgressIndicatorThemeData(color: Colors.black),
      ),
      home: const AuthGate(),
    );
  }
}