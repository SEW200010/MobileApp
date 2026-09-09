import 'package:flutter/material.dart';
import '../routes.dart';

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1500),
    )..repeat(reverse: true);
    _fadeAnimation = Tween<double>(begin: 0.5, end: 1.0).animate(
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
      backgroundColor: const Color(0xFF090D16),
      body: GestureDetector(
        onTap: _navigateToAuthChoice,
        behavior: HitTestBehavior.opaque,
        child: Stack(
          children: [
            // Full Screen Background Aviation Image
            Positioned.fill(
              child: Image.network(
                'https://images.unsplash.com/photo-1542296332-2e4473faf563?q=80&w=1600&auto=format&fit=crop',
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xFF0B132B), Color(0xFF1C2541), Color(0xFF1E40AF)],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                    child: const Center(
                      child: Icon(Icons.flight_takeoff_rounded, size: 120, color: Colors.white12),
                    ),
                  );
                },
              ),
            ),

            // Ultra-Subtle Vignette Gradient Overlay (keeps image vibrant)
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.black.withOpacity(0.4),
                      Colors.transparent,
                      Colors.black.withOpacity(0.65),
                    ],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
              ),
            ),

            // Pure Minimalist Overlay Content (Logo & Tap Anywhere Prompt)
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 32.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Top Subtle Brand Pill
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.4),
                            borderRadius: BorderRadius.circular(30),
                            border: Border.all(color: Colors.white.withOpacity(0.2)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: const [
                              Icon(Icons.flight_takeoff_rounded, color: Colors.white, size: 16),
                              SizedBox(width: 8),
                              Text(
                                'AERO GATEWAY • SMART AIRPORT',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    // Bottom Floating Glassmorphic Prompt ("Tap anywhere to continue")
                    FadeTransition(
                      opacity: _fadeAnimation,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.55),
                          borderRadius: BorderRadius.circular(30),
                          border: Border.all(color: Colors.white.withOpacity(0.3), width: 1.2),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.3),
                              blurRadius: 16,
                              offset: const Offset(0, 6),
                            )
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: const [
                            Text(
                              'TAP ANYWHERE TO CONTINUE',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 2.0,
                              ),
                            ),
                            SizedBox(width: 10),
                            Icon(Icons.touch_app_rounded, color: Color(0xFF38BDF8), size: 20),
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
    );
  }
}