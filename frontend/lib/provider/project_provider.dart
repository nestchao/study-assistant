// frontend/lib/provider/project_provider.dart

import 'dart:convert';
import 'dart:developer';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:study_assistance/api/api_service.dart';
import 'package:study_assistance/models/project.dart';
import 'dart:convert'; // Import
import 'dart:typed_data'; // Import
import 'package:image_picker/image_picker.dart';

// Your Source and ChatMessage classes remain the same
class Source {
  final String id;
  final String filename;
  Source({required this.id, required this.filename});
}

class ChatMessage {
  final String content;
  final bool isUser;
  ChatMessage({required this.content, required this.isUser});
}

class ProjectProvider with ChangeNotifier {
  final ApiService _api = ApiService();

  // Controllers
  final projectNameController = TextEditingController();
  final chatController = TextEditingController();
  final topicController = TextEditingController();
  final ImagePicker _picker = ImagePicker();

  final Map<String, Uint8List> _mediaCache = {};

  Future<Uint8List?> getCachedMediaBytes(String mediaId) async {
    // 1. Check if the image is already in the cache.
    if (_mediaCache.containsKey(mediaId)) {
      print("CACHE HIT for mediaId: $mediaId");
      // If yes, return it instantly from memory.
      return _mediaCache[mediaId];
    }

    // 2. If not in the cache, fetch it from the backend.
    print("CACHE MISS for mediaId: $mediaId. Fetching from network...");
    if (_currentProject == null) return null;
    
    final imageBytes = await _api.getMediaBytes(mediaId, _currentProject!.id);

    // 3. If the download was successful...
    if (imageBytes != null) {
      print("...fetched successfully. Storing in cache.");
      // ...store the data in the cache for next time.
      _mediaCache[mediaId] = imageBytes;
    }

    // 4. Return the newly fetched data.
    return imageBytes;
  }

  bool _isSavingNote = false;
  bool get isSavingNote => _isSavingNote;

  void updateScratchpadContent(String newContent) {
    _scratchpadContent = newContent;
    notifyListeners();
  }

  Future<bool> saveNoteChanges(String newHtmlContent) async {
    if (_currentProject == null || _selectedSource == null) {
      return false;
    }
    
    _isSavingNote = true;
    notifyListeners();

    try {
      final success = await _api.updateNote(
        _currentProject!.id,
        _selectedSource!.id,
        newHtmlContent,
      );
      
      if (success) {
        // If saving was successful, update the local state to match.
        _scratchpadContent = newHtmlContent;
      }
      return success;

    } catch (e) {
      print("Error in saveNoteChanges: $e");
      return false;
    } finally {
      _isSavingNote = false;
      notifyListeners();
    }
  }

  ApiService get apiService => _api;

  // NEW: Add a constructor to load from cache immediately
  ProjectProvider() {
    _loadProjectsFromCache();
    // Start fetching from the API immediately after loading cache
    fetchProjects();
  }

  @override
  void dispose() {
    projectNameController.dispose();
    chatController.dispose();
    topicController.dispose();
    super.dispose();
  }

  // State
  List<Project> _projects = [];
  bool _isLoadingProjects = false;
  List<Project> get projects => _projects;
  bool get isLoadingProjects => _isLoadingProjects;

  Project? _currentProject;
  Project? get currentProject => _currentProject;

  List<Source> _sources = [];
  List<Source> get sources => _sources;
  bool _isLoadingSources = false;
  bool get isLoadingSources => _isLoadingSources;
  bool _isUploading = false;
  bool get isUploading => _isUploading;

  Source? _selectedSource;
  Source? get selectedSource => _selectedSource;

  String _scratchpadContent =
      "<p>Select a source and click 'Show Source Note'.</p>";
  String get scratchpadContent => _scratchpadContent;
  bool _isLoadingNote = false;
  bool get isLoadingNote => _isLoadingNote;

  List<ChatMessage> _chatHistory = [
    ChatMessage(content: "Hello! Ask a question to get started.", isUser: false)
  ];
  List<ChatMessage> get chatHistory => _chatHistory;
  bool _isBotThinking = false;
  bool get isBotThinking => _isBotThinking;

