import 'dart:io';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import '../services/api_service.dart';
import '../routes.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _flightController = TextEditingController();
  final _passportController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();

  XFile? _selectedImage;
  bool _isLoading = false;

  final ImagePicker _picker = ImagePicker();

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.10).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _flightController.dispose();
    _passportController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? image = await _picker.pickImage(
        source: source,
        imageQuality: 85,
        maxWidth: 1000,
      );
      if (image != null) {
        setState(() {
          _selectedImage = image;
        });
      }
    } catch (e) {
      if (mounted) {
        _showErrorSnackBar('Failed to select image: $e');
      }
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

  void _showImageSourceBottomSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          decoration: const BoxDecoration(
            color: Color(0xFF0F172A),
            borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
            border: Border(top: BorderSide(color: Color(0xFF0284C7), width: 1.5)),
          ),
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 5,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const Text(
                'Facial Biometric Enrolment',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Select camera capture or official passport photo from gallery',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: Color(0xFF94A3B8),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: () {
                        Navigator.pop(context);
                        _pickImage(ImageSource.camera);
                      },
                      borderRadius: BorderRadius.circular(18),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 22),
                        decoration: BoxDecoration(
                          border: Border.all(color: const Color(0xFF0284C7).withOpacity(0.4)),
                          borderRadius: BorderRadius.circular(18),
                          color: const Color(0xFF1E293B),
                        ),
                        child: Column(
                          children: const [
                            Icon(Icons.camera_alt_rounded, size: 38, color: Color(0xFF38BDF8)),
                            SizedBox(height: 10),
                            Text(
                              'Use Camera',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: InkWell(
                      onTap: () {
                        Navigator.pop(context);
                        _pickImage(ImageSource.gallery);
                      },
                      borderRadius: BorderRadius.circular(18),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 22),
                        decoration: BoxDecoration(
                          border: Border.all(color: const Color(0xFF0284C7).withOpacity(0.4)),
                          borderRadius: BorderRadius.circular(18),
                          color: const Color(0xFF1E293B),
                        ),
                        child: Column(
                          children: const [
                            Icon(Icons.photo_library_rounded, size: 38, color: Color(0xFF38BDF8)),
                            SizedBox(height: 10),
                            Text(
                              'From Gallery',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text(
                  'Cancel',
                  style: TextStyle(
                    fontSize: 14,
                    color: Color(0xFF94A3B8),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _submitForm() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (_selectedImage == null) {
      _showErrorSnackBar('Biometric face photo is required for touchless airport access.');
      return;
    }

    setState(() {
      _isLoading = true;
    });

    final phoneNumber = _phoneController.text.trim();
    final result = await ApiService.sendOtp(phoneNumber, isRegistration: true);

    if (!mounted) return;

    setState(() {
      _isLoading = false;
    });

    if (result['status'] == 'success') {
      Navigator.pushNamed(
        context,
        AppRoutes.otp,
        arguments: {
          'identifier': phoneNumber,
          'mockOtp': result['otp'],
          'isRegistration': true,
          'registrationData': {
            'full_name': _nameController.text.trim(),
            'flight_number': _flightController.text.trim().toUpperCase(),
            'passport_number': _passportController.text.trim().toUpperCase(),
            'email': _emailController.text.trim(),
            'phone_number': phoneNumber,
            'face_image': _selectedImage,
          }
        },
      );
    } else {
      _showErrorSnackBar(result['message'] ?? 'Failed to send verification code. Please check details.');
    }
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
              // ✈️ Floating Aviation Background Stickers
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

              SafeArea(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 480),
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.symmetric(horizontal: 22.0, vertical: 20.0),
                      child: Column(
                        children: [
                          // Top Navigation Row
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Container(
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.6),
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
                            ],
                          ),
                          const SizedBox(height: 16),

                          // Header Icon & Title
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
                                      Icons.person_add_alt_1_rounded,
                                      color: Color(0xFF0284C7),
                                      size: 42,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 14),
                                const Text(
                                  'Passenger Registration',
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
                                  'Create your biometric profile for touchless airport check-in',
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

                          // Form Container Card
                          Form(
                            key: _formKey,
                            child: Column(
                              children: [
                                // 1. Facial Biometric Capture Section
                                Container(
                                  padding: const EdgeInsets.all(22),
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
                                        children: [
                                          Row(
                                            children: const [
                                              Icon(Icons.face_retouching_natural_rounded, color: Color(0xFF0284C7), size: 20),
                                              SizedBox(width: 8),
                                              Text(
                                                'FACIAL BIOMETRICS',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w800,
                                                  color: Color(0xFF334155),
                                                  letterSpacing: 1.0,
                                                ),
                                              ),
                                            ],
                                          ),
                                          if (_selectedImage != null)
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFFF0FDF4),
                                                borderRadius: BorderRadius.circular(20),
                                                border: Border.all(color: const Color(0xFF86EFAC)),
                                              ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: const [
                                                  Icon(Icons.check_circle_rounded, color: Color(0xFF16A34A), size: 14),
                                                  SizedBox(width: 4),
                                                  Text(
                                                    'FACE ENROLLED',
                                                    style: TextStyle(
                                                      fontSize: 10,
                                                      fontWeight: FontWeight.w800,
                                                      color: Color(0xFF15803D),
                                                      letterSpacing: 0.5,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                        ],
                                      ),
                                      const SizedBox(height: 16),

                                      // Camera Frame Box
                                      InkWell(
                                        onTap: _showImageSourceBottomSheet,
                                        borderRadius: BorderRadius.circular(20),
                                        child: Container(
                                          height: 200,
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFF8FAFC),
                                            borderRadius: BorderRadius.circular(20),
                                            border: Border.all(
                                              color: _selectedImage != null ? const Color(0xFF22C55E) : const Color(0xFF93C5FD),
                                              width: 1.8,
                                            ),
                                          ),
                                          child: ClipRRect(
                                            borderRadius: BorderRadius.circular(18),
                                            child: Stack(
                                              fit: StackFit.expand,
                                              children: [
                                                if (_selectedImage != null)
                                                  kIsWeb
                                                      ? Image.network(
                                                          _selectedImage!.path,
                                                          fit: BoxFit.cover,
                                                          errorBuilder: (context, error, stackTrace) {
                                                            return const Icon(Icons.person, size: 50, color: Colors.grey);
                                                          },
                                                        )
                                                      : Image.file(File(_selectedImage!.path), fit: BoxFit.cover)
                                                else
                                                  Column(
                                                    mainAxisAlignment: MainAxisAlignment.center,
                                                    children: [
                                                      Container(
                                                        padding: const EdgeInsets.all(16),
                                                        decoration: BoxDecoration(
                                                          color: const Color(0xFFEFF6FF),
                                                          shape: BoxShape.circle,
                                                          border: Border.all(color: const Color(0xFFBFDBFE)),
                                                          boxShadow: [
                                                            BoxShadow(
                                                              color: const Color(0xFF0284C7).withOpacity(0.12),
                                                              blurRadius: 12,
                                                              offset: const Offset(0, 4),
                                                            )
                                                          ],
                                                        ),
                                                        child: const Icon(Icons.camera_enhance_rounded, size: 36, color: Color(0xFF0284C7)),
                                                      ),
                                                      const SizedBox(height: 12),
                                                      const Text(
                                                        'Tap to Capture Biometric Photo',
                                                        style: TextStyle(
                                                          fontSize: 14,
                                                          fontWeight: FontWeight.w800,
                                                          color: Color(0xFF0F172A),
                                                        ),
                                                      ),
                                                      const SizedBox(height: 4),
                                                    
                                                    ],
                                                  ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 16),
                                      Wrap(
                                        spacing: 8.0,
                                        runSpacing: 8.0,
                                        alignment: WrapAlignment.center,
                                        children: [
                                          _buildGuidanceLabel(Icons.wb_sunny_outlined, 'Good Lighting'),
                                          _buildGuidanceLabel(Icons.visibility_rounded, 'No Sunglasses'),
                                          _buildGuidanceLabel(Icons.sentiment_neutral_outlined, 'Front Face'),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 20),

                                // 2. Passenger Identification Details Card
                                Container(
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
                                        children: const [
                                          Icon(Icons.badge_outlined, color: Color(0xFF0284C7), size: 20),
                                          SizedBox(width: 8),
                                          Text(
                                            'TRAVEL DETAILS',
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w800,
                                              color: Color(0xFF334155),
                                              letterSpacing: 1.0,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 20),

                                      // Full Name
                                      _buildTextField(
                                        controller: _nameController,
                                        labelText: 'Full Name (as in Passport)',
                                        hintText: 'e.g. ALEXANDER BENJAMIN',
                                        icon: Icons.person_outline_rounded,
                                        textCapitalization: TextCapitalization.words,
                                        maxLength: 255,
                                        inputFormatters: [
                                          LengthLimitingTextInputFormatter(255),
                                        ],
                                        validator: (value) {
                                          if (value == null || value.trim().isEmpty) {
                                            return 'Full name is required';
                                          }
                                          if (value.trim().length < 2) {
                                            return 'Name must be at least 2 characters long';
                                          }
                                          return null;
                                        },
                                      ),
                                      const SizedBox(height: 16),

                                      // Flight Number
                                      _buildTextField(
                                        controller: _flightController,
                                        labelText: 'Flight Number',
                                        hintText: 'e.g. UL503 or BA120',
                                        icon: Icons.flight_takeoff_rounded,
                                        textCapitalization: TextCapitalization.characters,
                                        maxLength: 50,
                                        inputFormatters: [
                                          LengthLimitingTextInputFormatter(50),
                                          FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9\s-]')),
                                        ],
                                        validator: (value) {
                                          if (value == null || value.trim().isEmpty) {
                                            return 'Flight number is required';
                                          }
                                          if (value.trim().length < 2) {
                                            return 'Enter a valid flight number';
                                          }
                                          return null;
                                        },
                                      ),
                                      const SizedBox(height: 16),

                                      // Passport Number
                                      _buildTextField(
                                        controller: _passportController,
                                        labelText: 'Passport ID',
                                        hintText: 'e.g. N92837461',
                                        icon: Icons.vpn_key_outlined,
                                        textCapitalization: TextCapitalization.characters,
                                        maxLength: 50,
                                        inputFormatters: [
                                          LengthLimitingTextInputFormatter(50),
                                          FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9]')),
                                        ],
                                        validator: (value) {
                                          if (value == null || value.trim().isEmpty) {
                                            return 'Passport number is required';
                                          }
                                          if (value.trim().length < 4) {
                                            return 'Passport number is too short';
                                          }
                                          return null;
                                        },
                                      ),
                                      const SizedBox(height: 16),

                                      // Email Address
                                      _buildTextField(
                                        controller: _emailController,
                                        labelText: 'Email Address',
                                        hintText: 'e.g. passenger@airports.com',
                                        icon: Icons.email_outlined,
                                        keyboardType: TextInputType.emailAddress,
                                        maxLength: 255,
                                        inputFormatters: [
                                          LengthLimitingTextInputFormatter(255),
                                        ],
                                        validator: (value) {
                                          if (value == null || value.trim().isEmpty) {
                                            return 'Email address is required';
                                          }
                                          final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
                                          if (!emailRegex.hasMatch(value.trim())) {
                                            return 'Enter a valid email address';
                                          }
                                          return null;
                                        },
                                      ),
                                      const SizedBox(height: 16),

                                      // Phone Number
                                      _buildTextField(
                                        controller: _phoneController,
                                        labelText: 'Mobile Phone Number',
                                        hintText: 'e.g. +94771234567',
                                        icon: Icons.phone_android_rounded,
                                        keyboardType: TextInputType.phone,
                                        maxLength: 12,
                                        inputFormatters: [
                                          LengthLimitingTextInputFormatter(12),
                                          FilteringTextInputFormatter.allow(RegExp(r'[0-9\+]')),
                                        ],
                                        validator: (value) {
                                          if (value == null || value.trim().isEmpty) {
                                            return 'Phone number is required';
                                          }
                                          final phoneRegExp = RegExp(r'^\+94\d{9}$');
                                          if (!phoneRegExp.hasMatch(value.trim())) {
                                            return 'Format must be: +94771234567';
                                          }
                                          return null;
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 24),

                                // Submit Registration CTA Button
                                ElevatedButton(
                                  onPressed: _isLoading ? null : _submitForm,
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
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: const [
                                      Icon(Icons.fingerprint_rounded, size: 22),
                                      SizedBox(width: 10),
                                      Text(
                                        'Enrol Profile & Continue OTP',
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
                                const SizedBox(height: 28),

                               
                                const SizedBox(height: 32),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              // Glassmorphic Loading Blur Overlay (Fixed & Clean)
              if (_isLoading)
                Positioned.fill(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
                    child: Container(
                      color: Colors.black.withOpacity(0.45),
                      child: Center(
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 40),
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(28),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.15),
                                blurRadius: 30,
                                offset: const Offset(0, 10),
                              )
                            ],
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const SizedBox(
                                width: 60,
                                height: 60,
                                child: CircularProgressIndicator(
                                  strokeWidth: 3.5,
                                  color: Color(0xFF0284C7),
                                  backgroundColor: Color(0xFFEFF6FF),
                                ),
                              ),
                              const SizedBox(height: 24),
                              const Text(
                                'Encrypting Facial Profile',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF0F172A),
                                ),
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'Generating facial signature and securing credentials...',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF64748B),
                                  height: 1.4,
                                ),
                              ),
                            ],
                          ),
                        ),
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

  Widget _buildTextField({
    required TextEditingController controller,
    required String labelText,
    required String hintText,
    required IconData icon,
    TextCapitalization textCapitalization = TextCapitalization.none,
    TextInputType keyboardType = TextInputType.text,
    int? maxLength,
    List<TextInputFormatter>? inputFormatters,
    required String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      textCapitalization: textCapitalization,
      keyboardType: keyboardType,
      maxLength: maxLength,
      inputFormatters: inputFormatters,
      validator: validator,
      style: const TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w800,
        color: Color(0xFF0F172A),
      ),
      decoration: InputDecoration(
        labelText: labelText,
        counterText: '',
        labelStyle: const TextStyle(
          color: Color(0xFF64748B),
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
        floatingLabelStyle: const TextStyle(
          color: Color(0xFF0284C7),
          fontWeight: FontWeight.w800,
        ),
        hintText: hintText,
        hintStyle: TextStyle(
          color: Colors.grey.shade400,
          fontSize: 13,
          fontWeight: FontWeight.normal,
        ),
        prefixIcon: Container(
          margin: const EdgeInsets.all(8),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0xFFEFF6FF),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: const Color(0xFF0284C7), size: 18),
        ),
        filled: true,
        fillColor: const Color(0xFFF8FAFC),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFFE2E8F0), width: 1.2),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFFE2E8F0), width: 1.2),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFF0284C7), width: 2.0),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFFEF4444), width: 1.5),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFFEF4444), width: 2.0),
        ),
        errorStyle: const TextStyle(
          color: Color(0xFFEF4444),
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildGuidanceLabel(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFBFDBFE)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: const Color(0xFF0284C7)),
          const SizedBox(width: 4),
          Text(
            text,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: Color(0xFF0369A1),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSecurityBadge(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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