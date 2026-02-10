import 'dart:io';
import 'dart:convert';
import 'dart:async' show TimeoutException;
import 'package:flutter/foundation.dart';
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
      request.files.add(
        await http.MultipartFile.fromPath('image', imageFile.path),
      );

      final response = await request.send();
      final responseBody = await http.Response.fromStream(response);

      if (response.statusCode == 200) {
        return json.decode(responseBody.body);
      } else {
        if (kDebugMode) {
          debugPrint(
            'AI analysis failed: ${response.statusCode} - ${responseBody.body}',
          );
        }
        return null;
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error analyzing car image: $e');
      }
      return null;
    }
  }

  /// Process multiple images: send each to backend for license-plate blur,
  /// then return a list of XFiles pointing to the blurred temp files.
  static Future<List<XFile>?> processCarImages(List<XFile> imageFiles) async {
    if (imageFiles.isEmpty) return imageFiles;
    try {
      final token = await _getAuthToken();
      if (token == null || token.isEmpty) {
        if (kDebugMode) {
          debugPrint('AI Service: Blur requires authentication');
        }
        return null;
      }
      final base = apiBaseApi();
      final uri = Uri.parse('$base/blur-image');
      if (kDebugMode) {
        debugPrint('AI Service: Blur endpoint: $uri');
      }
      final List<XFile> result = [];
      int failed = 0;
      const int maxRetries = 2;
      const durationBetweenRequests = Duration(milliseconds: 400);
      for (int i = 0; i < imageFiles.length; i++) {
        if (i > 0) await Future.delayed(durationBetweenRequests);
        final file = imageFiles[i];
        if (kDebugMode) {
          debugPrint(
            'AI Service: Blurring image ${i + 1}/${imageFiles.length}',
          );
        }
        bool success = false;
        for (int attempt = 0; attempt <= maxRetries && !success; attempt++) {
          if (attempt > 0) {
            if (kDebugMode) {
              debugPrint(
                'AI Service: Retry $attempt/$maxRetries for image ${i + 1}',
              );
            }
            await Future.delayed(const Duration(seconds: 2));
          }
          try {
            final request = http.MultipartRequest('POST', uri);
            request.headers['Authorization'] = 'Bearer $token';
            request.files.add(
              await http.MultipartFile.fromPath('image', file.path),
            );
            final streamed = await request.send().timeout(
              const Duration(seconds: 90),
              onTimeout: () => throw TimeoutException(
                'Blur request timed out for image ${i + 1}',
              ),
            );
            final response = await http.Response.fromStream(streamed);
            if (response.statusCode != 200) {
              if (kDebugMode) {
                debugPrint(
                  'AI Service: Blur failed for image ${i + 1}: ${response.statusCode} ${response.body}',
                );
              }
              break;
            }
            final bytes = response.bodyBytes;
            if (bytes.isEmpty) break;
            final dir = Directory.systemTemp;
            final outFile = File(
              '${dir.path}/blurred_${i}_${DateTime.now().millisecondsSinceEpoch}_blurred.jpg',
            );
            await outFile.writeAsBytes(bytes);
            result.add(XFile(outFile.path));
            success = true;
          } on TimeoutException catch (e) {
            if (kDebugMode) {
              debugPrint('AI Service: Timeout for image ${i + 1}: $e');
            }
          } catch (e) {
            if (kDebugMode) {
              debugPrint(
                'AI Service: Error for image ${i + 1} (attempt ${attempt + 1}): $e',
              );
            }
          }
        }
        if (!success) {
          result.add(file);
          failed++;
        }
      }
      if (failed > 0) {
        if (kDebugMode) {
          debugPrint(
            'AI Service: $failed of ${imageFiles.length} images could not be blurred; originals kept.',
          );
        }
      }
      return result;
    } on TimeoutException catch (e) {
      if (kDebugMode) {
        debugPrint('AI Service: Timeout: $e');
      }
      return null;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('AI Service: Error processing images: $e');
      }
      return null;
    }
  }

  /// Blur/store images on the server (single request) and return server-relative paths.
  /// This is used by the "Blur Plates" button so blurring only happens when requested.
  static Future<List<String>?> processCarImagesToServerPaths(
    List<XFile> imageFiles,
  ) async {
    if (imageFiles.isEmpty) return const [];
    try {
      final token = await _getAuthToken();
      if (token == null || token.isEmpty) {
        if (kDebugMode) {
          debugPrint('AI Service: Processing requires authentication');
        }
        return null;
      }
      final url = Uri.parse('${apiBaseApi()}/process-car-images');
      final request = http.MultipartRequest('POST', url);
      request.headers['Authorization'] = 'Bearer $token';
      for (final f in imageFiles) {
        request.files.add(await http.MultipartFile.fromPath('images', f.path));
      }
      final streamed = await request.send().timeout(
        const Duration(seconds: 180),
        onTimeout: () => throw TimeoutException('Process images timed out'),
      );
      final response = await http.Response.fromStream(streamed);
      if (response.statusCode != 200) {
        if (kDebugMode) {
          debugPrint(
            'AI Service: Process images failed: ${response.statusCode} ${response.body}',
          );
        }
        return null;
      }
      final data = json.decode(response.body);
      final List<dynamic> list =
          (data is Map && data['processed_images'] is List)
          ? (data['processed_images'] as List)
          : const [];
      return list
          .map((e) => e.toString())
          .where((s) => s.trim().isNotEmpty)
          .toList();
    } on TimeoutException catch (e) {
      if (kDebugMode) {
        debugPrint('AI Service: Timeout: $e');
      }
      return null;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('AI Service: Error processing images: $e');
      }
      return null;
    }
  }

  /// Blur/store images on the server (single request) and return both:
  /// - `paths`: server-relative paths (e.g. uploads/car_photos/processed_...jpg)
  /// - `base64`: data URIs (image/jpeg) for immediate local preview without downloading static URLs.
  static Future<Map<String, List<String>>?> processCarImagesToServerPayload(
    List<XFile> imageFiles,
  ) async {
    if (imageFiles.isEmpty) {
      return {'paths': const <String>[], 'base64': const <String>[]};
    }
    final token = await _getAuthToken();
    if (token == null || token.isEmpty) {
      if (kDebugMode) {
        debugPrint('AI Service: Processing requires authentication');
      }
      return null;
    }

    // Batch requests to avoid huge multipart uploads and huge JSON/base64 responses
    // which can cause "connection closed while receiving data" on mobile/dev servers.
    Future<Map<String, List<String>>?> sendBatch(List<XFile> batch) async {
      final url = Uri.parse(
        '${apiBaseApi()}/process-car-images?inline_base64=1',
      );
      final request = http.MultipartRequest('POST', url);
      request.headers['Authorization'] = 'Bearer $token';
      for (final f in batch) {
        request.files.add(await http.MultipartFile.fromPath('images', f.path));
      }
      final streamed = await request.send().timeout(
        const Duration(seconds: 240),
        onTimeout: () => throw TimeoutException('Process images timed out'),
      );
      final response = await http.Response.fromStream(streamed);
      if (response.statusCode != 200) {
        if (kDebugMode) {
          debugPrint(
            'AI Service: Process images failed: ${response.statusCode} ${response.body}',
          );
        }
        return null;
      }
      final data = json.decode(response.body);
      final List<dynamic> pathsDyn =
          (data is Map && data['processed_images'] is List)
          ? (data['processed_images'] as List)
          : const [];
      final List<dynamic> b64Dyn =
          (data is Map && data['processed_images_base64'] is List)
          ? (data['processed_images_base64'] as List)
          : const [];
      final paths = pathsDyn
          .map((e) => e.toString())
          .where((s) => s.trim().isNotEmpty)
          .toList();
      final b64 = b64Dyn
          .map((e) => e.toString())
          .where((s) => s.trim().isNotEmpty)
          .toList();
      return {'paths': paths, 'base64': b64};
    }

    final List<String> outPaths = <String>[];
    final List<String> outB64 = <String>[];
    int batchSize = 3;

    for (int i = 0; i < imageFiles.length; i += batchSize) {
      final batch = imageFiles.sublist(
        i,
        (i + batchSize) > imageFiles.length
            ? imageFiles.length
            : (i + batchSize),
      );
      Map<String, List<String>>? res;

      // Retry per-batch; if still failing, fall back to single-image batches.
      for (int attempt = 0; attempt < 2 && res == null; attempt++) {
        try {
          if (attempt > 0) await Future.delayed(const Duration(seconds: 2));
          res = await sendBatch(batch);
        } catch (e) {
          if (kDebugMode) {
            debugPrint(
              'AI Service: Batch error (size=${batch.length}, attempt=${attempt + 1}): $e',
            );
          }
        }
      }

      if (res == null && batch.length > 1) {
        for (final single in batch) {
          try {
            final one = await sendBatch([single]);
            if (one != null) {
              outPaths.addAll(one['paths'] ?? const []);
              outB64.addAll(one['base64'] ?? const []);
            }
          } catch (e) {
            if (kDebugMode) {
              debugPrint('AI Service: Single-image batch error: $e');
            }
          }
        }
        continue;
      }

      if (res == null) return null;
      outPaths.addAll(res['paths'] ?? const []);
      outB64.addAll(res['base64'] ?? const []);
    }

    return {'paths': outPaths, 'base64': outB64};
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
  static Map<String, double> getConfidenceScores(
    Map<String, dynamic> analysis,
  ) {
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
