import 'package:flutter/material.dart';
import 'dart:async';
import 'package:image_picker/image_picker.dart';
import '../services/api_service.dart';
import '../routes.dart';

class OtpVerificationScreen extends StatefulWidget {
  final String identifier;
  final String mockOtp;
  final bool isRegistration;
  final Map<String, dynamic>? registrationData; // Contains name, flight, passport, email, phone, face_image (XFile)

  const OtpVerificationScreen({
    super.key,
    required this.identifier,
    required this.mockOtp,
    required this.isRegistration,
    this.registrationData,
  });

  @override
  State<OtpVerificationScreen> createState() => _OtpVerificationScreenState();
}

class _OtpVerificationScreenState extends State<OtpVerificationScreen> {
  final List<TextEditingController> _controllers = List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _focusNodes = List.generate(6, (_) => FocusNode());
  bool _isLoading = false;
  late String _currentMockOtp;
  int _timerSeconds = 59;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _currentMockOtp = widget.mockOtp;
    _startTimer();
  }

  void _startTimer() {
    _timerSeconds = 59;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_timerSeconds == 0) {
        setState(() {
          _timer?.cancel();
        });
      } else {
        setState(() {
          _timerSeconds--;
        });
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    for (var controller in _controllers) {
      controller.dispose();
    }
    for (var focusNode in _focusNodes) {
      focusNode.dispose();
    }
    super.dispose();
  }

  Future<void> _resendOtp() async {
    setState(() {
      _isLoading = true;
    });

    final result = await ApiService.sendOtp(
      widget.identifier,
      isRegistration: widget.isRegistration,
    );

    setState(() {
      _isLoading = false;
    });

    if (!mounted) return;

    if (result['status'] == 'success') {
      setState(() {
        _currentMockOtp = result['otp'] ?? '';
      });
      _startTimer();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Verification code resent successfully!'),
          backgroundColor: Colors.green.shade600,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result['message'] ?? 'Failed to resend code'),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    }
  }

  Future<void> _verifyOtp() async {
    String code = _controllers.map((c) => c.text).join();
    if (code.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Please enter the complete 6-digit verification code'),
          backgroundColor: Colors.orange.shade800,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    // 1. Verify the OTP code
    final result = await ApiService.verifyOtp(widget.identifier, code);

    if (result['status'] == 'success') {
      if (widget.isRegistration) {
        // 2. Perform the actual Registration
        final regData = widget.registrationData!;
        final regResult = await ApiService.registerPassenger(
          fullName: regData['full_name'],
          flightNumber: regData['flight_number'],
          passportNumber: regData['passport_number'],
          email: regData['email'],
          phoneNumber: regData['phone_number'],
          imageFile: regData['face_image'] as XFile,
        );

        setState(() {
          _isLoading = false;
        });

        if (!mounted) return;

        if (regResult['status'] == 'success') {
          final loginRes = await ApiService.login(regData['passport_number']);
          if (!mounted) return;

          if (loginRes['status'] == 'success') {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text('Registration & Biometric Profile created successfully!'),
                backgroundColor: Colors.green.shade600,
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            );
            Navigator.pushNamedAndRemoveUntil(
              context,
              AppRoutes.home,
              (route) => false,
              arguments: loginRes['data'],
            );
          } else {
            Navigator.pushNamedAndRemoveUntil(context, AppRoutes.login, (route) => false);
          }
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(regResult['message'] ?? 'Failed to register passenger profile'),
              backgroundColor: Colors.redAccent,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          );
        }
      } else {
        setState(() {
          _isLoading = false;
        });

        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Authentication verified successfully!'),
            backgroundColor: Colors.green.shade600,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
        Navigator.pushNamedAndRemoveUntil(
          context,
          AppRoutes.home,
          (route) => false,
          arguments: result['data'],
        );
      }
    } else {
      setState(() {
        _isLoading = false;
      });
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result['message'] ?? 'Invalid verification code'),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9), // Soft Modern Light Slate Background
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Color(0xFF1E293B)),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Stack(
        children: [
          // Background Soft Decorative Glow
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
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 28.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 10),
                    // Security Icon Badge
                    Center(
                      child: Container(
                        padding: const EdgeInsets.all(22),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.blue.withOpacity(0.12),
                              blurRadius: 20,
                              offset: const Offset(0, 8),
                            )
                          ],
                        ),
                        child: Icon(
                          Icons.verified_user_rounded,
                          color: Colors.blue.shade700,
                          size: 48,
                        ),
                      ),
                    ),
                    const SizedBox(height: 32),

                    // Title
                    const Text(
                      'Security Verification',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF0F172A),
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Enter the 6-digit secure code sent to\n${widget.identifier}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Color(0xFF64748B),
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 40),

                    // 6-digit inputs row
                    //
                    // Expanded, not a fixed 48px box. Six 48px boxes need 288px
                    // and the row had no way to shrink, so it overflowed on a
                    // 320px phone and on any narrow browser window. Each cell
                    // now takes an equal share of whatever width there is.
                    Row(
                      children: List.generate(6, (index) {
                        return Expanded(
                          child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 3),
                          child: SizedBox(
                          height: 56,
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: Colors.blue.shade100,
                                width: 1.5,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.03),
                                  blurRadius: 8,
                                  offset: const Offset(0, 4),
                                )
                              ],
                            ),
                            child: TextField(
                              controller: _controllers[index],
                              focusNode: _focusNodes[index],
                              textAlign: TextAlign.center,
                              keyboardType: TextInputType.number,
                              maxLength: 1,
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF0F172A),
                              ),
                              decoration: const InputDecoration(
                                counterText: '',
                                border: InputBorder.none,
                              ),
                              onChanged: (value) {
                                if (value.isNotEmpty) {
                                  if (index < 5) {
                                    _focusNodes[index + 1].requestFocus();
                                  } else {
                                    _focusNodes[index].unfocus();
                                  }
                                } else {
                                  if (index > 0) {
                                    _focusNodes[index - 1].requestFocus();
                                  }
                                }
                              },
                            ),
                          ),
                          ),
                          ),
                        );
                      }),
                    ),
                    const SizedBox(height: 36),

                    // Verify Button
                    ElevatedButton(
                      onPressed: _isLoading ? null : _verifyOtp,
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
                      child: _isLoading
                          ? const SizedBox(
                              height: 22,
                              width: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : const Text(
                              'Verify & Proceed',
                              style: TextStyle(
                                fontSize: 16, 
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.5,
                              ),
                            ),
                    ),
                    const SizedBox(height: 24),

                    // Countdown / Resend Option
                    Center(
                      child: _timerSeconds > 0
                          ? Text(
                              'Resend code in 0:${_timerSeconds.toString().padLeft(2, '0')}',
                              style: const TextStyle(
                                color: Color(0xFF64748B),
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            )
                          : TextButton(
                              onPressed: _isLoading ? null : _resendOtp,
                              child: Text(
                                'Resend Code',
                                style: TextStyle(
                                  color: Colors.blue.shade700,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                    ),

                    const SizedBox(height: 36),

                    // Styled Mock SMS display box
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
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
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.sms_rounded, color: Colors.blue.shade700, size: 18),
                              const SizedBox(width: 8),
                              // Flexible so the label ellipsises instead of
                              // pushing the row past its parent.
                              Flexible(
                                child: Text(
                                  'SMS Gateway Simulator',
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.blue.shade900,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Your simulated 6-digit OTP code is:',
                            style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                          ),
                          const SizedBox(height: 6),
                          GestureDetector(
                            onTap: () {
                              for (int i = 0; i < 6; i++) {
                                if (i < _currentMockOtp.length) {
                                  _controllers[i].text = _currentMockOtp[i];
                                }
                              }
                              setState(() {});
                            },
                            child: Text(
                              _currentMockOtp,
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w900,
                                color: Colors.blue.shade800,
                                letterSpacing: 6,
                                decoration: TextDecoration.underline,
                                decorationColor: Colors.blue.shade800,
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            '(Tap the code above to auto-fill)',
                            style: TextStyle(fontSize: 10, color: Color(0xFF94A3B8)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}