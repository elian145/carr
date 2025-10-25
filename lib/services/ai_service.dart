import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'config.dart';
import 'api_service.dart';

class AiService {
  static const String _baseUrl = 'api/analyze-car-image';
  static const String _processImagesUrl = 'api/process-car-images-test';
  
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
      
      final url = Uri.parse(apiBase() + '/' + _processImagesUrl + '?inline_base64=1');
      print('AI Service: API Base: ${apiBase()}');
      print('AI Service: Process Images URL: $_processImagesUrl');
      print('AI Service: Request URL: $url');
      
      final request = http.MultipartRequest('POST', url);
      
      // Add authorization header if available
      final token = await _getAuthToken();
      print('AI Service: Auth token: ${token != null ? "Present" : "Not available"}');
      
      if (token != null) {
        request.headers['Authorization'] = 'Bearer $token';
      }
      
      // Add image files
      for (final imageFile in imageFiles) {
        print('AI Service: Adding image: ${imageFile.path}');
        request.files.add(await http.MultipartFile.fromPath('images', imageFile.path));
      }
      
      print('AI Service: Sending request...');
      // Send with retry and a longer timeout
      http.StreamedResponse? response;
      http.Response? responseBody;
      String? lastError;
      for (int attempt = 1; attempt <= 3; attempt++) {
        try {
          response = await request.send().timeout(
            Duration(seconds: 90),
            onTimeout: () {
              throw TimeoutException('AI upload timeout after 90s');
            },
          );
          responseBody = await http.Response.fromStream(response);
          lastError = null;
          break;
        } catch (e) {
          print('AI Service: Upload attempt $attempt failed: $e');
          lastError = e.toString();
          if (attempt < 3) {
            await Future.delayed(Duration(seconds: attempt));
          }
        }
      }
      if (lastError != null || response == null) {
        print('AI Service: Error processing car images (inline_base64=1): ${lastError ?? 'Unknown error'}');
        print('AI Service: Falling back to inline_base64=0...');
        
        // Build a new request without base64 to reduce payload size
        final fallbackUrl = Uri.parse(apiBase() + '/' + _processImagesUrl);
        final fallbackRequest = http.MultipartRequest('POST', fallbackUrl);
        if (token != null) {
          fallbackRequest.headers['Authorization'] = 'Bearer $token';
        }
        for (final imageFile in imageFiles) {
          fallbackRequest.files.add(await http.MultipartFile.fromPath('images', imageFile.path));
        }
        
        http.StreamedResponse? fbResp;
        http.Response? fbBody;
        String? fbErr;
        for (int attempt = 1; attempt <= 3; attempt++) {
          try {
            fbResp = await fallbackRequest.send().timeout(
              Duration(seconds: 90),
              onTimeout: () => throw TimeoutException('AI upload timeout after 90s (fallback)'),
            );
            fbBody = await http.Response.fromStream(fbResp);
            fbErr = null;
            break;
          } catch (e) {
            print('AI Service: Fallback upload attempt $attempt failed: $e');
            fbErr = e.toString();
            if (attempt < 3) {
              await Future.delayed(Duration(seconds: attempt));
            }
          }
        }
        if (fbErr != null || fbResp == null) {
          print('AI Service: Fallback error processing car images: ${fbErr ?? 'Unknown error'}');
          return null;
        }
        response = fbResp;
        responseBody = fbBody;
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
        
        // Build a map processedPath -> base64 (aligned by index with processedImagePaths)
        final Map<String, String> pathToBase64 = {};
        if (processedImagesBase64.isNotEmpty && processedImagesBase64.length == processedImagePaths.length) {
          for (int i = 0; i < processedImagePaths.length; i++) {
            pathToBase64[processedImagePaths[i]] = processedImagesBase64[i];
          }
        }
        print('AI Service: Successfully processed ${processedImagePaths.length} images');
        
        // Download the processed images and return them as XFile objects
        // Create a map to match processed images to original images by filename
        final processedImages = <XFile>[];
        final processedFilenameMap = <String, String>{};
        
        // Build a map of processed filenames to their paths
        for (final processedPath in processedImagePaths) {
          // Extract original filename from processed path
          // Format: "uploads/car_photos/processed_YYYYMMDD_HHMMSS_original.jpg"
          final filename = processedPath.split('/').last;
          // Remove "processed_TIMESTAMP_" prefix to get original filename (case-insensitive)
          final originalFilename = filename.replaceFirst(RegExp(r'processed_\d{8}_\d{6}_', caseSensitive: false), '');
          processedFilenameMap[originalFilename.toLowerCase()] = processedPath;
          print('AI Service: Mapped ${originalFilename.toLowerCase()} -> $processedPath');
        }
        
        // We will consult pathToBase64 per processed path, if present
        
        // Process each original image in order
        for (int i = 0; i < imageFiles.length; i++) {
          try {
            final originalFile = imageFiles[i];
            // Use cross-platform filename extraction
            final originalFilename = p.basename(originalFile.path);
            final originalFilenameKey = originalFilename.toLowerCase();
            
            // Check if this image was processed
            // Prefer index-aligned base64 when lengths match (most robust)
            String? inlineB64ForThis;
            if (processedImagesBase64.isNotEmpty && processedImagesBase64.length == imageFiles.length) {
              inlineB64ForThis = processedImagesBase64[i];
            }

            final processedPath = processedFilenameMap[originalFilenameKey];
            
            if (processedPath == null && inlineB64ForThis == null) {
              print('AI Service: No processed version for $originalFilename, using original');
              processedImages.add(originalFile);
              continue;
            }
            
            // If base64 for this processed path is present, use it directly
            final b64 = inlineB64ForThis ?? (processedPath != null ? pathToBase64[processedPath] : null);
            if (b64 != null && b64.startsWith('data:')) {
              try {
                final base64Data = b64.split(',').last;
                final bytes = base64.decode(base64Data);
                final processedImagePath = '${originalFile.path}_blurred.jpg';
                final file = File(processedImagePath);
                await file.writeAsBytes(bytes);
                processedImages.add(XFile(processedImagePath));
                print('AI Service: Wrote base64 image to: $processedImagePath (${bytes.length} bytes)');
                continue;
              } catch (e) {
                print('AI Service: Failed to write base64 image for index $i: $e');
                // Fall through to HTTP download
              }
            }

            // Construct the full URL to access the processed image
            final imageUrl = processedPath != null ? '${apiBase()}/static/$processedPath' : '';
            print('AI Service: Downloading processed image from: $imageUrl');
            print('AI Service: Processed path: $processedPath');
            
            // Retry logic for failed downloads (increased to 5 attempts with longer delays)
            http.Response? imageResponse;
            bool downloadSuccess = false;
            
            for (int retry = 0; retry < 5; retry++) {
              try {
                // Try using a client with a longer timeout for larger files
                final client = http.Client();
                try {
                  final request = http.Request('GET', Uri.parse(imageUrl));
                  // Increase timeout to 60 seconds for large files
                  final streamedResponse = await client.send(request).timeout(
                    Duration(seconds: 60),
                    onTimeout: () {
                      throw TimeoutException('Download timeout after 60 seconds');
                    },
                  );
                  
                  if (streamedResponse.statusCode == 200) {
                    // Read the response as bytes with streaming and timeout
                    final bytes = await streamedResponse.stream.toBytes().timeout(
                      Duration(seconds: 60),
                      onTimeout: () {
                        throw TimeoutException('Stream read timeout after 60 seconds');
                      },
                    );
                    imageResponse = http.Response.bytes(bytes, streamedResponse.statusCode);
                    downloadSuccess = true;
                    print('AI Service: Successfully downloaded ${bytes.length} bytes');
                    break; // Success, exit retry loop
                  } else {
                    print('AI Service: Download failed with status: ${streamedResponse.statusCode}');
                  }
                } finally {
                  client.close();
                }
              } catch (e) {
                print('AI Service: Download attempt ${retry + 1} failed: $e');
                if (retry < 4) {
                  // Exponential backoff: 1s, 2s, 3s, 4s
                  await Future.delayed(Duration(seconds: retry + 1));
                }
              }
            }
            
            if (!downloadSuccess || imageResponse == null) {
              print('AI Service: All download attempts failed for $originalFilename, attempting per-image inline fallback...');
              // Per-image inline fallback: reprocess just this image with inline_base64=1
              try {
                final singleUrl = Uri.parse(apiBase() + '/' + _processImagesUrl + '?inline_base64=1');
                final singleReq = http.MultipartRequest('POST', singleUrl);
                if (token != null) {
                  singleReq.headers['Authorization'] = 'Bearer $token';
                }
                singleReq.files.add(await http.MultipartFile.fromPath('images', originalFile.path));
                final singleResp = await singleReq.send().timeout(
                  Duration(seconds: 90),
                  onTimeout: () => throw TimeoutException('AI single upload timeout after 90s'),
                );
                final singleBody = await http.Response.fromStream(singleResp);
                if (singleResp.statusCode == 200) {
                  final singleData = json.decode(singleBody.body);
                  final singlesB64 = (singleData['processed_images_base64'] is List)
                      ? List<String>.from(singleData['processed_images_base64'])
                      : <String>[];
                  if (singlesB64.isNotEmpty && singlesB64[0].startsWith('data:')) {
                    final base64Data = singlesB64[0].split(',').last;
                    final bytes = base64.decode(base64Data);
                    final processedImagePath = '${originalFile.path}_blurred.jpg';
                    final file = File(processedImagePath);
                    await file.writeAsBytes(bytes);
                    processedImages.add(XFile(processedImagePath));
                    print('AI Service: Per-image inline fallback succeeded for $originalFilename');
                    continue;
                  }
                }
                // If inline base64 still not provided, fall back to original
                print('AI Service: Per-image inline fallback did not return base64 for $originalFilename; using original');
                processedImages.add(originalFile);
                continue;
              } catch (e) {
                print('AI Service: Per-image inline fallback failed for $originalFilename: $e');
                processedImages.add(originalFile);
                continue;
              }
            }
            
            print('AI Service: Download response status: ${imageResponse.statusCode}');
            
            if (imageResponse.statusCode == 200) {
              // Save the processed image locally
              final processedImagePath = '${imageFiles[i].path}_blurred.jpg';
              final file = File(processedImagePath);
              await file.writeAsBytes(imageResponse.bodyBytes);
              processedImages.add(XFile(processedImagePath));
              print('AI Service: Downloaded processed image to: $processedImagePath');
              print('AI Service: File size: ${imageResponse.bodyBytes.length} bytes');
              print('AI Service: File exists: ${await file.exists()}');
              print('AI Service: XFile path: ${XFile(processedImagePath).path}');
              
              // Compare with original file size
              final originalFile = File(imageFiles[i].path);
              if (await originalFile.exists()) {
                final originalSize = await originalFile.length();
                print('AI Service: Original file size: $originalSize bytes');
                print('AI Service: Processed file size: ${imageResponse.bodyBytes.length} bytes');
                if (originalSize != imageResponse.bodyBytes.length) {
                  print('AI Service: SUCCESS - File sizes different, blurring applied!');
                } else {
                  print('AI Service: WARNING - File sizes same, may not be blurred');
                }
              }
            } else {
              print('AI Service: Failed to download processed image: ${imageResponse.statusCode}');
              print('AI Service: Response body: ${imageResponse.body}');
              // Fallback to original image
              processedImages.add(imageFiles[i]);
            }
          } catch (e) {
            print('AI Service: Error downloading processed image: $e');
            // Fallback to original image
            processedImages.add(imageFiles[i]);
          }
        }
        
        return processedImages;
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
    // Get auth token from ApiService
    await ApiService.initializeTokens();
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
