// lib/api/api_service.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:file_picker/file_picker.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:typed_data';

class ApiService {
  late final String baseUrl;

  ApiService() {
    if (kIsWeb) {
      // If we are on the web, ALWAYS use localhost. The browser will handle it.
      baseUrl = 'http://localhost:5000';
    } else {
      // For mobile (Android/iOS), read the IP from the .env file.
      // Provide a fallback for the emulator just in case.
      baseUrl = dotenv.env['API_URL'] ?? 'http://10.0.2.2:5000';
    }

    print("!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!");
    print("Platform: ${kIsWeb ? 'Web' : 'Mobile'}");
    print("ApiService initialized with baseUrl: $baseUrl");
    print("!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!");
  }

  // GET /api/get-projects
  Future<List<Map<String, dynamic>>> getProjects() async {
    final response = await http.get(Uri.parse('$baseUrl/get-projects'));
    return List<Map<String, dynamic>>.from(json.decode(response.body));
  }

  // POST /api/create-project
  Future<void> createProject(String name) async {
    final headers = await _getHeaders();
    await http.post(
      Uri.parse('$baseUrl/create-project'),
      headers: headers, // <-- USE THE NEW HEADERS
      body: json.encode({'name': name}),
    );
  }

  // --- NEW ---
  Future<void> renameProject(String projectId, String newName) async {
    final response = await http.put(
      Uri.parse('$baseUrl/rename-project/$projectId'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'new_name': newName}),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to rename project');
    }
  }

  Future<void> deleteProject(String projectId) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/delete-project/$projectId'),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to delete project');
    }
  }
  
  // --- NEW ---
  Future<void> deleteSource(String projectId, String sourceId) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/delete-source/$projectId/$sourceId'),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to delete source');
    }
  }

  // GET /api/get-sources/<project_id>
  Future<List<Map<String, dynamic>>> getSources(String projectId) async {
    final response = await http.get(Uri.parse('$baseUrl/get-sources/$projectId'));
    return List<Map<String, dynamic>>.from(json.decode(response.body));
  }

  // POST /api/upload-source/<project_id>
  Future<void> uploadSources(String projectId, List<PlatformFile> files) async {
    print("📤 Uploading ${files.length} files to project $projectId");
    
    var request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/upload-source/$projectId'),
    );

    for (var file in files) {
      print("  Adding file: ${file.name} (${file.size} bytes)");
      
      if (file.bytes != null) {
        request.files.add(http.MultipartFile.fromBytes(
          'pdfs',  // ⚠️  MUST match Flask route's request.files.getlist('pdfs')
          file.bytes!,
          filename: file.name,
        ));
      }
    }

    print("  Sending request...");
    var response = await request.send();
    var responseBody = await response.stream.bytesToString();
    
    print("  Response status: ${response.statusCode}");
    print("  Response body: $responseBody");

    if (response.statusCode != 200) {
      throw Exception('Upload failed: $responseBody');
    }
  }

  // GET /api/get-note/<project_id>/<source_id>
  Future<String> getNote(String projectId, String sourceId) async {
    final response = await http.get(Uri.parse('$baseUrl/get-note/$projectId/$sourceId'));
    return json.decode(response.body)['note_html'] ?? '<p>No note</p>';
  }

  // POST /api/generate-topic-note/<project_id>
  Future<String> generateTopicNote(String projectId, String topic) async {
    final response = await http.post(
      Uri.parse('$baseUrl/generate-topic-note/$projectId'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'topic': topic}),
    );
    return json.decode(response.body)['note_html'] ?? '<p>Failed</p>';
  }

  // POST /api/ask-chatbot/<project_id>
  Future<String> askChatbot(String projectId, String question,
      {String? sourceId, List<Map<String, dynamic>>? history}) async {
    final response = await http.post(
      Uri.parse('$baseUrl/ask-chatbot/$projectId'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        'question': question,
        'source_id': sourceId,
        'history': history ?? [],
      }),
    );
    return json.decode(response.body)['answer'] ?? 'No response';
  }

  // GET /api/hello
  Future<Map<String, dynamic>> hello() async {
    final response = await http.get(Uri.parse('$baseUrl/api/hello'));
    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      return {"message": "Backend offline"};
    }
  }

  Future<String?> uploadImageBytes(String projectId, Uint8List imageBytes, String fileName) async {
    final String base64Image = base64Encode(imageBytes);

    final response = await http.post(
      Uri.parse('$baseUrl/media/upload'),
      headers: {
        'Content-Type': 'application/json',
        'X-User-ID': projectId, // Using projectId as a stand-in for user ID
      },
      body: json.encode({
        'content': base64Image,
        'fileName': fileName,
        'type': 'image',
      }),
    );

    if (response.statusCode == 201) {
      return json.decode(response.body)['mediaId'];
    }
    return null;
  }

  Future<Uint8List?> getMediaBytes(String mediaId, String projectId) async {
    final response = await http.get(
      Uri.parse('$baseUrl/media/get/$mediaId'),
      headers: { 'X-User-ID': projectId },
    );

    if (response.statusCode == 200) {
      // THIS IS CORRECT: Return the raw bytes of the response body.
      return response.bodyBytes;
    }

    print("Failed to get media bytes: ${response.statusCode}");
    return null;
  }

  Future<bool> updateNote(String projectId, String sourceId, String newHtmlContent) async {
    final response = await http.post(
      Uri.parse('$baseUrl/update-note/$projectId/$sourceId'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'html_content': newHtmlContent}),
    );
    
    if (response.statusCode == 200) {
      return true;
    } else {
      print("Failed to update note: ${response.body}");
      return false;
    }
  }

  // --- NEW: Get Past Papers ---
  Future<List<Map<String, dynamic>>> getPastPapers(String projectId) async {
    final response = await http.get(Uri.parse('$baseUrl/get-papers/$projectId'));
    if (response.statusCode == 200) {
      return List<Map<String, dynamic>>.from(json.decode(response.body));
    } else {
      throw Exception('Failed to load past papers');
    }
  }

  // --- NEW: Upload Past Paper ---
  Future<Map<String, dynamic>> uploadPastPaper(String projectId, PlatformFile file) async {
    var request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/upload-paper/$projectId'),
    );

    if (file.bytes != null) {
      request.files.add(http.MultipartFile.fromBytes(
        'file', // MUST match Flask's request.files['file']
        file.bytes!,
        filename: file.name,
      ));
    } else {
      throw Exception('File bytes are null');
    }

    var response = await request.send();
    var responseBody = await response.stream.bytesToString();
    var decodedBody = json.decode(responseBody);

    if (response.statusCode == 200) {
      return decodedBody;
    } else {
      throw Exception(decodedBody['error'] ?? 'Failed to upload and process paper');
    }
  }

  Future<List<Map<String, dynamic>>> getSyncConfigs() async {
  final response = await http.get(Uri.parse('$baseUrl/sync/configs'));
  if (response.statusCode == 200) {
    return List<Map<String, dynamic>>.from(json.decode(response.body));
  }
  throw Exception('Failed to load sync configs');
}

  Future<String> registerSyncConfig(String projectId, String path, List<String> extensions) async {
    final response = await http.post(
      Uri.parse('$baseUrl/sync/register'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        'project_id': projectId,
        'local_path': path,
        'extensions': extensions,
      }),
    );
    if (response.statusCode == 201) {
      return json.decode(response.body)['config_id'];
    }
    throw Exception('Failed to register sync config');
  }

  Future<void> updateSyncConfig(String configId, {bool? isActive, List<String>? extensions}) async {
    final Map<String, dynamic> body = {};
    if (isActive != null) body['is_active'] = isActive;
    if (extensions != null) body['allowed_extensions'] = extensions;

    final response = await http.put(
      Uri.parse('$baseUrl/sync/config/$configId'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode(body),
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to update sync config');
    }
  }

  Future<void> deleteSyncConfig(String configId) async {
    final response = await http.delete(Uri.parse('$baseUrl/sync/config/$configId'));
    if (response.statusCode != 200) {
      throw Exception('Failed to delete sync config');
    }
  }

  Future<Map<String, dynamic>> runSync(String configId) async {
    final response = await http.post(Uri.parse('$baseUrl/sync/run/$configId'));
    if (response.statusCode == 200) {
      return json.decode(response.body);
    }
    throw Exception('Failed to run sync');
  }


  // --- CODE CONVERTER METHODS ---

  Future<Map<String, dynamic>> getProjectFileStructure(String projectId) async {
    final response = await http.get(Uri.parse('$baseUrl/code-converter/structure/$projectId'));
    if (response.statusCode == 200) {
      return json.decode(response.body);
    }
    throw Exception('Failed to get project structure');
  }

  Future<String> getFileContent(String projectId, String docId) async {
    // Call the new, correct endpoint
    final response = await http.get(Uri.parse('$baseUrl/code-converter/file/$projectId/$docId'));
    
    if (response.statusCode == 200) {
      // The backend returns JSON: {"content": "...", "original_path": "..."}
      final data = json.decode(response.body);
      return data['content'] ?? 'Error: Content field missing in response.';
    }
    
    print("Failed to get file content, Status: ${response.statusCode}, Body: ${response.body}");
    throw Exception('Failed to get file content');
  }

  Future<Map<String, String>> _getHeaders() async {
    final user = FirebaseAuth.instance.currentUser;
    String? token;
    if (user != null) {
      // Get the Firebase ID token for the current user.
      token = await user.getIdToken();
    }
    
    return {
      'Content-Type': 'application/json',
      // Send the token in the standard 'Authorization' header
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }
}