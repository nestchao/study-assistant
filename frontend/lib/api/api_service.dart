// lib/api/api_service.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:file_picker/file_picker.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class ApiService {
  late final String baseUrl;

  ApiService() {
    baseUrl = dotenv.env['API_URL'] ?? 'http://10.0.2.2:5000';
  }

  // GET /api/get-projects
  Future<List<Map<String, dynamic>>> getProjects() async {
    final response = await http.get(Uri.parse('$baseUrl/get-projects'));
    return List<Map<String, dynamic>>.from(json.decode(response.body));
  }

  // POST /api/create-project
  Future<void> createProject(String name) async {
    await http.post(
      Uri.parse('$baseUrl/create-project'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'name': name}),
    );
  }

  // GET /api/get-sources/<project_id>
  Future<List<Map<String, dynamic>>> getSources(String projectId) async {
    final response = await http.get(Uri.parse('$baseUrl/get-sources/$projectId'));
    return List<Map<String, dynamic>>.from(json.decode(response.body));
  }

  // POST /api/upload-source/<project_id>
  // In your ApiService class, update uploadSources:
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

  // ADD THIS METHOD
  Future<Map<String, dynamic>> hello() async {
    final response = await http.get(Uri.parse('$baseUrl/api/hello'));
    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      return {"message": "Backend offline"};
    }
  }
}