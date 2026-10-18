// Requiere: flutter pub add firebase_ai
// Y activar "AI Logic" (proveedor Gemini Developer API) en la consola de Firebase.
// No hay API key en el código: Firebase AI Logic hace de proxy.
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_ai/firebase_ai.dart';

class RecommendationService {
  /// Modelos en orden de preferencia. Si uno está saturado (error 500/503/429)
  /// o no existe, se prueba el siguiente. Todos son estables y, con Gemini
  /// Developer API, no requieren facturación. Si alguno devuelve 404, revisa
  /// los nombres vigentes: https://firebase.google.com/docs/ai-logic/models
  static const List<String> modelNames = [
    'gemini-3.5-flash',
    'gemini-3.5-flash-lite',
    'gemini-3.1-flash-lite',
  ];

  static const int _attemptsPerModel = 2;
  static const Duration _timeout = Duration(seconds: 20);

  static const String _systemPrompt =
      'Eres un asistente de apoyo para entrenadores de ciclismo. '
      'Recibes las métricas de una salida de un deportista y redactas una '
      'sugerencia para que EL ENTRENADOR la revise; él tomará la decisión final. '
      'Responde en español, en texto plano (sin markdown, sin asteriscos), '
      'máximo 6 líneas, con este orden: '
      '1) Resumen de la salida en una línea. '
      '2) Sugerencia para el próximo entrenamiento. '
      '3) Alerta, solo si algún dato es anómalo. '
      'No des diagnósticos médicos. Si los datos son pocos, muy cortos o '
      'simulados, dilo y no saques conclusiones fuertes.';

  GenerativeModel _modelFor(String name) =>
      FirebaseAI.googleAI().generativeModel(
        model: name,
        generationConfig: GenerationConfig(temperature: 0.4),
        systemInstruction: Content.system(_systemPrompt),
      );

  /// Errores temporales del servidor: vale la pena reintentar.
  bool _isTransient(Object e) {
    if (e is TimeoutException) return true;
    final s = e.toString().toLowerCase();
    return s.contains('500') ||
        s.contains('503') ||
        s.contains('429') ||
        s.contains('high demand') ||
        s.contains('unavailable') ||
        s.contains('overloaded') ||
        s.contains('resource_exhausted');
  }

  /// El modelo no existe o ya no está disponible: pasar directo al siguiente.
  bool _isModelMissing(Object e) {
    final s = e.toString().toLowerCase();
    return s.contains('404') ||
        (s.contains('not found') && s.contains('model'));
  }

  Future<({String text, String model})> _generate(String prompt) async {
    Object? lastError;
    for (final name in modelNames) {
      final model = _modelFor(name);
      for (var attempt = 1; attempt <= _attemptsPerModel; attempt++) {
        try {
          final res = await model
              .generateContent([Content.text(prompt)])
              .timeout(_timeout);
          final text = res.text?.trim();
          if (text != null && text.isNotEmpty) {
            return (text: text, model: name);
          }
          lastError = 'Respuesta vacía de $name';
          break; // siguiente modelo
        } catch (e) {
          lastError = e;
          if (_isModelMissing(e)) break; // siguiente modelo
          // Errores NO temporales (permisos, API sin activar...) se repetirían
          // igual en todos los modelos: se informan de inmediato.
          if (!_isTransient(e)) rethrow;
          if (attempt < _attemptsPerModel) {
            await Future.delayed(const Duration(seconds: 2));
          }
        }
      }
    }
    throw Exception(
        'La IA no respondió tras probar ${modelNames.length} modelos. '
        'Último error: $lastError');
  }

  /// Genera la sugerencia y la guarda como 'pending' para que el entrenador
  /// la apruebe, edite o rechace.
  /// Devuelve false si el deportista no tiene entrenador vinculado (no se
  /// gasta cuota de la IA). Lanza una excepción si la IA no pudo responder.
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

    final result = await _generate(prompt);

    await db.collection('recommendations').add({
      'athleteId': athleteId,
      'coachId': coachId,
      'sessionId': m['id'],
      'text': result.text,
      'status': 'pending',
      'source': 'ai',
      'model': result.model, // modelo que respondió realmente
      'metricsSnapshot': {
        for (final e in m.entries)
          if (e.key != 'id') e.key: e.value,
      },
      'createdAt': FieldValue.serverTimestamp(),
    });
    return true;
  }
}