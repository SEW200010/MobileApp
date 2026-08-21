import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../routes.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Map<String, dynamic>? _passenger;
  bool _isLoading = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_passenger == null) {
      final args = ModalRoute.of(context)!.settings.arguments;
      if (args is Map<String, dynamic>) {
        _passenger = args;
      }
    }
  }

  Future<void> _refreshStatus() async {
    if (_passenger == null) return;
    
    setState(() {
      _isLoading = true;
    });

    final passportNumber = _passenger!['passport_number'];
    final result = await ApiService.login(passportNumber);

    setState(() {
      _isLoading = false;
    });

    if (!mounted) return;

    if (result['status'] == 'success') {
      setState(() {
        _passenger = result['data'];
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Status refreshed successfully!'),
          backgroundColor: Colors.green,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result['message'] ?? 'Failed to refresh status'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_passenger == null) {
      return const Scaffold(
        body: Center(child: Text('Loading passenger data...')),
      );
    }

    final String name = _passenger!['full_name'] ?? 'Passenger';
    final String passport = _passenger!['passport_number'] ?? '';
    final String flight = _passenger!['flight_number'] ?? '';
    final String email = _passenger!['email'] ?? 'Not Provided';
    final String phone = _passenger!['phone_number'] ?? 'Not Provided';
    final String photoUrl = _passenger!['face_image_url'] ?? '';
    final String status = _passenger!['check_in_status'] ?? 'Pending';

    final bool isCheckedIn = status.toLowerCase() == 'checked-in';

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.flight_takeoff, color: Colors.blue.shade800, size: 24),
            ),
            const SizedBox(width: 12),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'AERO GATEWAY',
                  style: TextStyle(
                    color: Color(0xFF0F172A),
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.5,
                  ),
                ),
                Text(
                  'Passenger Boarding Pass',
                  style: TextStyle(
                    color: Colors.grey,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh_rounded, color: Colors.grey.shade700),
            onPressed: _refreshStatus,
          ),
          IconButton(
            icon: Icon(Icons.logout_rounded, color: Colors.red.shade700),
            onPressed: () {
              Navigator.pushNamedAndRemoveUntil(context, AppRoutes.login, (route) => false);
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Status Banner Card
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: isCheckedIn
                            ? [Colors.green.shade600, Colors.teal.shade700]
                            : [Colors.amber.shade600, Colors.orange.shade700],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: (isCheckedIn ? Colors.green : Colors.orange)
                              .withOpacity(0.3),
                          blurRadius: 16,
                          offset: const Offset(0, 6),
                        )
                      ],
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            isCheckedIn ? Icons.verified_rounded : Icons.pending_actions_rounded,
                            color: Colors.white,
                            size: 32,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Check-In Status',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                isCheckedIn ? 'CHECKED-IN' : 'PENDING BIOMETRICS',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Passenger Details Card
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: Colors.grey.shade100),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.02),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        )
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            // Passenger Avatar
                            CircleAvatar(
                              radius: 36,
                              backgroundColor: Colors.blue.shade50,
                              backgroundImage: photoUrl.isNotEmpty ? NetworkImage(photoUrl) : null,
                              child: photoUrl.isEmpty
                                  ? Icon(Icons.person_rounded, size: 36, color: Colors.blue.shade800)
                                  : null,
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    name,
                                    style: const TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF0F172A),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Passport: $passport',
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Colors.grey.shade500,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const Divider(height: 32, thickness: 1),
                        _buildDetailRow(Icons.flight_takeoff_rounded, 'Flight Number', flight),
                        const SizedBox(height: 16),
                        _buildDetailRow(Icons.email_outlined, 'Email Address', email),
                        const SizedBox(height: 16),
                        _buildDetailRow(Icons.phone_outlined, 'Phone Number', phone),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Standardized Action / Information Card (Replacing QR code)
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: Colors.grey.shade100),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.02),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        )
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.info_outline_rounded, color: Colors.blue.shade800, size: 22),
                            const SizedBox(width: 10),
                            const Text(
                              'Terminal Guidelines',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF0F172A),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Text(
                          '• Please ensure your biometric verification is completed at the terminal kiosk before proceeding to the boarding gate.\n• Keep your passport and flight credentials readily accessible.',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey.shade600,
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildDetailRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, color: Colors.blue.shade600, size: 20),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade400,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              value,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Color(0xFF0F172A),
              ),
            ),
          ],
        ),
      ],
    );
  }
}