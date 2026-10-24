import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/health_service.dart';
import '../widgets/progress_charts.dart';

/// Vista del deportista: recomendaciones APROBADAS por su entrenador y el
/// historial de sus recorridos.
class AthleteHistoryScreen extends StatefulWidget {
  const AthleteHistoryScreen({super.key});

  @override
  State<AthleteHistoryScreen> createState() => _AthleteHistoryScreenState();
}

class _AthleteHistoryScreenState extends State<AthleteHistoryScreen> {
  late final String? _uid = FirebaseAuth.instance.currentUser?.uid;
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _recsStream;
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _sessionsStream;

  @override
  void initState() {
    super.initState();
    final db = FirebaseFirestore.instance;
    // Un solo filtro de igualdad: no requiere índice. Se separa por estado
    // en el cliente (aprobadas / pendientes).
    _recsStream = db
        .collection('recommendations')
        .where('athleteId', isEqualTo: _uid)
        .snapshots();
    _sessionsStream = db
        .collection('users')
        .doc(_uid)
        .collection('sessions')
        .orderBy('endedAt', descending: true)
        .limit(50)
        .snapshots();
  }

  @override
  Widget build(BuildContext context) {
    if (_uid == null) {
      return const Scaffold(body: Center(child: Text('No hay sesión activa')));
    }
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          iconTheme: const IconThemeData(color: Colors.black),
          title: const Text('Mi progreso',
              style:
                  TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          bottom: const TabBar(
            labelColor: Colors.black,
            indicatorColor: Colors.black,
            tabs: [
              Tab(text: 'Sugerencias'),
              Tab(text: 'Recorridos'),
              Tab(text: 'Gráficas'),
            ],
          ),
        ),
        // Un solo StreamBuilder para los recorridos: lo comparten las
        // pestañas "Recorridos" y "Gráficas" (así no se escucha dos veces).
        body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _sessionsStream,
          builder: (context, snap) {
            return TabBarView(
              children: [
                _RecommendationsTab(stream: _recsStream),
                _SessionsTab(snap: snap),
                _ChartsTab(snap: snap),
              ],
            );
          },
        ),
      ),
    );
  }
}

String _fmtDate(dynamic ts) {
  if (ts is! Timestamp) return '';
  final d = ts.toDate().toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(d.day)}/${two(d.month)}/${d.year}  ${two(d.hour)}:${two(d.minute)}';
}

String _v(Map<String, dynamic> d, String key, String suffix) {
  final value = d[key];
  if (value == null) return '-';
  return '$value$suffix';
}

// ---------------------------------------------------------------------------
// Recomendaciones aprobadas
// ---------------------------------------------------------------------------
class _RecommendationsTab extends StatelessWidget {
  final Stream<QuerySnapshot<Map<String, dynamic>>> stream;
  const _RecommendationsTab({required this.stream});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(child: Text('Error: ${snap.error}'));
        }
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final all = snap.data?.docs.map((d) => d.data()).toList() ?? [];
        final approved =
            all.where((d) => d['status'] == 'approved').toList()
              ..sort((a, b) {
                final ta = a['decidedAt'] ?? a['createdAt'];
                final tb = b['decidedAt'] ?? b['createdAt'];
                if (ta is Timestamp && tb is Timestamp) return tb.compareTo(ta);
                return 0;
              });
        final pending = all.where((d) => d['status'] == 'pending').length;

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (pending > 0)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.amber[100],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(children: [
                  const Icon(Icons.hourglass_top, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                        '$pending sugerencia${pending == 1 ? '' : 's'} en revisión por tu entrenador'),
                  ),
                ]),
              ),
            if (approved.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 40),
                child: Center(
                  child: Text(
                    'Aún no tienes recomendaciones aprobadas.\nTermina un recorrido y tu entrenador las revisará.',
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            for (final d in approved) _RecommendationCard(data: d),
          ],
        );
      },
    );
  }
}

class _RecommendationCard extends StatelessWidget {
  final Map<String, dynamic> data;
  const _RecommendationCard({required this.data});

