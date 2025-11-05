// lib/services/firestore_image_service.dart

import 'dart:async';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:study_assistance/api/api_service.dart';
import 'package:http/http.dart' as http;

// --- THIS IS THE CORRECTED CUSTOM FILE SERVICE ---
class FirestoreFileService extends FileService {
  final ApiService _apiService;
  final String _projectId;

  FirestoreFileService(this._apiService, this._projectId);

  @override
  Future<FileServiceResponse> get(String url, {Map<String, String>? headers}) async {
    // We only want to handle our custom URLs.
    if (url.startsWith('firestore_media:')) {
      final mediaId = url.substring('firestore_media:'.length);

      try {
        final bytes = await _apiService.getMediaBytes(mediaId, _projectId);
        if (bytes != null) {
          // --- THIS IS THE CORRECT IMPLEMENTATION ---
          // The cache manager expects a response that simulates an HTTP response.
          // We can create one manually using http.StreamedResponse.
          final response = http.StreamedResponse(
            Stream.value(bytes),
            200, // HTTP OK
            contentLength: bytes.length,
            headers: {'content-type': 'image/jpeg'}, // Assume JPEG
          );

          // Wrap it in HttpGetResponse, which is the concrete implementation
          // of FileServiceResponse that the cache manager understands for HTTP.
          return HttpGetResponse(response);
        } else {
          // If bytes are null (e.g., API returned 404), throw an error.
          throw Exception('Image not found from API');
        }
      } catch (e) {
        print("Error in FirestoreFileService get: $e");
        // Re-throw the error to be caught by the cache manager
        rethrow;
      }
    } else {
      // For ANY other URL (http, https, etc.), let the default service handle it.
      // This is the crucial part that was broken before.
      return HttpFileService().get(url, headers: headers);
    }
  }
}


// --- THIS CACHE MANAGER CLASS REMAINS THE SAME ---
class FirestoreImageCacheManager extends CacheManager with ImageCacheManager {
  static const key = 'firestoreImageCache';
  
  // Note: Removed the singleton instance to make it simpler and avoid state issues.
  // We will create a new instance where needed.

  factory FirestoreImageCacheManager({
    required ApiService apiService,
    required String projectId,
  }) {
    return FirestoreImageCacheManager._internal(
      Config(
        key,
        fileService: FirestoreFileService(apiService, projectId),
        stalePeriod: const Duration(days: 7),
      ),
    );
  }

  FirestoreImageCacheManager._internal(super.config);
}