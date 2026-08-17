import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'profile_details_screen.dart';

class ProfileListScreen extends StatefulWidget {
  const ProfileListScreen({super.key});

  @override
  State<ProfileListScreen> createState() => _ProfileListScreenState();
}

class _ProfileListScreenState extends State<ProfileListScreen> {
  late Future<List<dynamic>> _profilesFuture;

  @override
  void initState() {
    super.initState();
    _profilesFuture = ApiService.getProfiles();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Registered Passengers')),
      body: FutureBuilder<List<dynamic>>(
        future: _profilesFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          } else if (snapshot.hasError || !snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text('No registered profiles found!'));
          }

          final profiles = snapshot.data!;

          return ListView.builder(
            itemCount: profiles.length,
            itemBuilder: (context, index) {
              final profile = profiles[index];
              final isCheckedIn = profile['check_in_status'] == 'Checked-In';

              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundImage: NetworkImage(profile['face_image_url'] ?? ''),
                    onBackgroundImageError: (exception, stackTrace) {
                      debugPrint('Error loading image: $exception');
                    },
                  ),
                  title: Text(profile['full_name'], style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text('Flight: ${profile['flight_number']} | Passport: ${profile['passport_number']}'),
                  trailing: Chip(
                    label: Text(profile['check_in_status'] ?? 'Pending'),
                    backgroundColor: isCheckedIn ? Colors.green[100] : Colors.orange[100],
                    labelStyle: TextStyle(color: isCheckedIn ? Colors.green[800] : Colors.orange[800]),
                  ),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => ProfileDetailsScreen(profile: profile),
                      ),
                    );
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}