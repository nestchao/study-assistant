import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:study_assistance/api/api_service.dart';
import 'package:study_assistance/models/project.dart';
import 'dart:typed_data'; // Import
import 'package:image_picker/image_picker.dart';

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

  String _scratchpadContent = "<p>Select a source and click 'Show Source Note'.</p>";
  String get scratchpadContent => _scratchpadContent;
  bool _isLoadingNote = false;
  bool get isLoadingNote => _isLoadingNote;

  List<ChatMessage> _chatHistory = [
    ChatMessage(content: "Hello! Ask a question to get started.", isUser: false)
  ];
  List<ChatMessage> get chatHistory => _chatHistory;
  bool _isBotThinking = false;
  bool get isBotThinking => _isBotThinking;
  bool _hasFetched = false;

  Future<void> fetchProjects() async {
    if (_hasFetched || _isLoadingProjects) return;
    _hasFetched = true;
    _isLoadingProjects = true;
    notifyListeners();

    try {
      final data = await _api.getProjects();
      _projects = data.map((map) => Project.fromMap(map)).toList();
    } catch (e) {
      print("Error: $e");
    } finally {
      _isLoadingProjects = false;
      notifyListeners();
    }
  }

  Future<void> createProject(String name) async {
    if (name.isEmpty) return;
    try {
      await _api.createProject(name);  // Use ApiService
      await fetchProjects(); // ADD THIS LINE
      notifyListeners();
    } catch (e) {
      print("Error creating project: $e");
    }
  }

  void setCurrentProject(Project project) {
    _currentProject = project;
    _sources = [];
    _selectedSource = null;
    _chatHistory = [ChatMessage(content: "Hello! Ask a question to get started.", isUser: false)];
    _scratchpadContent = "<p>Select a source and click 'Show Source Note'.</p>";
    fetchSources();
    notifyListeners();
  }

  Future<void> fetchSources() async {
    if (_currentProject == null) return;
    _isLoadingSources = true;
    notifyListeners();
    try {
      final data = await _api.getSources(_currentProject!.id);
      _sources = data.map((s) => Source(
        id: s['id'],           // ← THIS IS SAFE ID
        filename: s['filename']
      )).toList();
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
    // Prevent duplicate selection
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
      
      // Auto-load the note
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
      _scratchpadContent = await _api.getNote(_currentProject!.id, _selectedSource!.id);
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
      _scratchpadContent = await _api.generateTopicNote(_currentProject!.id, topic);
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
      final historyForApi = _chatHistory.where((m) => !m.isUser || m != _chatHistory.last)
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
      _chatHistory.add(ChatMessage(content: "Error: Could not get response.", isUser: false));
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
}