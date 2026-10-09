// Requiere: flutter pub add firebase_ai
// Y activar "AI Logic" (proveedor Gemini Developer API) en la consola de Firebase.
// No hay API key en el código: Firebase AI Logic hace de proxy.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_ai/firebase_ai.dart';

class RecommendationService {
  /// Modelo estable de la familia Gemini 3.x Flash (no requiere facturación
  /// con Gemini Developer API). Si algún día devuelve error 404, cambia solo
  /// este valor por uno vigente: https://firebase.google.com/docs/ai-logic/models
  static const String modelName = 'gemini-3.5-flash';

  late final GenerativeModel _model = FirebaseAI.googleAI().generativeModel(
    model: modelName,
    generationConfig: GenerationConfig(temperature: 0.4),
    systemInstruction: Content.system(
      'Eres un asistente de apoyo para entrenadores de ciclismo. '
      'Recibes las métricas de una salida de un deportista y redactas una '
      'sugerencia para que EL ENTRENADOR la revise; él tomará la decisión final. '
      'Responde en español, en texto plano (sin markdown, sin asteriscos), '
      'máximo 6 líneas, con este orden: '
      '1) Resumen de la salida en una línea. '
      '2) Sugerencia para el próximo entrenamiento. '
      '3) Alerta, solo si algún dato es anómalo. '
      'No des diagnósticos médicos. Si los datos son pocos, muy cortos o '
      'simulados, dilo y no saques conclusiones fuertes.',
    ),
  );

  /// Genera la sugerencia y la guarda como 'pending' para que el entrenador
  /// la apruebe, edite o rechace.
  /// Devuelve false si el deportista no tiene entrenador vinculado (no se
  /// gasta cuota de la IA) o si la IA no devolvió texto.
  Future<bool> generateFor(String athleteId, Map<String, dynamic> m) async {
    final db = FirebaseFirestore.instance;

    final athleteDoc = await db.collection('users').doc(athleteId).get();
    final coachId = athleteDoc.data()?['coachId'] as String?;
    if (coachId == null) return false;

    // Solo métricas: NO se envía nombre, correo ni ubicación (privacidad).
    final source = m['sensorSource'] == 'demo'
        ? 'SIMULADOS (modo demo)'
        : 'medidos con sensor';
    final prompt = 'Métricas de la última salida: '
        'distancia ${m['distanceKm']} km, duración ${m['durationMin']} min, '
        'velocidad media ${m['avgSpeedKmh']} km/h, '
        'velocidad máxima ${m['maxSpeedKmh']} km/h, '
        'desnivel acumulado ${m['elevationGainM']} m, '
        'cadencia media ${m['avgCadenceRpm']} rpm, '
        'frecuencia cardíaca media ${m['avgHr']} bpm, '
        'FC máxima ${m['maxHr']} bpm. '
        'La frecuencia cardíaca y la cadencia fueron $source.';

    final res = await _model
        .generateContent([Content.text(prompt)])
        .timeout(const Duration(seconds: 30));
    final text = res.text?.trim();
    if (text == null || text.isEmpty) return false;

    await db.collection('recommendations').add({
      'athleteId': athleteId,
      'coachId': coachId,
      'sessionId': m['id'],
      'text': text,
      'status': 'pending',
      'source': 'ai',
      'model': modelName,
      'metricsSnapshot': {
        for (final e in m.entries)
          if (e.key != 'id') e.key: e.value,
      },
      'createdAt': FieldValue.serverTimestamp(),
    });
    return true;
  }
}