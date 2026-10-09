import 'package:firebase_auth/firebase_auth.dart';

/// Traduce los códigos de FirebaseAuth a mensajes claros en español.
String friendlyAuthError(FirebaseAuthException e) {
  switch (e.code) {
    case 'invalid-email':
      return 'El correo no tiene un formato válido';
    case 'user-not-found':
    case 'wrong-password':
    case 'invalid-credential':
      return 'Correo o contraseña incorrectos';
    case 'user-disabled':
      return 'Esta cuenta fue deshabilitada';
    case 'too-many-requests':
      return 'Demasiados intentos. Espera unos minutos e inténtalo de nuevo';
    case 'network-request-failed':
      return 'Sin conexión a internet. Revisa tu red e inténtalo de nuevo';
    case 'email-already-in-use':
      return 'Ya existe una cuenta con ese correo';
    case 'weak-password':
      return 'La contraseña es muy débil (mínimo 6 caracteres)';
    case 'operation-not-allowed':
      return 'El registro con correo no está habilitado en Firebase';
    default:
      return 'No se pudo completar la acción (${e.code})';
  }
}

final _emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

bool isValidEmail(String email) => _emailRegex.hasMatch(email.trim());