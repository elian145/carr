import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'config.dart';
import 'api_service.dart';

class AiService {
  
  
  /// Analyze a single car image and extract vehicle information
  static Future<Map<String, dynamic>?> analyzeCarImage(XFile imageFile) async {
    try {
      final url = Uri.parse('${apiBaseApi()}/analyze-car-image');
      final request = http.MultipartRequest('POST', url);
      
      // Add authorization header if available
      final token = await _getAuthToken();
      if (token != null) {
        request.headers['Authorization'] = 'Bearer $token';
      }
      
      // Add image file
      request.files.add(await http.MultipartFile.fromPath('image', imageFile.path));
      
      final response = await request.send();
      final responseBody = await http.Response.fromStream(response);
      
      if (response.statusCode == 200) {
        return json.decode(responseBody.body);
      } else {
        print('AI analysis failed: ${response.statusCode} - ${responseBody.body}');
        return null;
      }
    } catch (e) {
      print('Error analyzing car image: $e');
      return null;
    }
  }
  
  /// Process multiple images.
  ///
  /// License-plate blurring has been removed; this is currently a no-op that
  /// returns the original list.
  static Future<List<XFile>?> processCarImages(List<XFile> imageFiles) async {
    try {
      return imageFiles;
    } catch (e) {
      print('AI Service: Error processing images: $e');
      return null;
    }
  }
  
  static Future<String?> _getAuthToken() async {
    return ApiService.accessToken;
  }
  
  /// Extract car information from AI analysis result
  static Map<String, dynamic> extractCarInfo(Map<String, dynamic> analysis) {
    final carInfo = <String, dynamic>{};
    
    if (analysis['car_info'] != null) {
      final info = analysis['car_info'];
      if (info['color'] != null) carInfo['color'] = info['color'];
      if (info['body_type'] != null) carInfo['body_type'] = info['body_type'];
      if (info['condition'] != null) carInfo['condition'] = info['condition'];
      if (info['doors'] != null) carInfo['doors'] = info['doors'];
    }
    
    if (analysis['brand_model'] != null) {
      final brandModel = analysis['brand_model'];
      if (brandModel['brand'] != null) carInfo['brand'] = brandModel['brand'];
      if (brandModel['model'] != null) carInfo['model'] = brandModel['model'];
    }
    
    return carInfo;
  }
  
  /// Get confidence scores from analysis
  static Map<String, double> getConfidenceScores(Map<String, dynamic> analysis) {
    if (analysis['confidence_scores'] != null) {
      final scores = analysis['confidence_scores'];
      return {
        'color': (scores['color'] ?? 0.0).toDouble(),
        'body_type': (scores['body_type'] ?? 0.0).toDouble(),
        'condition': (scores['condition'] ?? 0.0).toDouble(),
        'brand_model': (scores['brand_model'] ?? 0.0).toDouble(),
      };
    }
    return {};
  }
}