  @override
  Widget build(BuildContext context) {
    final original = (data['text'] ?? '').toString();
    final finalText = (data['finalText'] ?? original).toString();
    final edited = data['finalText'] != null && data['finalText'] != original;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.verified, size: 18, color: Colors.green),
            const SizedBox(width: 6),
            const Text('Aprobada por tu entrenador',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const Spacer(),
            Text(_fmtDate(data['decidedAt'] ?? data['createdAt']),
                style: const TextStyle(fontSize: 12, color: Colors.black54)),
          ]),
          const SizedBox(height: 10),
          Text(finalText),
          if (edited) ...[
            const SizedBox(height: 8),
            const Text('Ajustada por tu entrenador',
                style: TextStyle(fontSize: 12, color: Colors.black54)),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Historial de recorridos
// ---------------------------------------------------------------------------
class _SessionsTab extends StatelessWidget {
  final AsyncSnapshot<QuerySnapshot<Map<String, dynamic>>> snap;
  const _SessionsTab({required this.snap});

  @override
  Widget build(BuildContext context) {
    if (snap.hasError) {
      return Center(child: Text('Error: ${snap.error}'));
    }
    if (snap.connectionState == ConnectionState.waiting) {
      return const Center(child: CircularProgressIndicator());
    }
    final docs = snap.data?.docs ?? [];
    if (docs.isEmpty) {
      return const Center(child: Text('Aún no has registrado recorridos.'));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: docs.length,
      itemBuilder: (context, i) =>
          _SessionCard(id: docs[i].id, data: docs[i].data()),
    );
  }
}

// ---------------------------------------------------------------------------
// Gráficas de progreso
// ---------------------------------------------------------------------------
class _ChartsTab extends StatelessWidget {
  final AsyncSnapshot<QuerySnapshot<Map<String, dynamic>>> snap;
  const _ChartsTab({required this.snap});

  @override
  Widget build(BuildContext context) {
    if (snap.hasError) {
      return Center(child: Text('Error: ${snap.error}'));
    }
    if (snap.connectionState == ConnectionState.waiting) {
      return const Center(child: CircularProgressIndicator());
    }
    final sessions = snap.data?.docs.map((d) => d.data()).toList() ?? [];
    return ProgressCharts(sessions: sessions);
  }
}

class _SessionCard extends StatefulWidget {
  final String id;
  final Map<String, dynamic> data;
  const _SessionCard({required this.id, required this.data});

  @override
  State<_SessionCard> createState() => _SessionCardState();
}

class _SessionCardState extends State<_SessionCard> {
  bool _syncing = false;

  /// Trae el pulso de la banda (Health Connect) para este recorrido.
  Future<void> _syncBand() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final start = widget.data['startedAt'];
    final end = widget.data['endedAt'];
    if (uid == null || start is! Timestamp || end is! Timestamp) return;

    setState(() => _syncing = true);
    String msg;
    try {
      final service = HealthService();
      final ok = await service.requestAccess();
      if (!ok) {
        msg = 'No se pudo acceder a Health Connect. ¿Está instalado y con '
            'permiso para BiciLab?';
      } else {
        final hr = await service
            .syncSession(
              uid: uid,
              sessionId: widget.id,
              start: start.toDate(),
              end: end.toDate(),
            )
            .timeout(const Duration(seconds: 15));
        msg = hr == null
            ? 'Aún no hay pulso para este recorrido. Sincroniza Mi Fitness e '
                'inténtalo de nuevo'
            : 'Pulso importado: ${hr.avg} bpm de media';
      }
    } catch (e) {
      debugPrint('Error trayendo el pulso: $e');
      msg = 'No se pudo traer el pulso de la banda';
    }
    if (!mounted) return;
    setState(() => _syncing = false);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final demo = data['sensorSource'] == 'demo';
    final band = data['sensorSource'] == 'band';
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.pedal_bike, size: 18),
            const SizedBox(width: 6),
            Text(_fmtDate(data['endedAt'] ?? data['startedAt']),
                style: const TextStyle(fontWeight: FontWeight.bold)),
            const Spacer(),
            if (demo)
              const Text('FC/cadencia demo',
                  style: TextStyle(fontSize: 11, color: Colors.black54)),
            if (band)
              const Text('FC de la banda · cadencia demo',
                  style: TextStyle(fontSize: 11, color: Colors.black54)),
          ]),
          const SizedBox(height: 10),
          Wrap(
            spacing: 18,
            runSpacing: 8,
            children: [
              _Stat(Icons.straighten, _v(data, 'distanceKm', ' km')),
              _Stat(Icons.timer_outlined, _v(data, 'durationMin', ' min')),
              _Stat(Icons.speed, _v(data, 'avgSpeedKmh', ' km/h')),
              _Stat(Icons.favorite_border, _v(data, 'avgHr', ' bpm')),
              _Stat(Icons.rotate_right, _v(data, 'avgCadenceRpm', ' rpm')),
              _Stat(Icons.terrain, _v(data, 'elevationGainM', ' m')),
            ],
          ),
          if (demo)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: _syncing ? null : _syncBand,
                icon: _syncing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.watch, size: 18),
                label: const Text('Traer pulso de la banda'),
              ),
            ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Stat(this.icon, this.text);

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 16, color: Colors.black54),
      const SizedBox(width: 4),
      Text(text),
    ]);
  }
}