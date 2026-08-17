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
    required XFile imageFile,
  }) async {
    try {
      var uri = Uri.parse('$baseUrl/register'); 
      var request = http.MultipartRequest('POST', uri);

      request.fields['full_name'] = fullName;
      request.fields['flight_number'] = flightNumber;
      request.fields['passport_number'] = passportNumber;

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
}