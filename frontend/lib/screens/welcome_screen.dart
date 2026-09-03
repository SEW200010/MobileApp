import 'package:flutter/material.dart';
import '../routes.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GestureDetector(
        // Tap anywhere on the screen to navigate to the login screen
        onTap: () {
          Navigator.pushReplacementNamed(
            context,
            AppRoutes.login,
          );
        },
        child: Stack(
          children: [
            // 1. Background Image covering the entire screen
            Positioned.fill(
              child: Image.network(
                'https://images.unsplash.com/photo-1436491865332-7a61a109cc05?q=80&w=1000&auto=format&fit=crop',
                fit: BoxFit.cover, // Ensures the image covers the entire area
              ),
            ),
            
            // 2. Dark Gradient Overlay for optimal contrast
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.black.withOpacity(0.8),
                      Colors.black.withOpacity(0.3)
                    ],
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                  ),
                ),
              ),
            ),

            // 3. Content Area with SafeArea to avoid system overlays
            Positioned.fill(
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      const Icon(
                        Icons.flight_takeoff,
                        size: 60,
                        color: Colors.white,
                      ),
                      const SizedBox(height: 15),
                      const Text(
                        'Smart Airport\nFace Check-In',
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'Fast, secure, and touchless boarding experience powered by facial recognition.',
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.white70,
                        ),
                      ),
                      const SizedBox(height: 40),                     
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}