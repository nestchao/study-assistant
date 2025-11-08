import 'dart:developer';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:study_assistance/api/api_service.dart';
import 'package:study_assistance/models/project.dart';
import 'dart:typed_data'; // Import
import 'dart:convert';
import 'package:image_picker/image_picker.dart';
import 'package:study_assistance/models/past_paper.dart';

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

  List<PastPaper> _pastPapers = [];
  List<PastPaper> get pastPapers => _pastPapers;

  bool _isLoadingPapers = false;
  bool get isLoadingPapers => _isLoadingPapers;

  bool _isUploadingPaper = false;
  bool get isUploadingPaper => _isUploadingPaper;

  String? _paperError;
  String? get paperError => _paperError;

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

  ProjectProvider() {
    _loadProjectsFromCache();
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

  // --- NEW: State variables for UI feedback ---
  String? _deletingProjectId;
  String? get deletingProjectId => _deletingProjectId;
  String? _renamingProjectId;
  String? get renamingProjectId => _renamingProjectId;
  String? _deletingSourceId;
  String? get deletingSourceId => _deletingSourceId;


  // --- CACHING LOGIC ---

  Future<void> _loadProjectsFromCache() async {
    final prefs = await SharedPreferences.getInstance();
    final String? projectsJson = prefs.getString('cached_projects');

    if (projectsJson != null) {
      final List<dynamic> projectList = jsonDecode(projectsJson);
      _projects = projectList.map((map) => Project.fromMap(map)).toList();
      print("✅ Loaded ${_projects.length} projects from cache.");
      notifyListeners();
    }
  }

  Future<void> _saveProjectsToCache() async {
    final prefs = await SharedPreferences.getInstance();
    final List<Map<String, dynamic>> projectList =
        _projects.map((p) => p.toMap()).toList();
    await prefs.setString('cached_projects', jsonEncode(projectList));
    print("💾 Saved ${_projects.length} projects to cache.");
  }

  // --- DATA FETCHING & MUTATION METHODS ---

  Future<void> fetchProjects({bool forceRefresh = false}) async {
    if (_isLoadingProjects) return;
    if (_projects.isNotEmpty && !forceRefresh) return;

    _isLoadingProjects = true;
    if (_projects.isEmpty || forceRefresh) {
      notifyListeners();
    }

    try {
      final data = await _api.getProjects();
      final newProjects = data.map((map) => Project.fromMap(map)).toList();

      if (jsonEncode(newProjects.map((p) => p.toMap()).toList()) != jsonEncode(_projects.map((p) => p.toMap()).toList())) {
          _projects = newProjects;
          await _saveProjectsToCache();
      }
    } catch (e) {
      print("Error fetching projects: $e");
    } finally {
      _isLoadingProjects = false;
      notifyListeners();
    }
  }

  Future<void> createProject(String name) async {
    if (name.isEmpty) return;
    try {
      await _api.createProject(name);
      await fetchProjects(forceRefresh: true);
    } catch (e) {
      print("Error creating project: $e");
    }
  }

  // --- NEW ---
  Future<void> renameProject(String projectId, String newName) async {
    _renamingProjectId = projectId;
    notifyListeners();

    try {
      await _api.renameProject(projectId, newName);
      // Find and update the project in the local list
      final index = _projects.indexWhere((p) => p.id == projectId);
      if (index != -1) {
        _projects[index] = Project(
          id: _projects[index].id,
          name: newName,
          createdAt: _projects[index].createdAt,
        );
        await _saveProjectsToCache(); // Update the cache
      }
    } catch (e) {
      print("Error renaming project: $e");
      rethrow;
    } finally {
      _renamingProjectId = null;
      notifyListeners();
    }
  }

  Future<void> deleteProject(String projectId) async {
    _deletingProjectId = projectId;
    notifyListeners();

    try {
      await _api.deleteProject(projectId);
      _projects.removeWhere((project) => project.id == projectId);
      await _saveProjectsToCache();
    } catch (e) {
      print("Error deleting project: $e");
      rethrow;
    } finally {
      _deletingProjectId = null;
      notifyListeners();
    }
  }

  // --- NEW ---
  Future<void> deleteSource(String sourceId) async {
    if (_currentProject == null) return;
    _deletingSourceId = sourceId;
    notifyListeners();
    try {
      await _api.deleteSource(_currentProject!.id, sourceId);
      _sources.removeWhere((s) => s.id == sourceId);

      // If the deleted source was the selected one, clear the selection
      if (_selectedSource?.id == sourceId) {
        _selectedSource = null;
        _scratchpadContent = "<p>Select a source to see its note.</p>";
      }
    } catch (e) {
      print("Error deleting source: $e");
      rethrow;
    } finally {
      _deletingSourceId = null;
      notifyListeners();
    }
  }


  // --- REST OF YOUR METHODS ---

  void setCurrentProject(Project project) {
    _currentProject = project;
    _sources = [];
    _selectedSource = null;
    _chatHistory = [
      ChatMessage(content: "Hello! Ask a question to get started.", isUser: false)
    ];
    _scratchpadContent = "<p>Select a source and click 'Show Source Note'.</p>";
    _mediaCache.clear();
    _pastPapers = []; // Clear old papers
    fetchSources();
    fetchPastPapers(); // Fetch papers for the new project
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
          return currentNoteText + imageTag;
        }
      }
    } catch (e) {
      print("Error taking photo: $e");
    }
    return null;
  }

  Future<void> fetchPastPapers({bool forceRefresh = false}) async {
    if (_currentProject == null) return;
    if (_isLoadingPapers) return;

    _isLoadingPapers = true;
    notifyListeners();
    try {
      final data = await _api.getPastPapers(_currentProject!.id);
      _pastPapers = data.map((map) => PastPaper.fromMap(map)).toList();
    } catch (e) {
      print("Error fetching past papers: $e");
    } finally {
      _isLoadingPapers = false;
      notifyListeners();
    }
  }

  Future<void> pickAndProcessPaper(String analysisMode) async {
    if (_currentProject == null) return;

    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'png', 'jpg', 'jpeg'],
      allowMultiple: false,
    );

    if (result != null && result.files.single.bytes != null) {
      _isUploadingPaper = true;
      _paperError = null;
      notifyListeners();
      try {
        // Pass the mode to the API service
        final newPaperData = await _api.uploadPastPaper(
            _currentProject!.id, result.files.single, analysisMode);
        
        // Add the new paper to the top of the list instantly
        _pastPapers.insert(0, PastPaper.fromMap(newPaperData));

      } catch (e) {
        print("Paper processing error: $e");
        _paperError = e.toString();
      } finally {
        _isUploadingPaper = false;
        notifyListeners();
      }
    }
  }

  void clearPaperError() {
    _paperError = null;
    notifyListeners();
  }

  Future<String?> getPhotoAsTag() async {
    if (_currentProject == null) return null;

    try {
      final XFile? photo = await _picker.pickImage(source: ImageSource.camera);

      if (photo != null) {
        final Uint8List imageBytes = await photo.readAsBytes();
        final String fileName = photo.name;

        // This part just does the upload
        final String? mediaId = await _api.uploadImageBytes(
          _currentProject!.id,
          imageBytes,
          fileName,
        );

        // This part just returns the tag as a string
        if (mediaId != null) {
          return '\n\n<firestore-image src="$mediaId"></firestore-image>\n\n';
        }
      }
    } catch (e) {
      print("Error taking photo: $e");
    }
    return null;
  }

  Future<String> getNoteAsRichHtml() async {
    String richHtml = _scratchpadContent;

    // This regex finds all instances of your custom tag and captures the mediaId.
    final RegExp exp = RegExp(r'<firestore-image src="([^"]+)"></firestore-image>');

    // Find all matches in the current note content.
    final matches = exp.allMatches(richHtml).toList();

    // Asynchronously process each match.
    for (final match in matches) {
      // The full matched tag, e.g., '<firestore-image src="img_123"></firestore-image>'
      final String fullTag = match.group(0)!; 
      
      // The captured mediaId, e.g., 'img_123'
      final String mediaId = match.group(1)!;

      // Get the image bytes using your existing caching logic.
      final Uint8List? imageBytes = await getCachedMediaBytes(mediaId);

      if (imageBytes != null) {
        // Convert the image bytes to a Base64 string.
        final String base64Image = base64Encode(imageBytes);
        
        // Create the standard <img> tag with a Base64 Data URI.
        // Assuming JPEG. You could store the mime type in your backend metadata for more accuracy.
        final String imageHtmlTag = '<img src="data:image/jpeg;base64,$base64Image">';

        // Replace the custom tag in our string with the new standard <img> tag.
        richHtml = richHtml.replaceFirst(fullTag, imageHtmlTag);
      } else {
        // If the image can't be loaded, replace the tag with an error message.
        richHtml = richHtml.replaceFirst(fullTag, '<p>[Error: Image $mediaId not found]</p>');
      }
    }

    return richHtml;
  }
}