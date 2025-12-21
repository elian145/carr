import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'config.dart';
import 'api_service.dart';

class AiService {
  static const String _baseUrl = 'api/analyze-car-image';
  static const String _processApi = 'api/process-car-images-test';
  
  /// Analyze a single car image and extract vehicle information
  static Future<Map<String, dynamic>?> analyzeCarImage(XFile imageFile) async {
    try {
      final url = Uri.parse(apiBase() + '/' + _baseUrl);
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
  
  /// Process multiple images and blur license plates
  static Future<List<XFile>?> processCarImages(List<XFile> imageFiles) async {
    try {
      print('AI Service: Starting image processing for ${imageFiles.length} images');
      
      // Prefer paths first (smaller payload); we will fall back to base64 if downloads fail
      // Prefer accurate multi-pass mode by default to maximize plate detection.
      final noInlineUrl = Uri.parse('${apiBase()}/$_processApi?mode=auto');
      final inlineUrl = Uri.parse('${apiBase()}/$_processApi?inline_base64=1&mode=auto');
      final fallbackInlineUrl = Uri.parse('${apiBase()}/$_processApi?inline_base64=1&fallback_only=1&mode=auto');
      print('AI Service: API Base: ${apiBase()}');
      print('AI Service: Process Images URL: $_processApi');
      print('AI Service: Initial Request URL: $noInlineUrl');
      
      http.MultipartRequest _buildRequest(Uri targetUrl) {
        final req = http.MultipartRequest('POST', targetUrl);
        return req;
      }
      
      // Add authorization header if available
      final token = await _getAuthToken();
      print('AI Service: Auth token: ${token != null ? "Present" : "Not available"}');
      
      print('AI Service: Sending request...');

      // BULK NON-INLINE FIRST: returns server-side paths for instant attach on submit
      http.StreamedResponse? response;
      http.Response? responseBody;
      try {
        final request = http.MultipartRequest('POST', noInlineUrl);
        if (token != null) request.headers['Authorization'] = 'Bearer $token';
        // Avoid emulator keep-alive and streaming quirks
        request.headers['Connection'] = 'close';
        request.headers['Accept-Encoding'] = 'identity';
        for (final imageFile in imageFiles) {
          request.files.add(await http.MultipartFile.fromPath('images', imageFile.path));
        }
        response = await request.send().timeout(
          const Duration(seconds: 120),
          onTimeout: () => throw TimeoutException('AI bulk non-inline timeout after 120s'),
        );
        responseBody = await http.Response.fromStream(response);
      } catch (e) {
        print('AI Service: Bulk non-inline failed, falling back to parallel per-image inline (single attempt): $e');
        // Parallel per-image inline (single attempt each, concurrency=3)
        final int maxConcurrent = 3;
        final List<XFile> parallelOut = List<XFile>.filled(imageFiles.length, XFile(''), growable: false);
        Future<void> processOne(int idx) async {
            try {
              final req = http.MultipartRequest('POST', inlineUrl);
              if (token != null) req.headers['Authorization'] = 'Bearer $token';
              req.headers['Connection'] = 'close';
              req.headers['Accept-Encoding'] = 'identity';
            req.files.add(await http.MultipartFile.fromPath('images', imageFiles[idx].path));
              final resp = await req.send().timeout(
              const Duration(seconds: 60),
              onTimeout: () => throw TimeoutException('AI per-image inline timeout after 60s'),
              );
              final body = await http.Response.fromStream(resp);
              if (resp.statusCode == 200) {
                final data = json.decode(body.body);
                final b64s = (data['processed_images_base64'] is List)
                    ? List<String>.from(data['processed_images_base64'])
                    : <String>[];
                if (b64s.isNotEmpty && b64s[0].startsWith('data:')) {
                  final bytes = base64.decode(b64s[0].split(',').last);
                final out = '${imageFiles[idx].path}_blurred.jpg';
                  await File(out).writeAsBytes(bytes);
                parallelOut[idx] = XFile(out);
                return;
              }
            }
            parallelOut[idx] = imageFiles[idx];
          } catch (_) {
            parallelOut[idx] = imageFiles[idx];
          }
        }
        for (int start = 0; start < imageFiles.length; start += maxConcurrent) {
          final end = (start + maxConcurrent) > imageFiles.length ? imageFiles.length : (start + maxConcurrent);
          final tasks = <Future<void>>[];
          for (int i = start; i < end; i++) {
            tasks.add(processOne(i));
          }
          await Future.wait(tasks);
        }
        return parallelOut;
      }

      print('AI Service: Response status: ${response.statusCode}');
      print('AI Service: Response body: ${responseBody!.body}');
      print('AI Service: Response headers: ${response.headers}');
      
      if (response.statusCode == 200) {
        print('AI Service: Backend processing successful');
        final result = json.decode(responseBody.body);
        final processedImagePaths = List<String>.from(result['processed_images']);
        final processedImagesBase64 = (result['processed_images_base64'] is List)
            ? List<String>.from(result['processed_images_base64'])
            : <String>[];

        // Save server-side paths so submit can attach without re-uploading
        if (processedImagePaths.isNotEmpty) {
          try { ApiService.setLastProcessedServerPaths(processedImagePaths); } catch (_) {}
        }

        // If no base64 returned, process per-image inline with limited concurrency (single attempt).
        if (processedImagesBase64.isEmpty) {
          try {
            print('AI Service: Running per-image inline in parallel (concurrency=3)...');
            final int maxConcurrent = 3;
            final List<XFile> parallelOut = List<XFile>.filled(imageFiles.length, XFile(''), growable: false);

            Future<void> processOne(int idx) async {
              try {
                final req = http.MultipartRequest('POST', inlineUrl);
                if (token != null) req.headers['Authorization'] = 'Bearer $token';
                req.headers['Connection'] = 'close';
                req.headers['Accept-Encoding'] = 'identity';
                req.files.add(await http.MultipartFile.fromPath('images', imageFiles[idx].path));
                final resp = await req.send().timeout(
                  const Duration(seconds: 60),
                  onTimeout: () => throw TimeoutException('AI per-image inline timeout after 60s'),
                );
                final body = await http.Response.fromStream(resp);
                if (resp.statusCode == 200) {
                  final data = json.decode(body.body);
                  final b64s = (data['processed_images_base64'] is List)
                      ? List<String>.from(data['processed_images_base64'])
                      : <String>[];
                  if (b64s.isNotEmpty && b64s[0].startsWith('data:')) {
                    final bytes = base64.decode(b64s[0].split(',').last);
                    final out = '${imageFiles[idx].path}_blurred.jpg';
                    await File(out).writeAsBytes(bytes);
                    parallelOut[idx] = XFile(out);
                    return;
                  }
                }
                // Fallback to original if inline not returned
                parallelOut[idx] = imageFiles[idx];
              } catch (_) {
                parallelOut[idx] = imageFiles[idx];
              }
            }

            for (int start = 0; start < imageFiles.length; start += maxConcurrent) {
              final end = (start + maxConcurrent) > imageFiles.length ? imageFiles.length : (start + maxConcurrent);
              final tasks = <Future<void>>[];
              for (int i = start; i < end; i++) {
                tasks.add(processOne(i));
              }
              await Future.wait(tasks);
            }

            print('AI Service: Parallel inline completed. Returning ${parallelOut.length} images.');
            return parallelOut;
          } catch (e) {
            print('AI Service: Parallel per-image inline failed: $e');
          }

          // As a final step before giving up, try downloading server-processed images by path
          try {
            if (processedImagePaths.isNotEmpty) {
              print('AI Service: Attempting to download processed images by path...');
              final tmpDir = await getTemporaryDirectory();
              final List<XFile> downloaded = <XFile>[];
              for (int i = 0; i < processedImagePaths.length && i < imageFiles.length; i++) {
                final rel = processedImagePaths[i];
                final url = Uri.parse('${apiBase()}/static/${rel.startsWith('/') ? rel.substring(1) : rel}');
                final resp = await http.get(url);
                if (resp.statusCode == 200 && resp.bodyBytes.isNotEmpty) {
                  final base = p.basename(imageFiles[i].path);
                  final outPath = p.join(tmpDir.path, '${base}_blurred.jpg');
                  final f = File(outPath);
                  await f.writeAsBytes(resp.bodyBytes);
                  downloaded.add(XFile(outPath));
                } else {
                  downloaded.add(imageFiles[i]); // fallback to original on failure
                }
              }
              // If lengths mismatch, append originals for the rest
              for (int i = downloaded.length; i < imageFiles.length; i++) {
                downloaded.add(imageFiles[i]);
              }
              if (downloaded.isNotEmpty) {
                print('AI Service: Downloaded ${downloaded.length} processed images by path.');
                return downloaded;
              }
            }
          } catch (e) {
            print('AI Service: Download-by-path fallback failed: $e');
          }
        }

        // Fast-path: if inline base64 is present, decode and return immediately
        if (processedImagesBase64.isNotEmpty) {
          final List<XFile> inlineFiles = <XFile>[];
          final int m = processedImagesBase64.length < imageFiles.length
              ? processedImagesBase64.length
              : imageFiles.length;
          for (int i = 0; i < m; i++) {
            final b64 = processedImagesBase64[i];
            if (b64.startsWith('data:')) {
              try {
                final base64Data = b64.split(',').last;
                final bytes = base64.decode(base64Data);
                final processedImagePath = '${imageFiles[i].path}_blurred.jpg';
                final file = File(processedImagePath);
                await file.writeAsBytes(bytes);
                inlineFiles.add(XFile(processedImagePath));
              } catch (e) {
                // If a single decode fails, fall back to original for that index
                inlineFiles.add(imageFiles[i]);
              }
            } else {
              inlineFiles.add(imageFiles[i]);
            }
          }
          // If there are more originals than returned base64 entries, append originals for the remainder
          for (int i = m; i < imageFiles.length; i++) {
            inlineFiles.add(imageFiles[i]);
          }
          print('AI Service: Returned ${inlineFiles.length} images from inline base64 fast-path');
          return inlineFiles;
        }
        
        // If we got here without base64, return originals (no extra processing).
        print('AI Service: No inline base64 available; returning originals.');
        return imageFiles;
      } else {
        print('AI Service: Image processing failed: ${response.statusCode} - ${responseBody.body}');
        // Try to parse error message
        try {
          final errorData = json.decode(responseBody.body);
          print('AI Service Error Details: ${errorData['error'] ?? 'Unknown error'}');
        } catch (e) {
          print('AI Service Raw Error: ${responseBody.body}');
        }
        return null;
      }
    } catch (e) {
      print('AI Service: Error processing car images: $e');
      print('AI Service: Error type: ${e.runtimeType}');
      if (e.toString().contains('SocketException')) {
        print('AI Service: Network error - check if backend is running');
      }
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
