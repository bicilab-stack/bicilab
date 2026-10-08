import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../services/ride_tracker.dart';
import 'welcome_screen.dart';

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
    _tracker.dispose();
    super.dispose();
  }

  void _followUser() {
    if (!_mapReady || !_tracker.tracking || _tracker.route.isEmpty) return;
    _mapController.move(_tracker.route.last, _mapController.camera.zoom);
  }

  void _msg(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _toggle() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      if (_tracker.tracking) {
        final saved = await _tracker.stopAndSave();
        if (saved == null) {
          _msg('Recorrido muy corto (menos de 10 s): no se guardó');
        } else {
          _msg('Recorrido guardado: ${saved['distanceKm']} km');
        }
      } else {
        final err = await _tracker.start();
        if (err != null) _msg(err);
      }
    } catch (e) {
      _msg('No se pudo guardar el recorrido: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: ListenableBuilder(
          listenable: _tracker,
          builder: (context, _) {
            final t = _tracker;
            final demo = t.demoSensors ? ' (demo)' : '';
            return Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 20.0, vertical: 10.0),
              child: Column(
                children: [
                  Row(
                    children: [
                      const SizedBox(width: 48),
                      const Expanded(
                        child: Text(
                          'BiciLab',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                              color: Colors.black),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Cerrar sesión',
                        icon: const Icon(Icons.logout),
                        onPressed: _logout,
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    flex: 4,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: FlutterMap(
                        mapController: _mapController,
                        options: MapOptions(
                          initialCenter: _defaultCenter,
                          initialZoom: 15,
                          onMapReady: () => _mapReady = true,
                        ),
                        children: [
                          TileLayer(
                            urlTemplate:
                                'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                            userAgentPackageName: 'com.example.bicilab',
                          ),
                          PolylineLayer(
                            polylines: [
                              Polyline(
                                points: List.of(t.route),
                                strokeWidth: 5,
                                color: Colors.blueAccent,
                              ),
                            ],
                          ),
                          if (t.route.isNotEmpty)
                            MarkerLayer(
                              markers: [
                                Marker(
                                  point: t.route.last,
                                  width: 40,
                                  height: 40,
                                  child: const Icon(Icons.pedal_bike,
                                      size: 32, color: Colors.redAccent),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    flex: 5,
                    child: ListView(
                      children: [
                        MetricCard(label: 'Tiempo: ${_fmtDuration(t.elapsed)}'),
                        const SizedBox(height: 10),
                        MetricCard(
                            label:
                                'Velocidad: ${t.speedKmh.toStringAsFixed(1)} km/h'),
                        const SizedBox(height: 10),
                        MetricCard(
                            label:
                                'Distancia: ${(t.distanceM / 1000).toStringAsFixed(2)} km'),
                        const SizedBox(height: 10),
                        MetricCard(label: 'Cadencia: ${t.cadence} RPM$demo'),
                        const SizedBox(height: 10),
                        MetricCard(
                            label: 'Frecuencia cardiaca: ${t.hr} BPM$demo'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _busy ? null : _toggle,
                      style: ElevatedButton.styleFrom(
                        backgroundColor:
                            t.tracking ? Colors.red[700] : Colors.black,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30)),
                      ),
                      child: _busy
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : Text(
                              t.tracking
                                  ? 'TERMINAR RECORRIDO'
                                  : 'INICIAR RECORRIDO',
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold),
                            ),
                    ),
                  ),
                  const SizedBox(height: 6),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class MetricCard extends StatelessWidget {
  final String label;

  const MetricCard({super.key, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
      decoration: BoxDecoration(
        color: Colors.grey[300],
        borderRadius: BorderRadius.circular(25),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: Colors.black,
        ),
      ),
    );
  }
}