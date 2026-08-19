import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:http_parser/http_parser.dart';

class ApiService {
  static const String baseUrl = 'http://localhost:5000';

  static Future<Map<String, dynamic>> registerPassenger({
    required String fullName,
    required String flightNumber,
    required String passportNumber,
    required String email,
    required String phoneNumber,
    required XFile imageFile,
  }) async {
    try {
      var uri = Uri.parse('$baseUrl/register'); 
      var request = http.MultipartRequest('POST', uri);

      request.fields['full_name'] = fullName;
      request.fields['flight_number'] = flightNumber;
      request.fields['passport_number'] = passportNumber;
      request.fields['email'] = email;
      request.fields['phone_number'] = phoneNumber;

      Uint8List imageBytes = await imageFile.readAsBytes();

      request.files.add(
        http.MultipartFile.fromBytes(
          'face_image',
          imageBytes,
          filename: imageFile.name,
          contentType: MediaType('image', 'jpeg'),
        ),
      );

      var streamedResponse = await request.send();
      var response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200 || response.statusCode == 201) {
        return json.decode(response.body);
      } else {
        return {'status': 'error', 'message': response.body};
      }
    } catch (e) {
      return {'status': 'error', 'message': e.toString()};
    }
  }

  static Future<List<dynamic>> getProfiles() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/get_profiles'));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'success') {
          return data['data'] as List<dynamic>;
        }
      }
      return [];
    } catch (e) {
      debugPrint('Error getting profiles: $e');
      return [];
    }
  }

  static Future<Map<String, dynamic>> updateCheckInStatus(int id, String status) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/check_in/$id'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'status': status}),
      );
      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        return {'status': 'error', 'message': 'HTTP error ${response.statusCode}'};
      }
    } catch (e) {
      return {'status': 'error', 'message': e.toString()};
    }
  }

  static Future<Map<String, dynamic>> login(String passportNumber) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/login'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'passport_number': passportNumber}),
      );
      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        return {'status': 'error', 'message': 'HTTP error ${response.statusCode}'};
      }
    } catch (e) {
      return {'status': 'error', 'message': e.toString()};
    }
  }

  static Future<Map<String, dynamic>> sendOtp(String identifier, {bool isRegistration = false}) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/send_otp'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'identifier': identifier,
          'is_registration': isRegistration,
        }),
      );
      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        return {'status': 'error', 'message': 'HTTP error ${response.statusCode}'};
      }
    } catch (e) {
      return {'status': 'error', 'message': e.toString()};
    }
  }

  static Future<Map<String, dynamic>> verifyOtp(String identifier, String otp) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/verify_otp'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'identifier': identifier,
          'otp': otp,
        }),
      );
      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        return {'status': 'error', 'message': 'HTTP error ${response.statusCode}'};
      }
    } catch (e) {
      return {'status': 'error', 'message': e.toString()};
    }
  }

  static Future<Map<String, dynamic>> verifyFace(String passportNumber, XFile cctvImage) async {
    try {
      var uri = Uri.parse('$baseUrl/verify_face'); 
      var request = http.MultipartRequest('POST', uri);

      request.fields['passport_number'] = passportNumber;

      Uint8List imageBytes = await cctvImage.readAsBytes();

      request.files.add(
        http.MultipartFile.fromBytes(
          'cctv_image',
          imageBytes,
          filename: cctvImage.name,
          contentType: MediaType('image', 'jpeg'),
        ),
      );

      var streamedResponse = await request.send();
      var response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200 || response.statusCode == 201) {
        return json.decode(response.body);
      } else {
        return {'status': 'error', 'message': response.body};
      }
    } catch (e) {
      return {'status': 'error', 'message': e.toString()};
    }
  }
}