import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Códigos de invitación para vincular deportistas con su entrenador.
///   coachCodes/{CODIGO} -> { coachId: uid del entrenador }
class CoachCodeService {
  static final _db = FirebaseFirestore.instance;

  /// Devuelve el código del entrenador actual; lo crea si aún no tiene.
  static Future<String> ensureCoachCode() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('No hay sesión activa');

    final userRef = _db.collection('users').doc(user.uid);
    final existing = (await userRef.get()).data()?['coachCode'] as String?;
    if (existing != null && existing.isNotEmpty) return existing;

    // Sin 0/O/1/I para evitar confusiones al dictar el código.
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rnd = Random.secure();

    for (var i = 0; i < 5; i++) {
      final code =
          List.generate(6, (_) => chars[rnd.nextInt(chars.length)]).join();
      final codeRef = _db.collection('coachCodes').doc(code);
      if ((await codeRef.get()).exists) continue;
      await codeRef.set({'coachId': user.uid});
      await userRef.update({'coachCode': code});
      return code;
    }
    throw Exception('No se pudo generar un código, intenta de nuevo');
  }

  /// Devuelve el uid del entrenador dueño del código, o null si no existe.
  static Future<String?> resolveCoachId(String code) async {
    final clean = code.trim().toUpperCase();
    if (clean.isEmpty) return null;
    final doc = await _db.collection('coachCodes').doc(clean).get();
    return doc.data()?['coachId'] as String?;
  }
}