  // Add a state variable to track the ID of the project being deleted.
  String? _deletingProjectId;
  String? get deletingProjectId => _deletingProjectId;

  // --- NEW CACHING LOGIC ---

  Future<void> _loadProjectsFromCache() async {
    final prefs = await SharedPreferences.getInstance();
    final String? projectsJson = prefs.getString('cached_projects');

    if (projectsJson != null) {
      final List<dynamic> projectList = jsonDecode(projectsJson);
      _projects = projectList.map((map) => Project.fromMap(map)).toList();
      print("✅ Loaded ${_projects.length} projects from cache.");
      notifyListeners(); // Show cached data on the UI immediately
    }
  }

  Future<void> _saveProjectsToCache() async {
    final prefs = await SharedPreferences.getInstance();
    final List<Map<String, dynamic>> projectList =
        _projects.map((p) => p.toMap()).toList();
    await prefs.setString('cached_projects', jsonEncode(projectList));
    print("💾 Saved ${_projects.length} projects to cache.");
  }

  // --- UPDATED DATA FETCHING METHODS ---

  /// Fetches projects from the API.
  /// If `forceRefresh` is false, it won't fetch if a list is already present
  /// and not loading (this is mostly for the constructor call).
  Future<void> fetchProjects({bool forceRefresh = false}) async {
    // Prevent simultaneous fetches or redundant fetches if not forcing a refresh
    if (_isLoadingProjects) return;

    // Only prevent fetch if we have data AND we are not forcing a refresh
    if (_projects.isNotEmpty && !forceRefresh) {
      // If we have data, we assume it came from cache, so we still start loading
      // to refresh it in the background, but we don't return here.
    }
    
    _isLoadingProjects = true;
    // Only show the full-screen loading spinner if the cache was empty
    if (_projects.isEmpty || forceRefresh) {
      notifyListeners();
    }

    try {
      final data = await _api.getProjects();
      final newProjects = data.map((map) => Project.fromMap(map)).toList();
      
      // Only update and save if the data actually changed
      if (jsonEncode(newProjects.map((p) => p.toMap()).toList()) != jsonEncode(_projects.map((p) => p.toMap()).toList())) {
          _projects = newProjects;
          await _saveProjectsToCache(); // Save fresh data to cache
      }
    } catch (e) {
      print("Error fetching projects: $e");
      // If fetching fails, we keep the cached list, but still need to stop loading.
    } finally {
      _isLoadingProjects = false;
      notifyListeners();
    }
  }

  // UPDATED: Now refreshes the project list and saves to cache
  Future<void> createProject(String name) async {
    if (name.isEmpty) return;
    try {
      await _api.createProject(name);
      // Force a refresh to get the new project from the server and update cache
      await fetchProjects(forceRefresh: true);
    } catch (e) {
      print("Error creating project: $e");
    }
  }

  // UPDATED: Now updates the cache after deleting
  Future<void> deleteProject(String projectId) async {
    _deletingProjectId = projectId;
    notifyListeners(); // Tell the UI to show a loading indicator for this project

    try {
      await _api.deleteProject(projectId); // Call the API
      _projects.removeWhere((project) => project.id == projectId); // Remove from local list
      await _saveProjectsToCache(); // Update the cache
    } catch (e) {
      print("Error deleting project: $e");
      // Re-throw the error so the UI can catch it and show a message
      rethrow;
    } finally {
      // This block runs whether the deletion succeeded or failed.
      _deletingProjectId = null;
      notifyListeners(); // Tell the UI to remove the loading indicator
    }
  }

  // --- REST OF YOUR METHODS (Unchanged functionality) ---

  void setCurrentProject(Project project) {
    _currentProject = project;
    _sources = [];
    _selectedSource = null;
    _chatHistory = [
      ChatMessage(content: "Hello! Ask a question to get started.", isUser: false)
    ];
    _scratchpadContent = "<p>Select a source and click 'Show Source Note'.</p>";
    _mediaCache.clear();
    fetchSources();
    notifyListeners();
  }

