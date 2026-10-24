// Requiere: flutter pub add health
// Lee la frecuencia cardíaca que Mi Fitness (la app de la Xiaomi Smart Band)
// guarda en Health Connect. Los datos llegan DESPUÉS de sincronizar la banda,
// no en tiempo real. Detalles de configuración de Android: ANDROID_HEALTH_CONNECT.txt
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:health/health.dart';

/// Resumen del pulso de un recorrido.
class BandHeartRate {
  final int avg;
  final int max;
  final int samples;
  const BandHeartRate(
      {required this.avg, required this.max, required this.samples});
}

class HealthService {
  static final HealthService _instance = HealthService._();
  factory HealthService() => _instance;
  HealthService._();

  final Health _health = Health();
  bool _configured = false;

  static const List<HealthDataType> _types = [HealthDataType.HEART_RATE];
  static const List<HealthDataAccess> _access = [HealthDataAccess.READ];

  Future<void> _configure() async {
    if (_configured) return;
    await _health.configure();
    _configured = true;
  }

  /// Pide permiso de lectura del pulso (si ya lo tiene, no vuelve a preguntar).
  /// Devuelve false si Health Connect no está instalado o el usuario lo niega.
  Future<bool> requestAccess() async {
    try {
      await _configure();
      final has = await _health.hasPermissions(_types, permissions: _access);
      if (has == true) return true;
      return await _health.requestAuthorization(_types, permissions: _access);
    } catch (e) {
      debugPrint('Health Connect no disponible: $e');
      return false;
    }
  }

  /// Promedio y máximo del pulso entre [start] y [end] (con 1 min de margen).
  /// Devuelve null si no hay datos (la banda aún no sincronizó) o hay un error.
  Future<BandHeartRate?> heartRateBetween(DateTime start, DateTime end) async {
    try {
      await _configure();
      final points = await _health.getHealthDataFromTypes(
        types: _types,
        startTime: start.subtract(const Duration(minutes: 1)),
        endTime: end.add(const Duration(minutes: 1)),
      );
      final values = <double>[];
      for (final p in points) {
        final v = p.value;
        if (v is NumericHealthValue) {
          final n = v.numericValue.toDouble();
          // Descarta lecturas imposibles.
          if (n >= 30 && n <= 230) values.add(n);
        }
      }
      if (values.isEmpty) return null;
      final sum = values.reduce((a, b) => a + b);
      final maxV = values.reduce((a, b) => a > b ? a : b);
      return BandHeartRate(
        avg: (sum / values.length).round(),
        max: maxV.round(),
        samples: values.length,
      );
    } catch (e) {
      debugPrint('Error leyendo el pulso de Health Connect: $e');
      return null;
    }
  }

  /// Trae el pulso de la banda y lo guarda en la sesión de Firestore.
  /// Devuelve null si no había datos.
  Future<BandHeartRate?> syncSession({
    required String uid,
    required String sessionId,
    required DateTime start,
    required DateTime end,
  }) async {
    final hr = await heartRateBetween(start, end);
    if (hr == null) return null;
    await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('sessions')
        .doc(sessionId)
        .update({
      'avgHr': hr.avg,
      'maxHr': hr.max,
      'hrSamples': hr.samples,
      'sensorSource': 'band',
    });
    return hr;
  }
}