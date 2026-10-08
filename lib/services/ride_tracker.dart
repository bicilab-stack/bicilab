import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

/// Controla un recorrido: GPS (real), cronómetro y sensores.
///
/// Frecuencia cardíaca y cadencia arrancan en MODO DEMO (simulados a partir
/// de la velocidad). Cuando llegue la smartband, basta con llamar a
/// [onHeartRate] / [onCadence] con los valores reales: el modo demo se apaga
/// solo y el resto de la app no cambia.
class RideTracker extends ChangeNotifier {
  // ---- Estado visible en la UI ----
  bool tracking = false;
  final List<LatLng> route = [];
  double distanceM = 0;
  double speedKmh = 0;
  double maxSpeedKmh = 0;
  double elevationGainM = 0;
  int hr = 0;
  int maxHr = 0;
  int cadence = 0;
  Duration elapsed = Duration.zero;
  bool demoSensors = true;

  // ---- Internos ----
  StreamSubscription<Position>? _posSub;
  Timer? _timer;
  final Stopwatch _watch = Stopwatch();
  final Random _rnd = Random();
  Position? _last;
  DateTime? _lastFixAt;
  DateTime? _startedAt;
  double? _refAltitude;
  int _hrSum = 0;
  int _hrCount = 0;
  int _cadSum = 0;
  int _cadCount = 0;

  // ---- Permisos ----
  Future<String?> _ensurePermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return 'Activa el GPS del teléfono';
    }
    var p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied) {
      p = await Geolocator.requestPermission();
    }
    if (p == LocationPermission.denied) {
      return 'Permiso de ubicación denegado';
    }
    if (p == LocationPermission.deniedForever) {
      return 'Permiso bloqueado: actívalo en Ajustes > Aplicaciones > bicilab';
    }
    return null;
  }

  /// Devuelve null si todo salió bien, o un mensaje de error para mostrar.
  Future<String?> start() async {
    if (tracking) return null;
    final err = await _ensurePermission();
    if (err != null) return err;

    _reset();
    tracking = true;
    _startedAt = DateTime.now();
    _watch
      ..reset()
      ..start();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    _posSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 5, // metros mínimos entre lecturas
      ),
    ).listen(_onPosition, onError: (_) {});
    notifyListeners();
    return null;
  }

  void _reset() {
    route.clear();
    distanceM = 0;
    speedKmh = 0;
    maxSpeedKmh = 0;
    elevationGainM = 0;
    hr = 0;
    maxHr = 0;
    cadence = 0;
    elapsed = Duration.zero;
    _last = null;
    _lastFixAt = null;
    _refAltitude = null;
    _hrSum = 0;
    _hrCount = 0;
    _cadSum = 0;
    _cadCount = 0;
  }

  void _onPosition(Position p) {
    // Descarta lecturas poco confiables (típico bajo techo).
    if (p.accuracy > 30) return;

    final last = _last;
    if (last != null) {
      distanceM += Geolocator.distanceBetween(
          last.latitude, last.longitude, p.latitude, p.longitude);
    }

    // Desnivel acumulado con umbral de 2 m para filtrar el ruido del GPS.
    final ref = _refAltitude;
    if (ref == null) {
      _refAltitude = p.altitude;
    } else if (p.altitude - ref > 2) {
      elevationGainM += p.altitude - ref;
      _refAltitude = p.altitude;
    } else if (ref - p.altitude > 2) {
      _refAltitude = p.altitude;
    }

    speedKmh = (p.speed.isFinite && p.speed > 0) ? p.speed * 3.6 : 0;
    maxSpeedKmh = max(maxSpeedKmh, speedKmh);

    _last = p;
    _lastFixAt = DateTime.now();
    route.add(LatLng(p.latitude, p.longitude));
    notifyListeners();
  }

  void _tick() {
    elapsed = _watch.elapsed;

    // Si no llegan lecturas (estás detenido), la velocidad pasa a 0.
    final fix = _lastFixAt;
    if (fix != null && DateTime.now().difference(fix).inSeconds > 6) {
      speedKmh = 0;
    }

    if (demoSensors) {
      final moving = speedKmh > 1;
      final targetHr = moving ? 95 + speedKmh * 3.2 : 80.0;
      hr = (targetHr + _rnd.nextInt(7) - 3).round().clamp(55, 195).toInt();
      cadence = moving
          ? (55 + speedKmh * 1.8 + _rnd.nextInt(7) - 3)
              .round()
              .clamp(0, 130)
              .toInt()
          : 0;
    }

    if (hr > 0) {
      _hrSum += hr;
      _hrCount++;
      maxHr = max(maxHr, hr);
    }
    if (cadence > 0) {
      _cadSum += cadence;
      _cadCount++;
    }
    notifyListeners();
  }

  // ---- Para la smartband / sensor BLE (mañana) ----
  void onHeartRate(int bpm) {
    demoSensors = false;
    hr = bpm;
    notifyListeners();
  }

  void onCadence(int rpm) {
    demoSensors = false;
    cadence = rpm;
    notifyListeners();
  }

  // ---- Terminar y guardar ----
  /// Devuelve las métricas guardadas (con el id de la sesión) o null si el
  /// recorrido fue demasiado corto (< 10 s) y se descartó.
  /// Las claves coinciden con las que espera RecommendationService.
  Future<Map<String, dynamic>?> stopAndSave() async {
    await _posSub?.cancel();
    _posSub = null;
    _timer?.cancel();
    _timer = null;
    _watch.stop();
    tracking = false;

    final seconds = _watch.elapsed.inSeconds;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || seconds < 10) {
      notifyListeners();
      return null;
    }

    final km = distanceM / 1000;
    final metrics = <String, dynamic>{
      'distanceKm': _round(km, 2),
      'durationMin': _round(seconds / 60, 1),
      'avgSpeedKmh': _round(km / (seconds / 3600), 1),
      'maxSpeedKmh': _round(maxSpeedKmh, 1),
      'avgHr': _hrCount > 0 ? (_hrSum / _hrCount).round() : 0,
      'maxHr': maxHr,
      'avgCadenceRpm': _cadCount > 0 ? (_cadSum / _cadCount).round() : 0,
      'elevationGainM': elevationGainM.round(),
      'sensorSource': demoSensors ? 'demo' : 'band',
    };

    final db = FirebaseFirestore.instance;
    final userRef = db.collection('users').doc(user.uid);
    final ref = await userRef.collection('sessions').add({
      ...metrics,
      'route': _downsample().map((p) => GeoPoint(p.latitude, p.longitude)).toList(),
      'startedAt': Timestamp.fromDate(_startedAt ?? DateTime.now()),
      'endedAt': FieldValue.serverTimestamp(),
    });
    // Esto es lo que enciende "Activo hoy" en la pantalla del entrenador.
    await userRef.update({'lastActivity': FieldValue.serverTimestamp()});

    notifyListeners();
    return {...metrics, 'id': ref.id};
  }

  /// Firestore limita cada documento a 1 MB: guardamos máx. 300 puntos.
  List<LatLng> _downsample([int maxPoints = 300]) {
    if (route.length <= maxPoints) return List.of(route);
    final step = route.length / maxPoints;
    return List.generate(maxPoints, (i) => route[(i * step).floor()]);
  }

  double _round(double v, int decimals) {
    final f = pow(10, decimals).toDouble();
    return (v * f).round() / f;
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _timer?.cancel();
    super.dispose();
  }
}