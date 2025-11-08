// lib/screens/mobile_study_layout.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:study_assistance/provider/project_provider.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:study_assistance/screens/workspace_panels.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:study_assistance/services/firestore_image_service.dart';

class MobileStudyLayout extends StatefulWidget {
  const MobileStudyLayout({super.key});

  @override
  State<MobileStudyLayout> createState() => _MobileStudyLayoutState();
}

class _MobileStudyLayoutState extends State<MobileStudyLayout> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _noteEditController = TextEditingController();
  bool _isEditingNote = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() => setState(() {})); // To rebuild actions on tab change
  }

  @override
  void dispose() {
    _tabController.dispose();
    _noteEditController.dispose();
    super.dispose();
  }
  
  // Mobile-specific helper method
  Future<FileInfo?> _getOrDownloadImage(
    CacheManager cacheManager,
    String url,
  ) async {
    try {
      // First, try to get the file info from the cache.
      final fileInfo = await cacheManager.getFileFromCache(url);
      
      // If it's in the cache, return it immediately.
      if (fileInfo != null) {
        print("Image loaded from cache: $url");
        return fileInfo;
      }
      
      // If it's not in the cache, trigger a download.
      // downloadFile will fetch it (using your custom FirestoreFileService),
      // save it to the cache, and then return the FileInfo.
      print("Image not in cache, downloading: $url");
      return await cacheManager.downloadFile(url);
      
    } catch (e) {
      print("Error in _getOrDownloadImage: $e");
      // Rethrow the error so the FutureBuilder can display an error state.
      rethrow;
    }
  }
  
  Widget _buildMobileNotesPanel(ProjectProvider p) {
      return Padding(
        padding: const EdgeInsets.all(8.0),
        child: _isEditingNote
            ? TextField(
                controller: _noteEditController,
                maxLines: null,
                expands: true,
                keyboardType: TextInputType.multiline,
                decoration: const InputDecoration(
                  hintText: "Edit your notes...",
                  border: InputBorder.none,
                ),
              )
            : SingleChildScrollView(
                child: Html(
                  data: p.scratchpadContent,
                  extensions: [
                    TagExtension(
                      tagsToExtend: {"firestore-image"},
                      builder: (ExtensionContext context) {
                        final buildContext = context.buildContext;
                        if (buildContext == null) {
                          return const SizedBox.shrink();
                        }

                        final String mediaId = context.attributes['src'] ?? '';
                        if (mediaId.isEmpty) {
                          return const Text("[Image Error: Missing ID]");
                        }

                        final provider = Provider.of<ProjectProvider>(
                          buildContext,
                          listen: false,
                        );

                        final cacheManager = FirestoreImageCacheManager(
                          apiService: provider.apiService,
                          projectId: provider.currentProject!.id,
                        );

                        final url = 'firestore_media:$mediaId';

                        return FutureBuilder<FileInfo?>(
                          // CHANGED: First check cache, if null then download
                          future: _getOrDownloadImage(cacheManager, url),
                          builder: (context, snapshot) {
                            if (snapshot.connectionState == ConnectionState.waiting) {
                              return const Center(
                                child: Padding(
                                  padding: EdgeInsets.all(8.0),
                                  child: CircularProgressIndicator(),
                                ),
                              );
                            }

                            if (snapshot.hasError) {
                              print("Image Loading Error: ${snapshot.error}");
                              return const Padding(
                                padding: EdgeInsets.all(8.0),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.error, color: Colors.red, size: 32),
                                    SizedBox(height: 4),
                                    Text(
                                      "Failed to load image",
                                      style: TextStyle(color: Colors.red, fontSize: 12),
                                    ),
                                  ],
                                ),
                              );
                            }

                            if (snapshot.hasData && snapshot.data != null) {
                              return Padding(
                                padding: const EdgeInsets.symmetric(vertical: 8.0),
                                child: Image.file(
                                  snapshot.data!.file,
                                  errorBuilder: (context, error, stackTrace) {
                                    print("Image.file Error: $error");
                                    return const Icon(
                                      Icons.broken_image,
                                      color: Colors.grey,
                                      size: 48,
                                    );
                                  },
                                ),
                              );
                            }

                            // Fallback for null data
                            return const Padding(
                              padding: EdgeInsets.all(8.0),
                              child: Icon(
                                Icons.broken_image,
                                color: Colors.grey,
                                size: 48,
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ],
                ),
            ),
          
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ProjectProvider>();
    return Scaffold(
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight),
        child: AppBar(
          automaticallyImplyLeading: false,
          backgroundColor: Colors.white,
          elevation: 0,
          title: TabBar(
            controller: _tabController,
            labelColor: Colors.indigo,
            tabs: const [
              Tab(icon: Icon(Icons.folder_open), text: "Sources"),
              Tab(icon: Icon(Icons.smart_toy), text: "AI Chat"),
              Tab(icon: Icon(Icons.edit_note), text: "Notes"),
            ],
          ),
          actions: [
            if (_tabController.index == 2)
              if (provider.isSavingNote)
                const Padding(padding: EdgeInsets.all(16.0), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator()))
              else
                TextButton(
                  onPressed: () async {
                    if (_isEditingNote) {
                      final success = await provider.saveNoteChanges(_noteEditController.text);
                      if (success) setState(() => _isEditingNote = false);
                    } else {
                      setState(() {
                        _noteEditController.text = provider.scratchpadContent;
                        _isEditingNote = true;
                      });
                    }
                  },
                  child: Text(_isEditingNote ? "SAVE" : "EDIT", style: const TextStyle(color: Colors.indigo)),
                )
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          const SourcesPanel(),
          const AiChatPanel(),
          _buildMobileNotesPanel(provider),
        ],
      ),
      floatingActionButton: _tabController.index == 2 && _isEditingNote
        ? FloatingActionButton(onPressed: () async {
            final currentText = _noteEditController.text;
            final imageTag = await provider.getPhotoAsTag();
            if (imageTag != null) {
              setState(() {
                _noteEditController.text = currentText + imageTag;
                _noteEditController.selection = TextSelection.fromPosition(TextPosition(offset: _noteEditController.text.length));
              });
            }
          }, child: const Icon(Icons.camera_alt))
        : null,
    );
  }
}