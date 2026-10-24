import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../services/health_service.dart';
import '../services/recommendation_service.dart';
import '../services/ride_tracker.dart';
import 'athlete_history_screen.dart';
import 'welcome_screen.dart';

// Paleta del logo de BiciLab.
const _yellow = Color(0xFFFFCC00);
const _red = Color(0xFFFF0000);
const _bg = Color(0xFF0E0E0E);
const _tile = Color(0xFF1A1A1A);
const _chip = Color(0xFF1F1F1F);
const _muted = Color(0xFF999999);

// Tipografía de la pantalla. null = la fuente por defecto de Android (Roboto).
// Cuando tengas la licencia de Typo Round, declara la fuente en pubspec.yaml
// y cambia esta línea por: const String? _font = 'TypoRound';
const String? _font = null;

// Filtro que oscurece los tiles de OpenStreetMap (invierte a gris oscuro).
const _darkTiles = ColorFilter.matrix(<double>[
  -0.2126, -0.7152, -0.0722, 0, 255,
  -0.2126, -0.7152, -0.0722, 0, 255,
  -0.2126, -0.7152, -0.0722, 0, 255,
  0, 0, 0, 1, 0,
]);

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _tracker = RideTracker();
  final _mapController = MapController();
  bool _mapReady = false;
  bool _busy = false;

  // Centro inicial genérico (Bogotá) hasta tener la primera lectura GPS.
  static const _defaultCenter = LatLng(4.711, -74.072);

  @override
  void initState() {
    super.initState();
    _tracker.addListener(_followUser);
  }

  @override
  void dispose() {
    _tracker.removeListener(_followUser);
    WakelockPlus.disable();
    _tracker.dispose();
    super.dispose();
  }

  void _followUser() {
    if (!_mapReady || !_tracker.tracking || _tracker.route.isEmpty) return;
    _mapController.move(_tracker.route.last, _mapController.camera.zoom);
  }

  void _msg(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<bool> _confirmFinish() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Terminar recorrido?'),
        content: const Text('Se guardará tu sesión y se generará una '
            'sugerencia para tu entrenador.\n\nPara importar el pulso de tu '
            'banda, abre Mi Fitness un momento y sincronízala antes de '
            'terminar.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Seguir')),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Terminar')),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _toggle() async {
    if (_busy) return;
    if (_tracker.tracking && !await _confirmFinish()) return;

    setState(() => _busy = true);
    try {
      if (_tracker.tracking) {
        // Sin internet, Firestore guarda en cola y no responde: no dejamos
        // la pantalla colgada; el dato se sincroniza solo al volver la red.
        final saved = await _tracker
            .stopAndSave()
            .timeout(const Duration(seconds: 20));
        if (saved == null) {
          _msg('Recorrido muy corto (menos de 10 s): no se guardó');
        } else {
          _msg('Recorrido guardado: ${saved['distanceKm']} km');
          // No bloquea la pantalla: trae el pulso de la banda (si hay) y
          // luego la IA, que tarda unos segundos.
          _afterSave(saved);
        }
      } else {
        final err = await _tracker.start();
        if (err != null) {
          _msg(err);
        } else {
          // Mantiene la pantalla encendida: con pantalla apagada Android
          // puede pausar el GPS.
          WakelockPlus.enable();
          // Pide (una sola vez) permiso para leer el pulso de la banda.
          unawaited(HealthService().requestAccess());
        }
      }
    } on TimeoutException {
      _msg('Sin conexión: tu recorrido se sincronizará cuando vuelva internet');
    } catch (e) {
      debugPrint('Error en recorrido: $e');
      _msg('No se pudo guardar el recorrido. Inténtalo de nuevo');
    } finally {
      if (!_tracker.tracking) WakelockPlus.disable();
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Después de guardar: intenta traer el pulso real de la banda desde
  /// Health Connect y, con esos datos, genera la sugerencia de la IA.
  Future<void> _afterSave(Map<String, dynamic> saved) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final start = _tracker.lastStartedAt;
    final end = _tracker.lastEndedAt;
    var metrics = saved;

    if (uid != null && start != null && end != null && saved['id'] != null) {
      try {
        final hr = await HealthService()
            .syncSession(
              uid: uid,
              sessionId: saved['id'] as String,
              start: start,
              end: end,
            )
            .timeout(const Duration(seconds: 15));
        if (hr != null) {
          metrics = {
            ...saved,
            'avgHr': hr.avg,
            'maxHr': hr.max,
            'sensorSource': 'band',
          };
          _msg('Pulso de la banda importado: ${hr.avg} bpm de media');
        } else {
          _msg('Aún no hay pulso de la banda. Sincroniza Mi Fitness y tráelo '
              'desde Mi progreso');
        }
      } catch (e) {
        debugPrint('No se pudo importar el pulso: $e');
      }
    }
    await _generateRecommendation(metrics);
  }

  Future<void> _generateRecommendation(Map<String, dynamic> session) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final sent = await RecommendationService().generateFor(uid, session);
      _msg(sent
          ? 'Sugerencia enviada a tu entrenador para revisión'
          : 'Vincula un entrenador para recibir recomendaciones');
    } catch (e) {
      debugPrint('Error generando recomendación: $e');
      _msg('La IA no respondió ahora (el recorrido sí se guardó). '
          'Inténtalo de nuevo en unos minutos');
    }
  }

  Future<void> _logout() async {
    if (_tracker.tracking) {
      _msg('Termina el recorrido antes de cerrar sesión');
      return;
    }
    await FirebaseAuth.instance.signOut();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const WelcomeScreen()),
      (route) => false,
    );
  }

  String _fmtDuration(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    return h > 0 ? '$h:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
  }

  Widget _roundIcon(String tooltip, IconData icon, VoidCallback onTap) {
    return Material(
      color: _chip,
      shape: const CircleBorder(),
      child: IconButton(
        tooltip: tooltip,
        icon: Icon(icon, color: _yellow),
        onPressed: onTap,
      ),
    );
  }

  Widget _map(RideTracker t) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: Container(
        height: 220,
        foregroundDecoration: BoxDecoration(
          border: Border.all(color: const Color(0xFF2A2A2A), width: 2),
          borderRadius: BorderRadius.circular(24),
        ),
        child: FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: _defaultCenter,
            initialZoom: 15,
            onMapReady: () => _mapReady = true,
          ),
          children: [
            ColorFiltered(
              colorFilter: _darkTiles,
              child: TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.bicilab',
              ),
            ),
            if (t.route.length >= 2)
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: List.of(t.route),
                    strokeWidth: 5,
                    color: _yellow,
                  ),
                ],
              ),
            if (t.route.isNotEmpty)
              MarkerLayer(
                markers: [
                  Marker(
                    point: t.route.last,
                    width: 28,
                    height: 28,
                    child: Container(
                      decoration: BoxDecoration(
                        color: _red,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 3),
                      ),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: ListenableBuilder(
          listenable: _tracker,
          builder: (context, _) {
            final t = _tracker;
            return PopScope(
              canPop: !t.tracking,
              onPopInvokedWithResult: (didPop, _) {
                if (!didPop) _msg('Termina el recorrido antes de salir');
              },
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                child: Column(
                  children: [
                    Row(
                      children: [
                        _roundIcon(
                          'Mi progreso',
                          Icons.history,
                          () => Navigator.of(context).push(
                            MaterialPageRoute(
                                builder: (_) => const AthleteHistoryScreen()),
                          ),
                        ),
                        const Expanded(
                          child: Text(
                            'BiciLab',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontFamily: _font,
                              fontSize: 28,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        _roundIcon('Cerrar sesión', Icons.logout, _logout),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _map(t),
                    // Parte central con scroll por si la pantalla es pequeña.
                    Expanded(
                      child: SingleChildScrollView(
                        child: Column(
                          children: [
                            const SizedBox(height: 12),
                            const Text('VELOCIDAD',
                                style: TextStyle(
                                    fontFamily: _font,
                                    color: _muted,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 2)),
                            Text(
                              t.speedKmh.toStringAsFixed(1),
                              style: const TextStyle(
                                fontFamily: _font,
                                color: _yellow,
                                fontSize: 80,
                                height: 1.05,
                                fontWeight: FontWeight.w800,
                                fontFeatures: [FontFeature.tabularFigures()],
                              ),
                            ),
                            const Text('km/h',
                                style: TextStyle(
                                    fontFamily: _font,
                                    color: _muted,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600)),
                            const SizedBox(height: 14),
                            Row(
                              children: [
                                Expanded(
                                  child: _StatTile(
                                    label: 'Tiempo',
                                    value: _fmtDuration(t.elapsed),
                                    accent: _yellow,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _StatTile(
                                    label: 'Distancia',
                                    value:
                                        (t.distanceM / 1000).toStringAsFixed(2),
                                    unit: 'km',
                                    accent: _yellow,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: _StatTile(
                                    label: 'Cadencia',
                                    value: '${t.cadence}',
                                    unit: 'RPM',
                                    accent: const Color(0xFF3A3A3A),
                                    demo: t.demoSensors,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _StatTile(
                                    label: 'Frec. cardiaca',
                                    value: '${t.hr}',
                                    unit: 'BPM',
                                    accent: _red,
                                    demo: t.demoSensors,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      height: 60,
                      child: ElevatedButton(
                        onPressed: _busy ? null : _toggle,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: t.tracking ? _red : _yellow,
                          foregroundColor:
                              t.tracking ? Colors.white : Colors.black,
                          disabledBackgroundColor: const Color(0xFF3A3A3A),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(30)),
                        ),
                        child: _busy
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white))
                            : Text(
                                t.tracking
                                    ? 'TERMINAR RECORRIDO'
                                    : 'INICIAR RECORRIDO',
                                style: const TextStyle(
                                  fontFamily: _font,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  final String label;
  final String value;
  final String? unit;
  final Color accent;
  final bool demo;

  const _StatTile({
    required this.label,
    required this.value,
    required this.accent,
    this.unit,
    this.demo = false,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: Container(
        color: _tile,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(height: 3, color: accent),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Flexible(
                        child: Text(label,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontFamily: _font,
                                color: _muted,
                                fontSize: 12,
                                fontWeight: FontWeight.w600)),
                      ),
                      if (demo)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: _yellow,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text('demo',
                              style: TextStyle(
                                  fontFamily: _font,
                                  color: Colors.black,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text.rich(
                    TextSpan(
                      text: value,
                      style: const TextStyle(
                        fontFamily: _font,
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                      children: [
                        if (unit != null)
                          TextSpan(
                            text: ' $unit',
                            style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: _muted),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}