import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

/// Pantalla que ve el entrenador al tocar un deportista.
/// Muestra las recomendaciones generadas por la IA y deja que el entrenador
/// las apruebe, edite o rechace: la decisión final es siempre humana.
///
/// Colección esperada: recommendations/{id}
///   athleteId: String, text: String, status: 'pending'|'approved'|'rejected',
///   createdAt: Timestamp, source: 'ai'
class DeportistaDetailScreen extends StatelessWidget {
  final String athleteId;
  final String athleteName;

  const DeportistaDetailScreen({
    super.key,
    required this.athleteId,
    required this.athleteName,
  });

  Future<void> _decide(
    String docId, {
    required bool approve,
    String? editedText,
  }) {
    return FirebaseFirestore.instance
        .collection('recommendations')
        .doc(docId)
        .update({
      'status': approve ? 'approved' : 'rejected',
      if (editedText != null) 'finalText': editedText,
      'decidedBy': FirebaseAuth.instance.currentUser?.uid,
      'decidedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> _editAndApprove(
      BuildContext context, String docId, String original) async {
    final controller = TextEditingController(text: original);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Editar y aprobar'),
        content: TextField(controller: controller, maxLines: 6),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar')),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              child: const Text('Aprobar')),
        ],
      ),
    );
    controller.dispose();
    if (result != null && result.isNotEmpty) {
      await _decide(docId, approve: true, editedText: result);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
        title: Text(athleteName,
            style: const TextStyle(
                color: Colors.black, fontWeight: FontWeight.bold)),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        // Solo where() de igualdad: no requiere índice compuesto.
        // El orden se hace en el cliente.
        stream: FirebaseFirestore.instance
            .collection('recommendations')
            .where('athleteId', isEqualTo: athleteId)
            .snapshots(),
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(child: Text('Error: ${snap.error}'));
          }
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final docs = [...?snap.data?.docs];
          docs.sort((a, b) {
            final ta = a.data()['createdAt'];
            final tb = b.data()['createdAt'];
            if (ta is Timestamp && tb is Timestamp) return tb.compareTo(ta);
            return 0;
          });
          if (docs.isEmpty) {
            return const Center(
                child: Text('Aún no hay recomendaciones para este deportista.'));
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            itemBuilder: (context, i) {
              final d = docs[i];
              final data = d.data();
              final status = (data['status'] as String?) ?? 'pending';
              final text =
                  (data['finalText'] ?? data['text'] ?? '').toString();
              return Card(
                color: Colors.grey[200],
                elevation: 0,
                margin: const EdgeInsets.only(bottom: 12),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        const Icon(Icons.auto_awesome, size: 16),
                        const SizedBox(width: 6),
                        Text(
                          status == 'pending'
                              ? 'Sugerencia de IA (pendiente)'
                              : status == 'approved'
                                  ? 'Aprobada'
                                  : 'Rechazada',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ]),
                      const SizedBox(height: 8),
                      Text(text),
                      if (status == 'pending') ...[
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton(
                              onPressed: () => _decide(d.id, approve: false),
                              child: const Text('Rechazar'),
                            ),
                            TextButton(
                              onPressed: () =>
                                  _editAndApprove(context, d.id, text),
                              child: const Text('Editar'),
                            ),
                            ElevatedButton(
                              onPressed: () => _decide(d.id, approve: true),
                              child: const Text('Aprobar'),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}