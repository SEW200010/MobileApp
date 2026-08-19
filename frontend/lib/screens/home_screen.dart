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
                        _buildDetailRow(Icons.flight_takeoff_rounded, 'Flight', flight),
                        const SizedBox(height: 16),
                        _buildDetailRow(Icons.email_outlined, 'Email', email),
                        const SizedBox(height: 16),
                        _buildDetailRow(Icons.phone_outlined, 'Phone', phone),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // QR Code Card
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
                      children: [
                        const Text(
                          'Digital Boarding QR Code',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Scan at boarding gate for access validation',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                        ),
                        const SizedBox(height: 24),
                        // Mock QR Paint widget
                        Container(
                          width: 160,
                          height: 160,
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey.shade200, width: 2),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: CustomPaint(
                            painter: MockQrPainter(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          passport,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey.shade600,
                            letterSpacing: 2,
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

// Custom Painter to draw a realistic mockup of a QR Code
class MockQrPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF0F172A)
      ..style = PaintingStyle.fill;

    // Draw finder patterns at 3 corners
    void drawFinderPattern(double x, double y) {
      // Outer 7x7 module square
      canvas.drawRect(Rect.fromLTWH(x, y, 28, 28), paint);
      // White inner spacer
      canvas.drawRect(
        Rect.fromLTWH(x + 4, y + 4, 20, 20),
        Paint()..color = Colors.white,
      );
      // Center solid block
      canvas.drawRect(Rect.fromLTWH(x + 8, y + 8, 12, 12), paint);
    }

    drawFinderPattern(0, 0); // Top-Left
    drawFinderPattern(size.width - 28, 0); // Top-Right
    drawFinderPattern(0, size.height - 28); // Bottom-Left

    // Draw mock data modules in a grid
    const int gridCount = 21;
    final double stepX = size.width / gridCount;
    final double stepY = size.height / gridCount;

    for (int x = 0; x < gridCount; x++) {
      for (int y = 0; y < gridCount; y++) {
        // Skip corner finder zones (7x7 modules)
        if ((x < 7 && y < 7) || (x >= gridCount - 7 && y < 7) || (x < 7 && y >= gridCount - 7)) {
          continue;
        }

        // Draw pseudorandom patterns based on position
        bool shouldDraw = false;
        // Deterministic patterns
        if ((x * 3 + y * 7) % 5 == 0) shouldDraw = true;
        if ((x * y) % 3 == 1) shouldDraw = true;
        if ((x + y) % 4 == 0) shouldDraw = true;
        
        // Exclude some areas to make it look like a real QR code layout
        if (x == 6 || y == 6) {
          // Timing patterns (alternating black/white)
          shouldDraw = (x % 2 == 0) || (y % 2 == 0);
        }

        if (shouldDraw) {
          canvas.drawRect(
            Rect.fromLTWH(x * stepX, y * stepY, stepX - 0.5, stepY - 0.5),
            paint,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}