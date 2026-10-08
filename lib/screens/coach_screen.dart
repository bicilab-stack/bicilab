import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/coach_code_service.dart';
import 'welcome_screen.dart';
import 'when_coach_touch_deportista_screen.dart';

class CoachScreen extends StatefulWidget {
  const CoachScreen({super.key});

  @override
  State<CoachScreen> createState() => _CoachScreenState();
}

class _CoachScreenState extends State<CoachScreen> {
  String _searchQuery = '';
  bool _onlyActiveToday = false;
  int _selectedIndex = 0;

  // El stream se crea UNA vez. Antes se creaba dentro de build(), así que
  // cada letra escrita en el buscador cancelaba y recreaba la suscripción
  // (parpadeo con CircularProgressIndicator y lecturas extra a Firestore).
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _athletesStream;
  late final Future<String> _codeFuture;

  @override
  void initState() {
    super.initState();
    _athletesStream = FirebaseFirestore.instance
        .collection('users')
        .where('role', isEqualTo: 'deportista')
        .where('coachId', isEqualTo: FirebaseAuth.instance.currentUser?.uid)
        .snapshots();
    _codeFuture = CoachCodeService.ensureCoachCode();
  }

  bool _isActiveToday(Map<String, dynamic> data) {
    final ts = data['lastActivity'];
    if (ts is! Timestamp) return false;
    final d = ts.toDate();
    final now = DateTime.now();
    return d.year == now.year && d.month == now.month && d.day == now.day;
  }

  String _displayName(Map<String, dynamic> data) {
    final nombre = (data['nombre'] as String?)?.trim();
    if (nombre != null && nombre.isNotEmpty) return nombre;
    final email = (data['email'] as String?)?.trim();
    if (email != null && email.isNotEmpty) return email;
    return 'Deportista';
  }

  Future<void> _logout() async {
    await FirebaseAuth.instance.signOut();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const WelcomeScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: _selectedIndex == 0 ? _buildTeamTab() : _buildProfileTab(),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        selectedItemColor: Colors.black,
        unselectedItemColor: Colors.black45,
        onTap: (i) => setState(() => _selectedIndex = i),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.groups), label: 'Equipo'),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Perfil'),
        ],
      ),
    );
  }

  Widget _buildProfileTab() {
    final user = FirebaseAuth.instance.currentUser;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.account_circle, size: 80, color: Colors.black87),
            const SizedBox(height: 12),
            Text(user?.email ?? 'Entrenador',
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 24),
            const Text('Código para tus deportistas',
                style: TextStyle(color: Colors.black54)),
            const SizedBox(height: 8),
            FutureBuilder<String>(
              future: _codeFuture,
              builder: (context, snap) {
                if (snap.hasError) {
                  return Text('No se pudo obtener el código:\n${snap.error}',
                      textAlign: TextAlign.center);
                }
                if (!snap.hasData) return const CircularProgressIndicator();
                final code = snap.data!;
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(code,
                        style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 4)),
                    IconButton(
                      icon: const Icon(Icons.copy),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: code));
                        ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Código copiado')));
                      },
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _logout,
              icon: const Icon(Icons.logout),
              label: const Text('Cerrar sesión'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.black,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTeamTab() {
    return Column(
      children: [
        const SizedBox(height: 30),
        const Text(
          'Tu equipo',
          style: TextStyle(
              fontSize: 32, fontWeight: FontWeight.bold, color: Colors.black),
        ),
        const SizedBox(height: 20),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: [
              Expanded(
                child: Container(
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.grey[200],
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: TextField(
                    onChanged: (v) =>
                        setState(() => _searchQuery = v.trim().toLowerCase()),
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search, color: Colors.black54),
                      hintText: 'Buscar por nombre',
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              // El "Filtro" ahora es funcional: alterna "Activos hoy".
              InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () => setState(() => _onlyActiveToday = !_onlyActiveToday),
                child: Container(
                  height: 40,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: _onlyActiveToday
                        ? Colors.greenAccent[400]
                        : Colors.grey[300],
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    _onlyActiveToday ? 'Activos hoy' : 'Filtro',
                    style: const TextStyle(color: Colors.black87),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Expanded(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 20),
            color: const Color(0xFFE0E0E0),
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _athletesStream,
              builder: (context, snapshot) {
                // Antes no se manejaba snapshot.hasError: un error de
                // permisos de Firestore se veía como "No tienes deportistas".
                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        'No se pudo cargar el equipo.\n${snapshot.error}',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                var items = (snapshot.data?.docs ?? [])
                    .map((d) => MapEntry(d.id, d.data()))
                    .toList();

                if (_searchQuery.isNotEmpty) {
                  items = items
                      .where((e) => _displayName(e.value)
                          .toLowerCase()
                          .contains(_searchQuery))
                      .toList();
                }
                if (_onlyActiveToday) {
                  items = items.where((e) => _isActiveToday(e.value)).toList();
                }
                items.sort((a, b) => _displayName(a.value)
                    .toLowerCase()
                    .compareTo(_displayName(b.value).toLowerCase()));

                if (items.isEmpty) {
                  return const Center(
                      child: Text(
                          'Aún no tienes deportistas vinculados.\nComparte tu código desde la pestaña Perfil.',
                          textAlign: TextAlign.center));
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(10),
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final uid = items[index].key;
                    final data = items[index].value;
                    final name = _displayName(data);
                    final active = _isActiveToday(data); // dato real

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Material(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(5),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(5),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => DeportistaDetailScreen(
                                  athleteId: uid, athleteName: name),
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 12),
                            child: Row(
                              children: [
                                const Icon(Icons.account_circle,
                                    size: 35, color: Colors.black87),
                                const SizedBox(width: 15),
                                Expanded(
                                  child: Text(
                                    name,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 15),
                                  ),
                                ),
                                if (active)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: Colors.greenAccent[400],
                                      borderRadius: BorderRadius.circular(15),
                                    ),
                                    child: const Text(
                                      'Activo hoy',
                                      style: TextStyle(
                                          color: Colors.black87,
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 12),
      ],
    );
  }
}