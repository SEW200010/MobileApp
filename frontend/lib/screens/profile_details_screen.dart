import 'package:flutter/material.dart';

class ProfileDetailsScreen extends StatelessWidget {
  final Map<String, dynamic> profile;

  const ProfileDetailsScreen({super.key, required this.profile});

  @override
  Widget build(BuildContext context) {
    final isCheckedIn = profile['check_in_status'] == 'Checked-In';

    return Scaffold(
      appBar: AppBar(title: Text(profile['full_name'])),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            Center(
              child: CircleAvatar(
                radius: 70,
                backgroundImage: NetworkImage(profile['face_image_url'] ?? ''),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              profile['full_name'],
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Chip(
              label: Text('Status: ${profile['check_in_status'] ?? 'Pending'}', style: const TextStyle(fontSize: 16)),
              backgroundColor: isCheckedIn ? Colors.green[100] : Colors.orange[100],
            ),
            const Divider(height: 40),
            ListTile(
              leading: const Icon(Icons.flight),
              title: const Text('Flight Number'),
              subtitle: Text(profile['flight_number'], style: const TextStyle(fontSize: 18)),
            ),
            ListTile(
              leading: const Icon(Icons.badge),
              title: const Text('Passport Number'),
              subtitle: Text(profile['passport_number'], style: const TextStyle(fontSize: 18)),
            ),
          ],
        ),
      ),
    );
  }
}