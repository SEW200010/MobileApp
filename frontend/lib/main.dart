import 'package:flutter/material.dart';
import 'screens/home_screen.dart';

void main() {
  runApp(const AirportCheckInApp());
}

class AirportCheckInApp extends StatelessWidget{
  const AirportCheckInApp({super.key});

  @override
  Widget build(BuildContext context){
    return MaterialApp(
      title: 'Airport Face Check-In',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch:Colors.blue,
        scaffoldBackgroundColor: Colors.grey[100],
      ),
      home: const HomeScreen(),
    );
  }
}