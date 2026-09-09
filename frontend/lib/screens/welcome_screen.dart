import 'package:flutter/material.dart';
import '../routes.dart';

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);
    
    _fadeAnimation = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  void _navigateToAuthChoice() {
    Navigator.pushNamed(context, AppRoutes.authChoice);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GestureDetector(
        onTap: _navigateToAuthChoice,
        behavior: HitTestBehavior.opaque,
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Color(0xFFF0F9FF),
                Color(0xFFE0F2FE),
                Color(0xFFBAE6FD),
              ],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
          child: Stack(
            children: [
              // ✈️ Floating Aviation Background Stickers / Icons (Decorative)
              Positioned(
                top: 80,
                left: 40,
                child: Icon(Icons.flight_rounded, color: Colors.blue.shade200.withOpacity(0.4), size: 40),
              ),
              Positioned(
                top: 150,
                right: 50,
                child: Icon(Icons.airplanemode_active_rounded, color: Colors.blue.shade300.withOpacity(0.3), size: 55),
              ),
              Positioned(
                bottom: 220,
                left: 30,
                child: Icon(Icons.flight_takeoff_rounded, color: Colors.blue.shade300.withOpacity(0.25), size: 45),
              ),
              Positioned(
                bottom: 120,
                right: 40,
                child: Icon(Icons.flight_rounded, color: Colors.blue.shade200.withOpacity(0.4), size: 50),
              ),

              // Main UI Content Layout
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32.0, vertical: 40.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // 1. Top Airport Branding Header
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0284C7).withOpacity(0.1),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.flight_rounded,
                              color: Color(0xFF0284C7),
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 10),
                          const Text(
                            'AIRPORT PASSENGER PORTAL',
                            style: TextStyle(
                              color: Color(0xFF0369A1),
                              fontSize: 12,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 2.5,
                            ),
                          ),
                        ],
                      ),

                      // 2. Center: Face Check-In & Airport Biometric Visual
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(32),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF0284C7).withOpacity(0.15),
                                  blurRadius: 35,
                                  spreadRadius: 10,
                                )
                              ],
                            ),
                            child: const Icon(
                              Icons.face_retouching_natural_rounded,
                              color: Color(0xFF0284C7),
                              size: 76,
                            ),
                          ),
                          const SizedBox(height: 32),
                          const Text(
                            'Face Check-In',
                            style: TextStyle(
                              color: Color(0xFF0F172A),
                              fontSize: 34,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.5,
                            ),
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'Seamless, touchless, and secure biometric\nclearance for your flight.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Color(0xFF475569),
                              fontSize: 15,
                              height: 1.5,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),

                      // 3. Bottom Clean Call-to-Action Button
                      FadeTransition(
                        opacity: _fadeAnimation,
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 18),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0284C7),
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF0284C7).withOpacity(0.3),
                                blurRadius: 20,
                                offset: const Offset(0, 8),
                              )
                            ],
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: const [
                              Text(
                                'TAP ANYWHERE TO START',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1.5,
                                ),
                              ),
                              SizedBox(width: 10),
                              Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 20),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}