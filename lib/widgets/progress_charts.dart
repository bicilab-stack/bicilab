import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

// Colores del logo de BiciLab.
const _yellow = Color(0xFFFFCC00);
const _red = Color(0xFFCC0000);

/// Gráficas de progreso a partir de los recorridos (documentos de
/// users/{uid}/sessions). Sin dependencias externas: se dibuja con CustomPaint.
///
/// Muestra: resumen (recorridos, km totales, velocidad media), distancia por
/// recorrido (barras) y velocidad media por recorrido (línea) de los últimos
/// 10 recorridos.
class ProgressCharts extends StatelessWidget {
  final List<Map<String, dynamic>> sessions;
  const ProgressCharts({super.key, required this.sessions});

  static double? _num(Map<String, dynamic> d, String key) {
    final v = d[key];
    return v is num ? v.toDouble() : null;
  }

  static String _label(Timestamp ts) {
    final d = ts.toDate().toLocal();
    return '${d.day}/${d.month}';
  }

  @override
  Widget build(BuildContext context) {
    // Solo recorridos con fecha; de más antiguo a más reciente.
    final rides = sessions.where((s) => s['endedAt'] is Timestamp).toList()
      ..sort((a, b) =>
          (a['endedAt'] as Timestamp).compareTo(b['endedAt'] as Timestamp));

    if (rides.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Aún no hay datos para graficar.\nTermina un recorrido para ver tu progreso.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    final totalKm =
        rides.fold<double>(0, (sum, s) => sum + (_num(s, 'distanceKm') ?? 0));
    final speeds =
        rides.map((s) => _num(s, 'avgSpeedKmh')).whereType<double>().toList();
    final avgSpeed = speeds.isEmpty
        ? 0.0
        : speeds.reduce((a, b) => a + b) / speeds.length;

    final last = rides.length > 10 ? rides.sublist(rides.length - 10) : rides;
    final labels = last.map((s) => _label(s['endedAt'] as Timestamp)).toList();
    final km = last.map((s) => _num(s, 'distanceKm') ?? 0).toList();
    final spd = last.map((s) => _num(s, 'avgSpeedKmh') ?? 0).toList();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Expanded(
                child: _SummaryTile(
                    label: 'Recorridos', value: '${rides.length}')),
            const SizedBox(width: 10),
            Expanded(
                child: _SummaryTile(
                    label: 'Distancia total',
                    value: '${totalKm.toStringAsFixed(1)} km')),
            const SizedBox(width: 10),
            Expanded(
                child: _SummaryTile(
                    label: 'Vel. media',
                    value: '${avgSpeed.toStringAsFixed(1)} km/h')),
          ],
        ),
        const SizedBox(height: 16),
        _ChartCard(
          title: 'Distancia por recorrido (km)',
          child: CustomPaint(
            size: Size.infinite,
            painter: _BarPainter(values: km, labels: labels),
          ),
        ),
        const SizedBox(height: 16),
        _ChartCard(
          title: 'Velocidad media (km/h)',
          child: CustomPaint(
            size: Size.infinite,
            painter: _LinePainter(values: spd, labels: labels),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          rides.length > 10
              ? 'Se muestran los últimos 10 recorridos.'
              : 'Se muestran todos tus recorridos.',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 12, color: Colors.black54),
        ),
      ],
    );
  }
}

class _SummaryTile extends StatelessWidget {
  final String label;
  final String value;
  const _SummaryTile({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(color: Colors.white70, fontSize: 11)),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value,
                style: const TextStyle(
                    color: _yellow, fontSize: 20, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}

class _ChartCard extends StatelessWidget {
  final String title;
  final Widget child;
  const _ChartCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          SizedBox(height: 180, child: child),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Dibujo
// ---------------------------------------------------------------------------
const double _topPad = 18; // espacio para el valor sobre la barra/punto
const double _bottomPad = 22; // espacio para las etiquetas del eje X

void _drawText(Canvas canvas, String text, Offset center,
    {double size = 10, Color color = Colors.black54, bool bold = false}) {
  final tp = TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(
        fontSize: size,
        color: color,
        fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
}

String _fmt(double v) => v.toStringAsFixed(v >= 100 ? 0 : 1);

void _drawGrid(Canvas canvas, Size size) {
  final paint = Paint()
    ..color = Colors.black12
    ..strokeWidth = 1;
  final top = _topPad;
  final bottom = size.height - _bottomPad;
  for (var i = 0; i <= 2; i++) {
    final y = top + (bottom - top) * i / 2;
    canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
  }
}

class _BarPainter extends CustomPainter {
  final List<double> values;
  final List<String> labels;
  _BarPainter({required this.values, required this.labels});

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    _drawGrid(canvas, size);

    final maxV = values.reduce((a, b) => a > b ? a : b);
    final maxY = maxV <= 0 ? 1.0 : maxV * 1.1;
    final top = _topPad;
    final bottom = size.height - _bottomPad;
    final slot = size.width / values.length;
    final barW = (slot * 0.6).clamp(6.0, 36.0);

    final barPaint = Paint()..color = _yellow;
    final edge = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    for (var i = 0; i < values.length; i++) {
      final cx = slot * i + slot / 2;
      final h = (values[i] / maxY) * (bottom - top);
      final rect = RRect.fromRectAndCorners(
        Rect.fromLTWH(cx - barW / 2, bottom - h, barW, h),
        topLeft: const Radius.circular(6),
        topRight: const Radius.circular(6),
      );
      canvas.drawRRect(rect, barPaint);
      canvas.drawRRect(rect, edge);
      _drawText(canvas, _fmt(values[i]), Offset(cx, bottom - h - 9),
          color: Colors.black, bold: true);
      _drawText(canvas, labels[i], Offset(cx, size.height - 8));
    }
  }

  @override
  bool shouldRepaint(covariant _BarPainter old) => true;
}

class _LinePainter extends CustomPainter {
  final List<double> values;
  final List<String> labels;
  _LinePainter({required this.values, required this.labels});

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    _drawGrid(canvas, size);

    var minV = values.reduce((a, b) => a < b ? a : b);
    var maxV = values.reduce((a, b) => a > b ? a : b);
    if (maxV - minV < 1) {
      // Todos casi iguales: da un rango mínimo para que no quede plana.
      minV -= 1;
      maxV += 1;
    }
    final pad = (maxV - minV) * 0.15;
    minV -= pad;
    maxV += pad;

    final top = _topPad;
    final bottom = size.height - _bottomPad;
    final slot = size.width / values.length;

    Offset point(int i) {
      final x = slot * i + slot / 2;
      final y = bottom - ((values[i] - minV) / (maxV - minV)) * (bottom - top);
      return Offset(x, y);
    }

    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final p = point(i);
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    if (values.length > 1) {
      canvas.drawPath(
        path,
        Paint()
          ..color = Colors.black
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..strokeJoin = StrokeJoin.round
          ..strokeCap = StrokeCap.round,
      );
    }

    for (var i = 0; i < values.length; i++) {
      final p = point(i);
      canvas.drawCircle(p, 6, Paint()..color = _yellow);
      canvas.drawCircle(
        p,
        6,
        Paint()
          ..color = _red
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
      _drawText(canvas, _fmt(values[i]), Offset(p.dx, p.dy - 15),
          color: Colors.black, bold: true);
      _drawText(canvas, labels[i], Offset(p.dx, size.height - 8));
    }
  }

  @override
  bool shouldRepaint(covariant _LinePainter old) => true;
}