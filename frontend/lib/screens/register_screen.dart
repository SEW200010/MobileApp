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

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _flightController = TextEditingController();
  final _passportController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();

  XFile? _selectedImage;
  bool _isLoading = false;

  final ImagePicker _picker = ImagePicker();

  @override
  void dispose() {
    _nameController.dispose();
    _flightController.dispose();
    _passportController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to pick image: $e'),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    }
  }

  void _showImageSourceBottomSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const Text(
                'Biometric Verification Photo',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Choose a capture method. Ensure your face is clearly visible with good lighting.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey.shade600,
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
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 20),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.blue.shade100),
                          borderRadius: BorderRadius.circular(16),
                          color: Colors.blue.shade50.withOpacity(0.5),
                        ),
                        child: Column(
                          children: [
                            Icon(Icons.camera_alt_rounded, size: 36, color: Colors.blue.shade700),
                            const SizedBox(height: 8),
                            Text(
                              'Use Camera',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.blue.shade900,
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
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 20),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.blue.shade100),
                          borderRadius: BorderRadius.circular(16),
                          color: Colors.blue.shade50.withOpacity(0.5),
                        ),
                        child: Column(
                          children: [
                            Icon(Icons.photo_library_rounded, size: 36, color: Colors.blue.shade700),
                            const SizedBox(height: 8),
                            Text(
                              'From Gallery',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.blue.shade900,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(
                  'Cancel',
                  style: TextStyle(
                    fontSize: 15,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.bold,
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: const [
              Icon(Icons.error_outline, color: Colors.white),
              SizedBox(width: 12),
              Expanded(
                child: Text('Biometric photo is required. Please capture/upload your face photo.'),
              ),
            ],
          ),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    final phoneNumber = _phoneController.text.trim();
    final result = await ApiService.sendOtp(phoneNumber, isRegistration: true);

    setState(() {
      _isLoading = false;
    });

    if (mounted) {
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.white),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(result['message'] ?? 'Failed to send OTP code'),
                ),
              ],
            ),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: Container(
          margin: const EdgeInsets.only(left: 16, top: 8, bottom: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.blue.withOpacity(0.08),
                blurRadius: 8,
                offset: const Offset(0, 2),
              )
            ],
            border: Border.all(color: Colors.blue.shade100),
          ),
          child: IconButton(
            icon: const Icon(Icons.arrow_back, color: Color(0xFF0F172A), size: 20),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        title: const Text(
          'Register Profile',
          style: TextStyle(
            color: Color(0xFF0F172A),
            fontWeight: FontWeight.w800,
            fontSize: 24,
          ),
        ),
        centerTitle: true,
      ),
      body: Stack(
        children: [
          Positioned(
            top: -80,
            right: -80,
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.blue.shade100.withOpacity(0.6),
              ),
            ),
          ),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 6),
                    Text(
                      'Fill in your boarding details and capture a facial profile to authorize touchless access.',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey.shade600,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Biometrics Capture Card
                    Container(
                      padding: const EdgeInsets.all(22),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.blue.shade100, width: 1),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.blue.withOpacity(0.04),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          )
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              // Expanded + Flexible: the title gives way to the
                              // "Captured" badge instead of overflowing once
                              // the badge appears on a narrow screen.
                              Expanded(
                                child: Row(
                                  children: [
                                    Icon(Icons.face_retouching_natural_rounded, color: Colors.blue.shade700, size: 22),
                                    const SizedBox(width: 10),
                                    const Flexible(
                                      child: Text(
                                        'Facial Biometric Scan',
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                          color: Color(0xFF0F172A),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (_selectedImage != null)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.green.shade50,
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(color: Colors.green.shade200),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.check_circle_rounded, color: Colors.green, size: 14),
                                      const SizedBox(width: 4),
                                      Text(
                                        'Captured',
                                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.green.shade700),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          InkWell(
                            onTap: _showImageSourceBottomSheet,
                            borderRadius: BorderRadius.circular(16),
                            child: Container(
                              height: 180,
                              decoration: BoxDecoration(
                                color: Colors.blue.shade50.withOpacity(0.3),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: _selectedImage != null ? Colors.green.shade400 : Colors.blue.shade200,
                                  width: 1.5,
                                ),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(15),
                                child: _selectedImage != null
                                    ? Stack(
                                        fit: StackFit.expand,
                                        children: [
                                          kIsWeb
                                              ? Image.network(_selectedImage!.path, fit: BoxFit.cover)
                                              : Image.file(File(_selectedImage!.path), fit: BoxFit.cover),
                                          Positioned(
                                            bottom: 12,
                                            right: 12,
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                              decoration: BoxDecoration(
                                                color: Colors.black.withOpacity(0.6),
                                                borderRadius: BorderRadius.circular(20),
                                              ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: const [
                                                  Icon(Icons.camera_alt_rounded, color: Colors.white, size: 14),
                                                  SizedBox(width: 6),
                                                  Text(
                                                    'Retake Photo',
                                                    style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ],
                                      )
                                    : Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.all(16),
                                            decoration: BoxDecoration(
                                              color: Colors.white,
                                              shape: BoxShape.circle,
                                              boxShadow: [
                                                BoxShadow(
                                                  color: Colors.blue.withOpacity(0.08),
                                                  blurRadius: 8,
                                                  offset: const Offset(0, 2),
                                                )
                                              ],
                                            ),
                                            child: Icon(Icons.camera_enhance_rounded, size: 32, color: Colors.blue.shade700),
                                          ),
                                          const SizedBox(height: 12),
                                          Text(
                                            'Tap to Capture Face Photo',
                                            style: TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.blue.shade900,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            'Required for terminal biometric verification',
                                            style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
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
                              _buildGuidanceLabel(Icons.wb_sunny_outlined, 'Good Light'),
                              _buildGuidanceLabel(Icons.remove_red_eye_outlined, 'No Glasses'),
                              _buildGuidanceLabel(Icons.sentiment_neutral_outlined, 'Look Straight'),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Passenger Details Card with Strict Validations
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.blue.shade100, width: 1),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.blue.withOpacity(0.04),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          )
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: const [
                              Icon(Icons.badge_outlined, color: Color(0xFF0F172A), size: 20),
                              SizedBox(width: 8),
                              Text(
                                'Passenger Info',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF0F172A),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          
                          // 1. Full Name
                          _buildTextField(
                            controller: _nameController,
                            labelText: 'Full Name',
                            hintText: 'Enter passenger full name',
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
                          const SizedBox(height: 10),

                          // 2. Flight Number
                          _buildTextField(
                            controller: _flightController,
                            labelText: 'Flight Number',
                            hintText: 'e.g. AA104 or EK201',
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
                                return 'Please enter a valid flight number';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 10),

                          // 3. Passport Number
                          _buildTextField(
                            controller: _passportController,
                            labelText: 'Passport Number',
                            hintText: 'e.g. A9283726',
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
                              if (value.trim().length < 5) {
                                return 'Passport number is too short';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 10),

                          // 4. Email Address (Strict @ and domain check)
                          _buildTextField(
                            controller: _emailController,
                            labelText: 'Email Address',
                            hintText: 'e.g. passenger@email.com',
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
                              // Proper regex ensuring @ symbol and domain extension format
                              final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
                              if (!emailRegex.hasMatch(value.trim())) {
                                return 'Enter a valid email address (e.g. name@domain.com)';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 10),

                          // 5. Phone Number (Strict +94 format with exactly 9 digits following)
                          _buildTextField(
                            controller: _phoneController,
                            labelText: 'Phone Number',
                            hintText: 'e.g. +94771234567',
                            icon: Icons.phone_outlined,
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
                              // Strict validation: Must start with +94 followed by exactly 9 digits
                              final phoneRegExp = RegExp(r'^\+94\d{9}$');
                              if (!phoneRegExp.hasMatch(value.trim())) {
                                return 'Enter valid format: +94 followed by 9 digits (e.g. +94771234567)';
                              }
                              return null;
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 28),

                    // Primary Submit Button
                    ElevatedButton(
                      onPressed: _submitForm,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue.shade700,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        elevation: 3,
                        shadowColor: Colors.blue.withOpacity(0.3),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          Icon(Icons.fingerprint_rounded, color: Colors.white, size: 22),
                          SizedBox(width: 10),
                          Flexible(
                            child: Text(
                              'Register & Save Biometrics',
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
          ),
          
          // Loading Overlay
          if (_isLoading)
            Positioned.fill(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                child: Container(
                  color: Colors.black.withOpacity(0.4),
                  child: Center(
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 40),
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 20,
                            offset: const Offset(0, 10),
                          )
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 70,
                            height: 70,
                            child: CircularProgressIndicator(
                              strokeWidth: 3.5,
                              color: Colors.blue.shade700,
                              backgroundColor: Colors.blue.shade50,
                            ),
                          ),
                          const SizedBox(height: 24),
                          const Text(
                            'Processing Biometrics',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Uploading credentials and facial profile securely to terminal database...',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey.shade600,
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
        fontWeight: FontWeight.w600,
        color: Color(0xFF0F172A),
      ),
      decoration: InputDecoration(
        labelText: labelText,
        counterText: '', // Hide character counter underneath text field for clean UI
        labelStyle: TextStyle(
          color: Colors.grey.shade500,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
        floatingLabelStyle: TextStyle(
          color: Colors.blue.shade700,
          fontWeight: FontWeight.bold,
        ),
        hintText: hintText,
        hintStyle: TextStyle(
          color: Colors.grey.shade400,
          fontSize: 14,
          fontWeight: FontWeight.normal,
        ),
        prefixIcon: Icon(icon, color: Colors.blue.shade700, size: 20),
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.blue.shade100, width: 1.5),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.blue.shade100, width: 1.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.blue.shade700, width: 2.0),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Colors.redAccent, width: 1.5),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Colors.redAccent, width: 2.0),
        ),
        errorStyle: const TextStyle(
          color: Colors.redAccent,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildGuidanceLabel(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.blue.shade50.withOpacity(0.6),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.blue.shade700),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: Colors.blue.shade900,
            ),
          ),
        ],
      ),
    );
  }
}