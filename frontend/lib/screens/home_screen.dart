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

  String _formatPhotoUrl(String url) {
    if (url.isEmpty) return '';
    try {
      final baseUri = Uri.parse(ApiService.baseUrl);
      if (url.contains('localhost:5000')) {
        return url.replaceAll('localhost:5000', '${baseUri.host}:${baseUri.port}');
      }
    } catch (_) {}
    return url;
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
        SnackBar(
          content: const Text('Boarding Pass refreshed successfully!'),
          backgroundColor: Colors.green.shade700,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result['message'] ?? 'Failed to refresh status'),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_passenger == null) {
      return const Scaffold(
        backgroundColor: Color(0xFFF8FAFC),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final String name = _passenger!['full_name'] ?? 'Passenger';
    final String passport = _passenger!['passport_number'] ?? '';
    final String flight = _passenger!['flight_number'] ?? '';
    final String email = _passenger!['email'] ?? 'Not Provided';
    final String phone = _passenger!['phone_number'] ?? 'Not Provided';
    final String rawPhotoUrl = _passenger!['face_image_url'] ?? '';
    final String photoUrl = _formatPhotoUrl(rawPhotoUrl);
    final String status = _passenger!['check_in_status'] ?? 'Pending';

    final bool isCheckedIn = status.toLowerCase() == 'checked-in';

    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFFDBEAFE)),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF2563EB).withOpacity(0.08),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  )
                ],
              ),
              child: const Icon(Icons.flight_takeoff_rounded, color: Color(0xFF1D4ED8), size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'AERO GATEWAY',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Color(0xFF0F172A),
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.2,
                    ),
                  ),
                  Text(
                    'Digital Boarding Pass',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Color(0xFF1D4ED8)),
            onPressed: _refreshStatus,
            tooltip: 'Refresh Boarding Pass',
          ),
          IconButton(
            icon: const Icon(Icons.logout_rounded, color: Colors.redAccent),
            onPressed: () {
              Navigator.pushNamedAndRemoveUntil(context, AppRoutes.login, (route) => false);
            },
            tooltip: 'Logout',
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Status Banner Card
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: isCheckedIn
                            ? [const Color(0xFF059669), const Color(0xFF0D9488)]
                            : [const Color(0xFF1D4ED8), const Color(0xFF312E81)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: (isCheckedIn ? Colors.green : Colors.blue).withOpacity(0.25),
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
                            isCheckedIn ? Icons.verified_user_rounded : Icons.pending_actions_rounded,
                            color: Colors.white,
                            size: 28,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'BOARDING GATE PERMIT',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.0,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                isCheckedIn ? 'CHECKED-IN • READY FOR GATE' : 'PENDING TERMINAL SCAN',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
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

                  // DIGITAL AIRLINE BOARDING PASS TICKET
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: const Color(0xFFCBD5E1), width: 1.5),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.06),
                          blurRadius: 16,
                          offset: const Offset(0, 6),
                        )
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Flight Route Top Banner
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                          decoration: const BoxDecoration(
                            color: Color(0xFF0F172A),
                            borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
                          ),
                          child: Column(
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(
                                    children: const [
                                      Icon(Icons.flight_outlined, color: Color(0xFF38BDF8), size: 18),
                                      SizedBox(width: 6),
                                      Text(
                                        'AERO EXPRESS',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                          letterSpacing: 1.2,
                                        ),
                                      ),
                                    ],
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF38BDF8).withOpacity(0.15),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: const Color(0xFF38BDF8).withOpacity(0.3)),
                                    ),
                                    child: const Text(
                                      'FIRST CLASS',
                                      style: TextStyle(
                                        color: Color(0xFF38BDF8),
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 1.0,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'CMB',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 28,
                                          fontWeight: FontWeight.w900,
                                          letterSpacing: 1.0,
                                        ),
                                      ),
                                      Text(
                                        'COLOMBO',
                                        style: TextStyle(
                                          color: Colors.grey.shade400,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                  Row(
                                    children: [
                                      Container(
                                        width: 40,
                                        height: 1,
                                        color: const Color(0xFF38BDF8).withOpacity(0.4),
                                      ),
                                      Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 8.0),
                                        child: Icon(
                                          Icons.flight_takeoff_rounded,
                                          color: const Color(0xFF38BDF8),
                                          size: 22,
                                        ),
                                      ),
                                      Container(
                                        width: 40,
                                        height: 1,
                                        color: const Color(0xFF38BDF8).withOpacity(0.4),
                                      ),
                                    ],
                                  ),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      const Text(
                                        'LHR',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 28,
                                          fontWeight: FontWeight.w900,
                                          letterSpacing: 1.0,
                                        ),
                                      ),
                                      Text(
                                        'LONDON',
                                        style: TextStyle(
                                          color: Colors.grey.shade400,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),

                        // Main Ticket Passenger Details
                        Padding(
                          padding: const EdgeInsets.all(24.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                children: [
                                  // Profile Photo Avatar
                                  Container(
                                    padding: const EdgeInsets.all(3),
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      border: Border.all(color: const Color(0xFF1D4ED8), width: 2.5),
                                    ),
                                    child: ClipOval(
                                      child: Container(
                                        width: 66,
                                        height: 66,
                                        color: const Color(0xFFEFF6FF),
                                        child: photoUrl.isNotEmpty
                                            ? Image.network(
                                                photoUrl,
                                                fit: BoxFit.cover,
                                                loadingBuilder: (context, child, loadingProgress) {
                                                  if (loadingProgress == null) return child;
                                                  return const Center(
                                                    child: SizedBox(
                                                      width: 22,
                                                      height: 22,
                                                      child: CircularProgressIndicator(strokeWidth: 2),
                                                    ),
                                                  );
                                                },
                                                errorBuilder: (context, error, stackTrace) {
                                                  return const Icon(
                                                    Icons.person_rounded,
                                                    size: 34,
                                                    color: Color(0xFF1D4ED8),
                                                  );
                                                },
                                              )
                                            : const Icon(
                                                Icons.person_rounded,
                                                size: 34,
                                                color: Color(0xFF1D4ED8),
                                              ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          name,
                                          overflow: TextOverflow.ellipsis,
                                          maxLines: 1,
                                          style: const TextStyle(
                                            fontSize: 20,
                                            fontWeight: FontWeight.w900,
                                            color: Color(0xFF0F172A),
                                            letterSpacing: -0.3,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Row(
                                          children: [
                                            const Icon(Icons.vpn_key_outlined, size: 14, color: Color(0xFF64748B)),
                                            const SizedBox(width: 4),
                                            Text(
                                              'Passport: $passport',
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                fontSize: 13,
                                                color: Color(0xFF64748B),
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),

                              const SizedBox(height: 24),
                              const Divider(height: 1, thickness: 1, color: Color(0xFFE2E8F0)),
                              const SizedBox(height: 20),

                              // Flight Details Grid
                              Row(
                                children: [
                                  Expanded(child: _buildPassField('FLIGHT', flight, Icons.flight_takeoff_rounded)),
                                  Expanded(child: _buildPassField('GATE', 'GATE B4', Icons.door_sliding_rounded)),
                                  Expanded(child: _buildPassField('SEAT', '14A', Icons.airline_seat_recline_extra_rounded)),
                                ],
                              ),
                              const SizedBox(height: 20),
                              Row(
                                children: [
                                  Expanded(child: _buildPassField('EMAIL', email, Icons.email_outlined)),
                                  Expanded(child: _buildPassField('PHONE', phone, Icons.phone_outlined)),
                                ],
                              ),

                              const SizedBox(height: 24),
                              
                              // Dashed Ticket Divider Visual
                              Row(
                                children: List.generate(
                                  30,
                                  (index) => Expanded(
                                    child: Container(
                                      color: index % 2 == 0 ? Colors.transparent : Colors.grey.shade300,
                                      height: 2,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 20),

                              // Simulated Gate Scanner Barcode
                              Center(
                                child: Column(
                                  children: [
                                    const Text(
                                      'TOUCHLESS GATE SCANNER BARCODE',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF94A3B8),
                                        letterSpacing: 1.2,
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    _buildBarcodeGraphic(),
                                    const SizedBox(height: 6),
                                    Text(
                                      '*PASSENGER-$passport*',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontFamily: 'monospace',
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF64748B),
                                        letterSpacing: 2.0,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Terminal Guidelines Card
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFFE2E8F0), width: 1),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.03),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        )
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: const [
                            Icon(Icons.info_outline_rounded, color: Color(0xFF1D4ED8), size: 20),
                            SizedBox(width: 8),
                            Text(
                              'Terminal Boarding Guidelines',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF0F172A),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          '• Look directly into the CCTV camera at Gate B4 for instant touchless boarding.\n'
                          '• Keep your passport ready in case manual verification is requested by airport security.',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey.shade600,
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
    );
  }

  Widget _buildPassField(String label, String value, IconData icon) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 14, color: const Color(0xFF1D4ED8)),
            const SizedBox(width: 4),
            Text(
              label,
              style: const TextStyle(
                fontSize: 10,
                color: Color(0xFF94A3B8),
                fontWeight: FontWeight.bold,
                letterSpacing: 0.8,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: Color(0xFF0F172A),
          ),
        ),
      ],
    );
  }

  Widget _buildBarcodeGraphic() {
    return SizedBox(
      height: 40,
      width: 260,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(45, (index) {
          final width = (index % 5 == 0) ? 4.0 : ((index % 3 == 0) ? 2.5 : 1.2);
          return Container(
            width: width,
            margin: const EdgeInsets.symmetric(horizontal: 1.5),
            color: const Color(0xFF0F172A),
          );
        }),
      ),
    );
  }
}