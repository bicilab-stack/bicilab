import 'package:flutter/material.dart';
import 'sign_in_screen.dart';
import 'log_in_screen.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Usamos un Container para aplicar el fondo con degradado
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.white, // Inicia en blanco
              Colors.black, // Termina en negro
            ],
            stops: [0.4, 1.0], // Controla dónde empieza a oscurecerse
          ),
        ),
        child: SafeArea(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(height: 60),
              
              // --- ZONA DEL LOGO ---
              // Por ahora puse un ícono de bicicleta de placeholder. 
              // Luego lo cambias por Image.asset('assets/logo.png')
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black12,
                      blurRadius: 10,
                      offset: Offset(0, 5),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.pedal_bike, 
                  size: 70, 
                  color: Colors.green, // Color representativo temporal
                ),
              ),
              const SizedBox(height: 30),

              // --- TÍTULO Y SUBTÍTULO ---
              const Text(
                'Bienvenido a BiciLab',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Plataforma integral de monitoreo\nen tiempo real',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.black54,
                ),
              ),
              const SizedBox(height: 40),

              // --- BOTÓN INICIAR SESIÓN ---
              ElevatedButton(
                onPressed: () {
                  Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const LoginScreen()),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black, // Fondo negro
                  foregroundColor: Colors.white, // Texto blanco
                  padding: const EdgeInsets.symmetric(horizontal: 50, vertical: 15),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                  elevation: 5,
                ),
                child: const Text(
                  'INICIAR SESION',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),

              // El Spacer empuja los siguientes elementos hasta abajo
              const Spacer(),

              // --- ZONA DE REGISTRO ---
              const Text(
                '¿Aun no eres parte de BiciLab?',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.white70, // Texto en blanco por el fondo oscuro
                ),
              ),
              const SizedBox(height: 15),
              ElevatedButton(
                onPressed: () {
                   Navigator.push(
                     context,
                      MaterialPageRoute(builder: (context) => const RegisterScreen()),
                );
              },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white, // Fondo blanco
                  foregroundColor: Colors.black, // Texto negro
                  padding: const EdgeInsets.symmetric(horizontal: 50, vertical: 15),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                ),
                child: const Text(
                  '¡REGISTRESE!',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 40), // Margen inferior
            ],
          ),
        ),
      ),
    );
  }
}