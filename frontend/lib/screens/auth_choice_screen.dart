import 'package:flutter/material.dart';
import '../routes.dart';

class AuthChoiceScreen extends StatefulWidget {
  const AuthChoiceScreen({super.key});

  @override
  State<AuthChoiceScreen> createState() => _AuthChoiceScreenState();
}

class _AuthChoiceScreenState extends State<AuthChoiceScreen> with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.08).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF090D16),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Container(
            color: const Color(0xFF0F172A),
            child: Stack(
              children: [
                // Background Glow Accents
                Positioned(
                  top: -80,
                  right: -80,
                  child: Container(
                    width: 280,
                    height: 280,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFF2563EB).withOpacity(0.15),
                    ),
                  ),
                ),
                Positioned(
                  bottom: -60,
                  left: -60,
                  child: Container(
                    width: 240,
                    height: 240,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFF38BDF8).withOpacity(0.1),
                    ),
                  ),
                ),

                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 28.0, vertical: 24.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Top Bar with Back Navigation to Fullscreen Welcome Image
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Container(
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.1),
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white.withOpacity(0.2)),
                              ),
                              child: IconButton(
                                icon: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 20),
                                onPressed: () => Navigator.pop(context),
                                tooltip: 'Back to Image View',
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: const Color(0xFF10B981).withOpacity(0.2),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: const Color(0xFF34D399).withOpacity(0.4)),
                              ),
                              child: Row(
                                children: const [
                                  Icon(Icons.shield_rounded, color: Color(0xFF34D399), size: 14),
                                  SizedBox(width: 6),
                                  Text(
                                    'SMART TERMINAL V2.0',
                                    style: TextStyle(
                                      color: Color(0xFF6EE7B7),
                                      fontSize: 10,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 1.0,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),

                        // Center Airport Brand & Biometric Identity
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ScaleTransition(
                              scale: _pulseAnimation,
                              child: Container(
                                padding: const EdgeInsets.all(24),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF2563EB).withOpacity(0.2),
                                  shape: BoxShape.circle,
                                  border: Border.all(color: const Color(0xFF3B82F6).withOpacity(0.6), width: 2),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFF2563EB).withOpacity(0.35),
                                      blurRadius: 30,
                                      offset: const Offset(0, 10),
                                    )
                                  ],
                                ),
                                child: const Icon(
                                  Icons.flight_takeoff_rounded,
                                  size: 60,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                            const SizedBox(height: 22),
                            const Text(
                              'AERO GATEWAY',
                              style: TextStyle(
                                fontSize: 26,
                                fontWeight: FontWeight.w900,
                                color: Colors.white,
                                letterSpacing: 3.5,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.08),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: Colors.white.withOpacity(0.15)),
                              ),
                              child: const Text(
                                'FACIAL CHECK-IN & BIOMETRIC GATEWAY',
                                style: TextStyle(
                                  color: Color(0xFF94A3B8),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 1.2,
                                ),
                              ),
                            ),
                          ],
                        ),

                        // Bottom Action Buttons (Register & Login)
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // 1. Register Button
                            ElevatedButton(
                              onPressed: () {
                                Navigator.pushNamed(context, AppRoutes.register);
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF2563EB),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 18),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                elevation: 6,
                                shadowColor: const Color(0xFF2563EB).withOpacity(0.5),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: const [
                                  Icon(Icons.person_add_alt_1_rounded, size: 22),
                                  SizedBox(width: 10),
                                  Text(
                                    'Register Passenger Profile',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 0.3,
                                    ),
                                  ),
                                  SizedBox(width: 6),
                                  Icon(Icons.arrow_forward_rounded, size: 18),
                                ],
                              ),
                            ),
                            const SizedBox(height: 14),

                            // 2. Login Button
                            OutlinedButton(
                              onPressed: () {
                                Navigator.pushNamed(context, AppRoutes.login);
                              },
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.white,
                                side: BorderSide(color: Colors.white.withOpacity(0.35), width: 1.5),
                                padding: const EdgeInsets.symmetric(vertical: 18),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                backgroundColor: Colors.white.withOpacity(0.06),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: const [
                                  Icon(Icons.login_rounded, size: 22),
                                  SizedBox(width: 10),
                                  Text(
                                    'Login to Passenger Portal',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 0.3,
                                    ),
                                  ),
                                  SizedBox(width: 6),
                                  Icon(Icons.arrow_forward_rounded, size: 18),
                                ],
                              ),
                            ),
                            const SizedBox(height: 24),

                            // Security Cert Footers
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                _buildSecurityBadge('ICAO 9303'),
                                const SizedBox(width: 8),
                                _buildSecurityBadge('AES-256 BIOMETRICS'),
                                const SizedBox(width: 8),
                                _buildSecurityBadge('IATA CERTIFIED'),
                              ],
                            ),
                            const SizedBox(height: 10),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSecurityBadge(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.white.withOpacity(0.12)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w800,
          color: Color(0xFF94A3B8),
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
