import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../routes.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _identifierController = TextEditingController();
  int _selectedTab = 0; // 0: Passport Number, 1: Phone Number
  bool _isLoading = false;

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.12).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _identifierController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin([String? customIdentifier]) async {
    final identifier = customIdentifier ?? _identifierController.text.trim();

    if (customIdentifier == null && !_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
    });

    final result = await ApiService.sendOtp(identifier, isRegistration: false);

    if (!mounted) return;

    setState(() {
      _isLoading = false;
    });

    if (result['status'] == 'success') {
      Navigator.pushNamed(
        context,
        AppRoutes.otp,
        arguments: {
          'identifier': identifier,
          'mockOtp': result['otp'],
          'isRegistration': false,
        },
      );
    } else {
      _showErrorSnackBar(result['message'] ?? 'Authentication failed. Please verify your details or register as a new passenger.');
    }
  }

  void _showErrorSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline_rounded, color: Colors.white, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFFEF4444),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }

  void _openFaceScanModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              height: MediaQuery.of(context).size.height * 0.65,
              decoration: const BoxDecoration(
                color: Color(0xFF0F172A),
                borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
                border: Border(top: BorderSide(color: Color(0xFF0284C7), width: 1.5)),
              ),
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Container(
                    width: 44,
                    height: 5,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Biometric Gate Scan',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Align face inside scanner frame for automated check-in',
                    style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                  ),
                  const SizedBox(height: 32),
                  Expanded(
                    child: Center(
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          ScaleTransition(
                            scale: _pulseAnimation,
                            child: Container(
                              width: 180,
                              height: 180,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: const Color(0xFF0284C7).withOpacity(0.15),
                                border: Border.all(color: const Color(0xFF38BDF8), width: 2),
                              ),
                            ),
                          ),
                          Container(
                            width: 140,
                            height: 140,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: const Color(0xFF1E293B),
                              border: Border.all(color: const Color(0xFF60A5FA).withOpacity(0.5), width: 1.5),
                            ),
                            child: const Icon(
                              Icons.face_retouching_natural_rounded,
                              size: 72,
                              color: Color(0xFF38BDF8),
                            ),
                          ),
                          Positioned(
                            bottom: 10,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                              decoration: BoxDecoration(
                                color: const Color(0xFF10B981).withOpacity(0.2),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: const Color(0xFF10B981).withOpacity(0.6)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: const [
                                  Icon(Icons.center_focus_strong, color: Color(0xFF34D399), size: 14),
                                  SizedBox(width: 6),
                                  Text(
                                    'SCANNER ACTIVE',
                                    style: TextStyle(
                                      color: Color(0xFF34D399),
                                      fontSize: 10,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 1.0,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context);
                      if (_identifierController.text.trim().isNotEmpty) {
                        _handleLogin();
                      } else {
                        _handleLogin('N92837461');
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0284C7),
                      foregroundColor: Colors.white,
                      minimumSize: const Size(double.infinity, 52),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      elevation: 4,
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.verified_rounded, size: 20),
                        SizedBox(width: 8),
                        Text(
                          'Confirm Biometric Match',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text(
                      'Cancel & Use Passport Number',
                      style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
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
              // ✈️ Background Aviation Stickers (Decorative only)
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

              // SAFE AREA & FLEXIBLE LAYOUT (Back button is 100% fixed here)
              SafeArea(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 480),
                    child: Column(
                      children: [
                        // 1. FIXED TOP APP BAR / NAVIGATION ROW (Will never dislocate)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 8.0),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Container(
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.7),
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.blue.shade100),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFF0284C7).withOpacity(0.1),
                                      blurRadius: 10,
                                    )
                                  ],
                                ),
                                child: IconButton(
                                  icon: const Icon(Icons.arrow_back_rounded, color: Color(0xFF0284C7), size: 20),
                                  onPressed: () => Navigator.pop(context),
                                  tooltip: 'Back to Welcome',
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF10B981).withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(color: const Color(0xFF34D399).withOpacity(0.4)),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                 
                                ),
                              ),
                            ],
                          ),
                        ),

                        // 2. SCROLLABLE CONTENT (Form and Header)
                        Expanded(
                          child: SingleChildScrollView(
                            physics: const BouncingScrollPhysics(),
                            padding: const EdgeInsets.symmetric(horizontal: 22.0, vertical: 10.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                // Header Biometric Icon & Title
                                Center(
                                  child: Column(
                                    children: [
                                      ScaleTransition(
                                        scale: _pulseAnimation,
                                        child: Container(
                                          padding: const EdgeInsets.all(18),
                                          decoration: BoxDecoration(
                                            color: Colors.white,
                                            shape: BoxShape.circle,
                                            boxShadow: [
                                              BoxShadow(
                                                color: const Color(0xFF0284C7).withOpacity(0.2),
                                                blurRadius: 25,
                                                spreadRadius: 5,
                                              )
                                            ],
                                          ),
                                          child: const Icon(
                                            Icons.fingerprint_rounded,
                                            color: Color(0xFF0284C7),
                                            size: 42,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 14),
                                      const Text(
                                        'Passenger Authentication',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          fontSize: 26,
                                          fontWeight: FontWeight.w900,
                                          color: Color(0xFF0F172A),
                                          letterSpacing: -0.5,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      const Text(
                                        'Verify travel details to retrieve electronic boarding pass',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          color: Color(0xFF475569),
                                          fontSize: 13,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 24),

                                // Floating Form Container Card
                                Form(
                                  key: _formKey,
                                  child: Container(
                                    padding: const EdgeInsets.all(24),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(30),
                                      border: Border.all(color: const Color(0xFFE2E8F0), width: 1),
                                      boxShadow: [
                                        BoxShadow(
                                          color: const Color(0xFF0284C7).withOpacity(0.12),
                                          blurRadius: 35,
                                          offset: const Offset(0, 12),
                                        )
                                      ],
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.stretch,
                                      children: [
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: const [
                                            Text(
                                              'AUTHENTICATION METHOD',
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w800,
                                                color: Color(0xFF64748B),
                                                letterSpacing: 1.1,
                                              ),
                                            ),
                                            Icon(Icons.tune_rounded, size: 16, color: Color(0xFF94A3B8)),
                                          ],
                                        ),
                                        const SizedBox(height: 12),

                                        // Tab Toggle Segment
                                        Container(
                                          padding: const EdgeInsets.all(4),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFF1F5F9),
                                            borderRadius: BorderRadius.circular(16),
                                          ),
                                          child: Row(
                                            children: [
                                              Expanded(
                                                child: GestureDetector(
                                                  onTap: () {
                                                    setState(() {
                                                      _selectedTab = 0;
                                                    });
                                                  },
                                                  child: AnimatedContainer(
                                                    duration: const Duration(milliseconds: 200),
                                                    padding: const EdgeInsets.symmetric(vertical: 12),
                                                    decoration: BoxDecoration(
                                                      color: _selectedTab == 0 ? Colors.white : Colors.transparent,
                                                      borderRadius: BorderRadius.circular(12),
                                                      boxShadow: _selectedTab == 0
                                                          ? [
                                                              BoxShadow(
                                                                color: const Color(0xFF0F172A).withOpacity(0.08),
                                                                blurRadius: 8,
                                                                offset: const Offset(0, 3),
                                                              )
                                                            ]
                                                          : [],
                                                    ),
                                                    child: Row(
                                                      mainAxisAlignment: MainAxisAlignment.center,
                                                      children: [
                                                        Icon(
                                                          Icons.badge_outlined,
                                                          size: 18,
                                                          color: _selectedTab == 0 ? const Color(0xFF0284C7) : const Color(0xFF64748B),
                                                        ),
                                                        const SizedBox(width: 8),
                                                        Text(
                                                          'Passport ',
                                                          style: TextStyle(
                                                            fontSize: 13,
                                                            fontWeight: FontWeight.w800,
                                                            color: _selectedTab == 0 ? const Color(0xFF0F172A) : const Color(0xFF64748B),
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                              ),
                                              Expanded(
                                                child: GestureDetector(
                                                  onTap: () {
                                                    setState(() {
                                                      _selectedTab = 1;
                                                    });
                                                  },
                                                  child: AnimatedContainer(
                                                    duration: const Duration(milliseconds: 200),
                                                    padding: const EdgeInsets.symmetric(vertical: 12),
                                                    decoration: BoxDecoration(
                                                      color: _selectedTab == 1 ? Colors.white : Colors.transparent,
                                                      borderRadius: BorderRadius.circular(12),
                                                      boxShadow: _selectedTab == 1
                                                          ? [
                                                              BoxShadow(
                                                                color: const Color(0xFF0F172A).withOpacity(0.08),
                                                                blurRadius: 8,
                                                                offset: const Offset(0, 3),
                                                              )
                                                            ]
                                                          : [],
                                                    ),
                                                    child: Row(
                                                      mainAxisAlignment: MainAxisAlignment.center,
                                                      children: [
                                                        Icon(
                                                          Icons.phone_iphone_rounded,
                                                          size: 18,
                                                          color: _selectedTab == 1 ? const Color(0xFF0284C7) : const Color(0xFF64748B),
                                                        ),
                                                        const SizedBox(width: 8),
                                                        Text(
                                                          'Phone ',
                                                          style: TextStyle(
                                                            fontSize: 13,
                                                            fontWeight: FontWeight.w800,
                                                            color: _selectedTab == 1 ? const Color(0xFF0F172A) : const Color(0xFF64748B),
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(height: 22),

                                        // Input Field Label
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            Text(
                                              _selectedTab == 0 ? 'Passport ID' : 'Mobile Number',
                                              style: const TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w700,
                                                color: Color(0xFF334155),
                                              ),
                                            ),
                                            Text(
                                              _selectedTab == 0 ? 'ICAO 9303' : 'SMS OTP Ready',
                                              style: const TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w600,
                                                color: Color(0xFF0284C7),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 8),

                                        // Input Text Box
                                        TextFormField(
                                          controller: _identifierController,
                                          style: const TextStyle(
                                            color: Color(0xFF0F172A),
                                            fontSize: 16,
                                            fontWeight: FontWeight.w800,
                                            letterSpacing: 0.8,
                                          ),
                                          keyboardType: _selectedTab == 1 ? TextInputType.phone : TextInputType.text,
                                          textCapitalization: TextCapitalization.characters,
                                          decoration: InputDecoration(
                                            hintText: _selectedTab == 0 ? 'e.g. N92837461' : 'e.g. +94771234567',
                                            hintStyle: TextStyle(
                                              color: Colors.grey.shade400,
                                              fontSize: 14,
                                              fontWeight: FontWeight.normal,
                                            ),
                                            prefixIcon: Container(
                                              margin: const EdgeInsets.all(8),
                                              padding: const EdgeInsets.all(8),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFFEFF6FF),
                                                borderRadius: BorderRadius.circular(10),
                                              ),
                                              child: Icon(
                                                _selectedTab == 0 ? Icons.flight_rounded : Icons.phone_android_rounded,
                                                color: const Color(0xFF0284C7),
                                                size: 20,
                                              ),
                                            ),
                                            suffixIcon: _identifierController.text.isNotEmpty
                                                ? IconButton(
                                                    icon: const Icon(Icons.cancel_rounded, size: 20, color: Color(0xFF94A3B8)),
                                                    onPressed: () {
                                                      setState(() {
                                                        _identifierController.clear();
                                                      });
                                                    },
                                                  )
                                                : null,
                                            filled: true,
                                            fillColor: const Color(0xFFF8FAFC),
                                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                                            border: OutlineInputBorder(
                                              borderRadius: BorderRadius.circular(16),
                                              borderSide: const BorderSide(color: Color(0xFFCBD5E1), width: 1),
                                            ),
                                            enabledBorder: OutlineInputBorder(
                                              borderRadius: BorderRadius.circular(16),
                                              borderSide: const BorderSide(color: Color(0xFFE2E8F0), width: 1.2),
                                            ),
                                            focusedBorder: OutlineInputBorder(
                                              borderRadius: BorderRadius.circular(16),
                                              borderSide: const BorderSide(color: Color(0xFF0284C7), width: 2),
                                            ),
                                          ),
                                          onChanged: (_) => setState(() {}),
                                          validator: (value) {
                                            if (value == null || value.trim().isEmpty) {
                                              return _selectedTab == 0
                                                  ? 'Please enter your passport number'
                                                  : 'Please enter your phone number';
                                            }
                                            if (_selectedTab == 0 && value.trim().length < 4) {
                                              return 'Passport number must be at least 4 characters';
                                            }
                                            return null;
                                          },
                                        ),
                                        const SizedBox(height: 20),

                                        const SizedBox(height: 24),

                                        // Submit Button
                                        ElevatedButton(
                                          onPressed: _isLoading ? null : () => _handleLogin(),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: const Color(0xFF0284C7),
                                            foregroundColor: Colors.white,
                                            padding: const EdgeInsets.symmetric(vertical: 18),
                                            shape: RoundedRectangleBorder(
                                              borderRadius: BorderRadius.circular(16),
                                            ),
                                            elevation: 5,
                                            shadowColor: const Color(0xFF0284C7).withOpacity(0.4),
                                          ),
                                          child: _isLoading
                                              ? const SizedBox(
                                                  height: 22,
                                                  width: 22,
                                                  child: CircularProgressIndicator(
                                                    strokeWidth: 2.5,
                                                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                                  ),
                                                )
                                              : Row(
                                                  mainAxisAlignment: MainAxisAlignment.center,
                                                  children: const [
                                                    Icon(Icons.security_rounded, size: 20),
                                                    SizedBox(width: 10),
                                                    Text(
                                                      'Verify & Send Security OTP',
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
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 20),

                                // Register Redirection Banner Container
                                Container(
                                  padding: const EdgeInsets.all(18),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(color: const Color(0xFFE2E8F0)),
                                    boxShadow: [
                                      BoxShadow(
                                        color: const Color(0xFF0284C7).withOpacity(0.06),
                                        blurRadius: 20,
                                        offset: const Offset(0, 6),
                                      )
                                    ],
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(10),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFEFF6FF),
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        child: const Icon(
                                          Icons.person_add_alt_1_rounded,
                                          color: Color(0xFF0284C7),
                                          size: 22,
                                        ),
                                      ),
                                      const SizedBox(width: 14),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: const [
                                            Text(
                                              'First Time Traveling?',
                                              style: TextStyle(
                                                fontSize: 14,
                                                fontWeight: FontWeight.w800,
                                                color: Color(0xFF0F172A),
                                              ),
                                            ),
                                            SizedBox(height: 2),
                                            Text(
                                              'Create your digital face profile',
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: Color(0xFF64748B),
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      ElevatedButton(
                                        onPressed: () {
                                          Navigator.pushNamed(context, AppRoutes.register);
                                        },
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: const Color(0xFFF1F5F9),
                                          foregroundColor: const Color(0xFF0284C7),
                                          elevation: 0,
                                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                        ),
                                        child: const Text(
                                          'Register',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w800,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 28)
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSecurityBadge(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.7),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFFCBD5E1)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w800,
          color: Color(0xFF475569),
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}