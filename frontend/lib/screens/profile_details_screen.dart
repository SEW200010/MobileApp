import 'package:flutter/material.dart';
import '../services/api_service.dart';

class ProfileDetailsScreen extends StatefulWidget {
  final Map<String, dynamic> profile;

  const ProfileDetailsScreen({super.key, required this.profile});

  @override
  State<ProfileDetailsScreen> createState() => _ProfileDetailsScreenState();
}

class _ProfileDetailsScreenState extends State<ProfileDetailsScreen> {
  late String _checkInStatus;
  bool _isSimulating = false;
  String _simulationStep = "";

  @override
  void initState() {
    super.initState();
    _checkInStatus = widget.profile['check_in_status'] ?? 'Pending';
  }

  Future<void> _toggleCheckInStatus() async {
    final newStatus = _checkInStatus == 'Checked-In' ? 'Pending' : 'Checked-In';
    final passengerId = widget.profile['id'];

    if (newStatus == 'Checked-In') {
      // Simulate professional biometric scan flow
      setState(() {
        _isSimulating = true;
        _simulationStep = "Initializing facial scanners...";
      });

      await Future.delayed(const Duration(milliseconds: 700));
      setState(() {
        _simulationStep = "Scanning biometric keypoints...";
      });

      await Future.delayed(const Duration(milliseconds: 700));
      setState(() {
        _simulationStep = "Verifying with central database...";
      });

      await Future.delayed(const Duration(milliseconds: 600));
    } else {
      setState(() {
        _isSimulating = true;
        _simulationStep = "Resetting gate credentials...";
      });
      await Future.delayed(const Duration(milliseconds: 600));
    }

    try {
      final int id = passengerId is String ? int.parse(passengerId) : passengerId;
      final response = await ApiService.updateCheckInStatus(id, newStatus);

      if (mounted) {
        setState(() {
          _isSimulating = false;
          _simulationStep = "";
        });

        if (response['status'] == 'success') {
          setState(() {
            _checkInStatus = newStatus;
          });

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  Icon(
                    newStatus == 'Checked-In' ? Icons.verified_user_rounded : Icons.info_outline_rounded,
                    color: Colors.white,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(newStatus == 'Checked-In'
                        ? 'Biometric identification verified! Boarding Gate Open.'
                        : 'Passenger boarding clearance reset to pending.'),
                  ),
                ],
              ),
              backgroundColor: newStatus == 'Checked-In' ? const Color(0xFF10B981) : Colors.blue.shade800,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          );
        } else {
          _showError(response['message'] ?? 'Failed to update passenger status');
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSimulating = false;
          _simulationStep = "";
        });
        _showError('Connection error: $e');
      }
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline_rounded, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: const Color(0xFFEF4444),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isCheckedIn = _checkInStatus == 'Checked-In';
    final fullName = widget.profile['full_name'] ?? 'Unknown';
    final flightNum = widget.profile['flight_number'] ?? 'N/A';
    final passportNum = widget.profile['passport_number'] ?? 'N/A';
    final faceUrl = widget.profile['face_image_url'] ?? '';

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: Container(
          margin: const EdgeInsets.only(left: 16, top: 8, bottom: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: IconButton(
            icon: const Icon(Icons.arrow_back, color: Color(0xFF0F172A), size: 20),
            onPressed: () => Navigator.pop(context, true),
          ),
        ),
        title: const Text(
          'Boarding Pass',
          style: TextStyle(
            color: Color(0xFF0F172A),
            fontWeight: FontWeight.w700,
            fontSize: 20,
          ),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            // Boarding Ticket Card Stack
            Stack(
              children: [
                // Main Ticket White Container
                Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: Colors.grey.shade100),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.04),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                      )
                    ],
                  ),
                  child: Column(
                    children: [
                      // UPPER SECTION - Flight Route Header
                      Padding(
                        padding: const EdgeInsets.all(24.0),
                        child: Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    Icon(Icons.airplane_ticket_rounded, color: Colors.blue.shade800, size: 20),
                                    const SizedBox(width: 8),
                                    const Text(
                                      'BOARDING PASS',
                                      style: TextStyle(
                                        color: Color(0xFF0F172A),
                                        fontSize: 12,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 1.5,
                                      ),
                                    ),
                                  ],
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: isCheckedIn ? Colors.green.shade50 : Colors.amber.shade50,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: (isCheckedIn ? Colors.green : Colors.amber).withOpacity(0.2),
                                    ),
                                  ),
                                  child: Text(
                                    isCheckedIn ? 'VERIFIED' : 'PENDING CLEARANCE',
                                    style: TextStyle(
                                      color: isCheckedIn ? Colors.green.shade800 : Colors.amber.shade900,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 24),
                            
                            // CMB -> DXB Route Mockup
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: const [
                                    Text(
                                      'CMB',
                                      style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: Color(0xFF0F172A)),
                                    ),
                                    Text('Colombo, LK', style: TextStyle(fontSize: 12, color: Colors.grey)),
                                  ],
                                ),
                                Column(
                                  children: [
                                    Icon(Icons.flight_takeoff_rounded, color: Colors.blue.shade700, size: 28),
                                    const SizedBox(height: 4),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: Colors.blue.shade50,
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: Text(
                                        flightNum,
                                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.blue.shade800),
                                      ),
                                    ),
                                  ],
                                ),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: const [
                                    Text(
                                      'DXB',
                                      style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: Color(0xFF0F172A)),
                                    ),
                                    Text('Dubai, UAE', style: TextStyle(fontSize: 12, color: Colors.grey)),
                                  ],
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),

                      // TICKET SEPARATOR LINE (Dashed)
                      Row(
                        children: [
                          const SizedBox(width: 10),
                          Expanded(
                            child: CustomPaint(
                              painter: DashedLinePainter(),
                              size: const Size(double.infinity, 1),
                            ),
                          ),
                          const SizedBox(width: 10),
                        ],
                      ),

                      // LOWER SECTION - Biometric Scan & Details
                      Padding(
                        padding: const EdgeInsets.all(24.0),
                        child: Column(
                          children: [
                            // Passenger Face Ring Photo with Tech Brackets
                            Center(
                              child: SizedBox(
                                width: 150,
                                height: 150,
                                child: Stack(
                                  children: [
                                    // Circular image
                                    Center(
                                      child: Container(
                                        width: 134,
                                        height: 134,
                                        decoration: BoxDecoration(
                                          color: Colors.grey.shade50,
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: isCheckedIn ? const Color(0xFF10B981) : Colors.blue.shade100,
                                            width: 3,
                                          ),
                                        ),
                                        child: ClipOval(
                                          child: faceUrl.isNotEmpty
                                              ? Image.network(
                                                  faceUrl,
                                                  fit: BoxFit.cover,
                                                  errorBuilder: (context, error, stackTrace) => Container(
                                                    color: Colors.blue.shade50,
                                                    child: Icon(Icons.person, size: 50, color: Colors.blue.shade800),
                                                  ),
                                                )
                                              : Container(
                                                  color: Colors.blue.shade50,
                                                  child: Icon(Icons.person, size: 50, color: Colors.blue.shade800),
                                                ),
                                        ),
                                      ),
                                    ),

                                    // Holographic scanning overlay when simulating
                                    if (_isSimulating)
                                      Center(
                                        child: Container(
                                          width: 134,
                                          height: 134,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: Colors.blue.shade900.withOpacity(0.4),
                                          ),
                                          child: const Center(
                                            child: CircularProgressIndicator(color: Colors.white),
                                          ),
                                        ),
                                      ),

                                    // Corner Brackets for Scanner
                                    ..._buildScannerBrackets(),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            
                            // Scanning text or match confidence
                            if (_isSimulating)
                              Text(
                                _simulationStep,
                                style: TextStyle(
                                  color: Colors.blue.shade800,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              )
                            else
                              Text(
                                isCheckedIn ? 'FACIAL MATCH: 99.8% (AUTHORIZED)' : 'READY FOR VERIFICATION',
                                style: TextStyle(
                                  color: isCheckedIn ? const Color(0xFF10B981) : Colors.grey.shade600,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            const SizedBox(height: 28),

                            // Details Grid (Mock Passenger Data)
                            _buildInfoRow('PASSENGER NAME', fullName),
                            const Divider(height: 20),
                            Row(
                              children: [
                                Expanded(child: _buildInfoColumn('PASSPORT NO.', passportNum)),
                                Expanded(child: _buildInfoColumn('FLIGHT CODE', flightNum)),
                              ],
                            ),
                            const Divider(height: 20),
                            Row(
                              children: [
                                Expanded(child: _buildInfoColumn('SEAT NUMBER', isCheckedIn ? '14A' : 'TBD')),
                                Expanded(child: _buildInfoColumn('BOARDING ZONE', isCheckedIn ? 'Zone 2' : 'TBD')),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // Left Circle Cutout
                Positioned(
                  left: -10,
                  top: 130, // Corresponds to the separator line height
                  child: Container(
                    width: 20,
                    height: 20,
                    decoration: const BoxDecoration(
                      color: Color(0xFFF8FAFC),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),

                // Right Circle Cutout
                Positioned(
                  right: -10,
                  top: 130, // Corresponds to the separator line height
                  child: Container(
                    width: 20,
                    height: 20,
                    decoration: const BoxDecoration(
                      color: Color(0xFFF8FAFC),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 32),           
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
        ],
      ),
    );
  }

  Widget _buildInfoColumn(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
      ],
    );
  }

  // Scanner tech corners
  List<Widget> _buildScannerBrackets() {
    const double bracketSize = 16;
    const double borderThickness = 3;
    final Color bracketColor = _checkInStatus == 'Checked-In' ? const Color(0xFF10B981) : Colors.blue.shade700;

    Widget buildBracket(bool top, bool left) {
      return Positioned(
        top: top ? 0 : null,
        bottom: top ? null : 0,
        left: left ? 0 : null,
        right: left ? null : 0,
        child: Container(
          width: bracketSize,
          height: bracketSize,
          decoration: BoxDecoration(
            border: Border(
              top: top ? BorderSide(color: bracketColor, width: borderThickness) : BorderSide.none,
              bottom: top ? BorderSide.none : BorderSide(color: bracketColor, width: borderThickness),
              left: left ? BorderSide(color: bracketColor, width: borderThickness) : BorderSide.none,
              right: left ? BorderSide.none : BorderSide(color: bracketColor, width: borderThickness),
            ),
          ),
        ),
      );
    }

    return [
      buildBracket(true, true),
      buildBracket(true, false),
      buildBracket(false, true),
      buildBracket(false, false),
    ];
  }
}

class DashedLinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    double dashWidth = 5, dashSpace = 4, startX = 0;
    final paint = Paint()
      ..color = Colors.grey.shade200
      ..strokeWidth = 1.5;
    while (startX < size.width) {
      canvas.drawLine(Offset(startX, 0), Offset(startX + dashWidth, 0), paint);
      startX += dashWidth + dashSpace;
    }
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}