import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/coach_code_service.dart';
import '../utils/auth_errors.dart';
import 'coach_screen.dart';
import 'home_screen.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  String _selectedRole = 'deportista';
  bool _loading = false;

  final _nombreController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _coachCodeController = TextEditingController();

  @override
  void dispose() {
    _nombreController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _coachCodeController.dispose();
    super.dispose();
  }

  void _msg(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  InputDecoration _decoration(String hint) => InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
      );

  Future<void> _register() async {
    final nombre = _nombreController.text.trim();
    final email = _emailController.text.trim();
    final pass = _passwordController.text.trim();

    if (nombre.isEmpty || email.isEmpty || pass.isEmpty) {
      _msg('Completa nombre, correo y contraseña');
      return;
    }
    if (!isValidEmail(email)) {
      _msg('El correo no tiene un formato válido');
      return;
    }
    if (pass.length < 6) {
      _msg('La contraseña debe tener al menos 6 caracteres');
      return;
    }
    if (pass != _confirmPasswordController.text.trim()) {
      _msg('Las contraseñas no coinciden');
      return;
    }

    setState(() => _loading = true);
    try {
      // 1. Si es deportista y puso código, validarlo ANTES de crear la cuenta.
      String? coachId;
      if (_selectedRole == 'deportista' &&
          _coachCodeController.text.trim().isNotEmpty) {
        coachId =
            await CoachCodeService.resolveCoachId(_coachCodeController.text);
        if (coachId == null) {
          _msg('El código de entrenador no existe');
          return; // el finally quita el loading
        }
      }

      // 2. Crear usuario en Firebase Auth.
      final cred = await FirebaseAuth.instance
          .createUserWithEmailAndPassword(email: email, password: pass);

      // 3. Guardar perfil en Firestore.
      await FirebaseFirestore.instance
          .collection('users')
          .doc(cred.user!.uid)
          .set({
        'nombre': nombre,
        'email': email,
        'role': _selectedRole,
        'coachId': ?coachId,
        'createdAt': FieldValue.serverTimestamp(),
      });

      // 4. Si es entrenador, generar su código de invitación.
      if (_selectedRole == 'entrenador') {
        await CoachCodeService.ensureCoachCode();
      }

      if (!mounted) return;
      final Widget next = _selectedRole == 'entrenador'
          ? const CoachScreen()
          : const HomeScreen();
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => next),
        (route) => false,
      );
    } on FirebaseAuthException catch (e) {
      _msg(friendlyAuthError(e));
    } catch (e) {
      debugPrint('Register error: $e');
      _msg('No se pudo completar el registro. Revisa tu conexión e inténtalo de nuevo');
    } finally {
      if (mounted) setState(() => _loading = false);
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
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20.0),
          child: Column(
            children: [
              const Icon(Icons.account_circle, size: 80, color: Colors.black87),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(25),
                decoration: BoxDecoration(
                  color: const Color(0xFFE0E0E0),
                  borderRadius: BorderRadius.circular(30),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: _nombreController,
                      textCapitalization: TextCapitalization.words,
                      decoration: _decoration('Nombre completo'),
                    ),
                    const SizedBox(height: 15),
                    TextField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      decoration: _decoration('Correo electrónico'),
                    ),
                    const SizedBox(height: 15),
                    TextField(
                      controller: _passwordController,
                      obscureText: true,
                      decoration: _decoration('Contraseña'),
                    ),
                    const SizedBox(height: 15),
                    TextField(
                      controller: _confirmPasswordController,
                      obscureText: true,
                      decoration: _decoration('Confirmar contraseña'),
                    ),
                    const SizedBox(height: 25),
                    const Text('Selecciona tu rol:',
                        style:
                            TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 10),
                    RadioGroup<String>(
                      groupValue: _selectedRole,
                      onChanged: (String? value) {
                        if (value == null) return;
                        setState(() => _selectedRole = value);
                      },
                      child: const Column(
                        children: [
                          Row(
                            children: [
                              Radio<String>(
                                  value: 'deportista',
                                  activeColor: Colors.black),
                              Text('Soy deportista',
                                  style:
                                      TextStyle(fontWeight: FontWeight.w500)),
                            ],
                          ),
                          Row(
                            children: [
                              Radio<String>(
                                  value: 'entrenador',
                                  activeColor: Colors.black),
                              Text('Soy entrenador',
                                  style:
                                      TextStyle(fontWeight: FontWeight.w500)),
                            ],
                          ),
                        ],
                      ),
                    ),
                    if (_selectedRole == 'deportista') ...[
                      const SizedBox(height: 15),
                      TextField(
                        controller: _coachCodeController,
                        textCapitalization: TextCapitalization.characters,
                        decoration:
                            _decoration('Código de tu entrenador (opcional)'),
                      ),
                    ],
                    const SizedBox(height: 30),
                    ElevatedButton(
                      onPressed: _loading ? null : _register,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30)),
                      ),
                      child: _loading
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('REGISTRARME',
                              style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }
}