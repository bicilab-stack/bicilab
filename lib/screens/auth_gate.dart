import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'coach_screen.dart';
import 'home_screen.dart';
import 'welcome_screen.dart';

/// Decide la primera pantalla al abrir la app:
///  - sin sesión            -> WelcomeScreen
///  - sesión + rol coach    -> CoachScreen
///  - sesión + deportista   -> HomeScreen
/// Se resuelve UNA sola vez al arrancar. Después, login/registro/logout
/// manejan su propia navegación.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  late final Future<Widget> _initial = _resolve();

  Future<Widget> _resolve() async {
    final user = await FirebaseAuth.instance.authStateChanges().first;
    if (user == null) return const WelcomeScreen();

    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final role = doc.data()?['role'] as String?;
      if (role == 'entrenador') return const CoachScreen();
      if (role == 'deportista') return const HomeScreen();
    } catch (_) {
      // Sin internet o error de permisos: caemos a Welcome sin cerrar sesión.
    }
    return const WelcomeScreen();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Widget>(
      future: _initial,
      builder: (context, snap) {
        if (snap.hasData) return snap.data!;
        return const Scaffold(
          backgroundColor: Colors.white,
          body: Center(child: CircularProgressIndicator()),
        );
      },
    );
  }
}