// Requiere: flutter pub add firebase_ai
// Y activar "Firebase AI Logic" (proveedor Gemini Developer API) en la consola.
// Sin API key en el código: Firebase AI Logic hace de proxy.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_ai/firebase_ai.dart';

class RecommendationService {
  final _model = FirebaseAI.googleAI().generativeModel(
    model: 'gemini-2.5-flash', // verifica en la consola el modelo vigente
    systemInstruction: Content.system(
      'Eres un asistente de apoyo para entrenadores de ciclismo. '
      'Analiza las métricas y devuelve una recomendación breve (máx. 5 líneas) '
      'en español. No des diagnósticos médicos. Si los datos son insuficientes '
      'o anómalos, dilo. El entrenador tomará la decisión final.',
    ),
  );

  /// Genera la sugerencia y la guarda como 'pending' para que el entrenador
  /// la apruebe, edite o rechace.
  Future<void> generateFor(String athleteId, Map<String, dynamic> m) async {
    final prompt = 'Métricas de la última salida: '
        'distancia ${m['distanceKm']} km, velocidad media ${m['avgSpeedKmh']} km/h, '
        'cadencia media ${m['avgCadenceRpm']} rpm, FC media ${m['avgHr']} bpm, '
        'FC máx ${m['maxHr']} bpm, desnivel ${m['elevationGainM']} m, '
        'duración ${m['durationMin']} min.';
    final res = await _model.generateContent([Content.text(prompt)]);
    final text = res.text?.trim();
    if (text == null || text.isEmpty) return;

    await FirebaseFirestore.instance.collection('recommendations').add({
      'athleteId': athleteId,
      'text': text,
      'status': 'pending',
      'source': 'ai',
      'metricsSnapshot': m,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }
}