  Future<void> fetchSources() async {
    if (_currentProject == null) return;
    _isLoadingSources = true;
    notifyListeners();
    try {
      final data = await _api.getSources(_currentProject!.id);
      _sources = data
          .map((s) => Source(id: s['id'], filename: s['filename']))
          .toList();
    } catch (e) {
      // print("Error fetching sources: $e");
    }
    _isLoadingSources = false;
    notifyListeners();
  }

  Future<void> pickAndUploadFiles() async {
    if (_currentProject == null) return;
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      allowMultiple: true,
    );

    if (result != null) {
      _isUploading = true;
      notifyListeners();
      try {
        await _api.uploadSources(_currentProject!.id, result.files);
        await fetchSources();
        notifyListeners();
        log("Uploading...");
      } catch (e) {
        // print("Upload error: $e");
      }
      _isUploading = false;
      notifyListeners();
    }
  }

  void selectSource(Source? source) {
    if (_selectedSource?.id == source?.id) return;
    _selectedSource = source;
    if (source == null) {
      _chatHistory.add(ChatMessage(
        content: "You are now chatting with all sources.",
        isUser: false,
      ));
    } else {
      _chatHistory.add(ChatMessage(
        content: "📄 Conversation started for <b>${source.filename}</b>",
        isUser: false,
      ));
      getNoteForSelectedSource();
    }
    notifyListeners();
  }

  Future<void> getNoteForSelectedSource() async {
    if (_currentProject == null || _selectedSource == null) return;
    _isLoadingNote = true;
    _scratchpadContent = "<p>Loading note...</p>";
    notifyListeners();
    try {
      _scratchpadContent =
          await _api.getNote(_currentProject!.id, _selectedSource!.id);
    } catch (e) {
      _scratchpadContent = "<p>Error fetching note.</p>";
    }
    _isLoadingNote = false;
    notifyListeners();
  }

  Future<void> generateTopicNote(String topic) async {
    if (_currentProject == null || topic.isEmpty) return;
    _isLoadingNote = true;
    _scratchpadContent = "<p>Generating note...</p>";
    notifyListeners();
    try {
      _scratchpadContent =
          await _api.generateTopicNote(_currentProject!.id, topic);
      topicController.clear();
    } catch (e) {
      _scratchpadContent = "<p>Error generating note.</p>";
    }
    _isLoadingNote = false;
    notifyListeners();
  }

  Future<void> askQuestion(String question) async {
    if (_currentProject == null || question.isEmpty) return;
    _chatHistory.add(ChatMessage(content: question, isUser: true));
    _isBotThinking = true;
    notifyListeners();
    try {
      // Prepare history: all messages except the last user message (which is `question`)
      // The API call expects the current question separately.
      final historyForApi = _chatHistory
          .where((m) => !m.isUser || m != _chatHistory.last)
          .map((m) => {'role': m.isUser ? 'user' : 'bot', 'content': m.content})
          .toList();
          
      final answer = await _api.askChatbot(
        _currentProject!.id,
        question,
        sourceId: _selectedSource?.id,
        history: historyForApi,
      );
      _chatHistory.add(ChatMessage(content: answer, isUser: false));
    } catch (e) {
      _chatHistory.add(
          ChatMessage(content: "Error: Could not get response.", isUser: false));
    }
    _isBotThinking = false;
    notifyListeners();
  }

  Future<String?> takePhotoAndInsertToNote(String currentNoteText) async {
    if (_currentProject == null) return null;

    try {
      final XFile? photo = await _picker.pickImage(source: ImageSource.camera);

      if (photo != null) {
        final Uint8List imageBytes = await photo.readAsBytes();
        final String fileName = photo.name;

        final String? mediaId = await _api.uploadImageBytes(
          _currentProject!.id,
          imageBytes,
          fileName,
        );

        if (mediaId != null) {
          final imageTag = '\n\n<firestore-image src="$mediaId"></firestore-image>\n\n';
          // Append to the text passed in from the editor, not the old provider state.
          return currentNoteText + imageTag;
        }
      }
    } catch (e) {
      print("Error taking photo: $e");
    }
    return null; // Return null on failure
  }
}