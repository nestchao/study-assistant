import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:study_assistance/provider/project_provider.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:study_assistance/models/past_paper.dart';
import 'package:study_assistance/screens/workspace_panels.dart';
import 'package:super_clipboard/super_clipboard.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:study_assistance/services/firestore_image_service.dart';
import 'package:study_assistance/widgets/firestore_image.dart';
import 'package:markdown/markdown.dart' as md;

// --- 1. TOP-LEVEL WORKSPACE SCREEN (Manages the two main tabs) ---
class WorkspaceScreen extends StatefulWidget {
  const WorkspaceScreen({super.key});

  @override
  State<WorkspaceScreen> createState() => _WorkspaceScreenState();
}

class _WorkspaceScreenState extends State<WorkspaceScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ProjectProvider>();
    final project = provider.currentProject;

    if (project == null) {
      return const Scaffold(body: Center(child: Text("No project selected.")));
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(project.name, style: const TextStyle(color: Colors.black87)),
        backgroundColor: Colors.white,
        elevation: 1.0,
        iconTheme: const IconThemeData(color: Colors.black54),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            provider.selectSource(null);
            Navigator.pop(context);
          },
        ),
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.indigo,
          unselectedLabelColor: Colors.grey[600],
          indicatorColor: Colors.indigo,
          tabs: const [
            Tab(icon: Icon(Icons.menu_book_rounded), text: 'Study Hub'),
            Tab(icon: Icon(Icons.quiz_rounded), text: 'Paper Solver'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          StudyHubView(),
          PaperSolverView(),
        ],
      ),
    );
  }
}


// --- 2. STUDY HUB GATEKEEPER (Decides mobile vs. desktop) ---
class StudyHubView extends StatelessWidget {
  const StudyHubView({super.key});
  static const double mobileBreakpoint = 900.0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < mobileBreakpoint) {
          return const MobileStudyLayout();
        } else {
          return const DesktopStudyLayout();
        }
      },
    );
  }
}


// --- 3. DESKTOP STUDY LAYOUT ---
class DesktopStudyLayout extends StatefulWidget {
  const DesktopStudyLayout({super.key});

  @override
  State<DesktopStudyLayout> createState() => _DesktopStudyLayoutState();
}

class _DesktopStudyLayoutState extends State<DesktopStudyLayout> {
  // State for desktop UI
  double _sourcesWidth = 280.0;
  double _notesWidth = 400.0;
  bool _isSourcesVisible = true;
  bool _isChatVisible = true;
  bool _isNotesVisible = true;
  final double _minPanelWidth = 150.0;
  final double _collapseThreshold = 50.0;
  final double _minChatPanelWidth = 200.0;
  bool _isEditingNote = false;
  final TextEditingController _noteEditController = TextEditingController();
  final ScrollController _sourcesScrollController = ScrollController();
  final ScrollController _notesScrollController = ScrollController();

  @override
  void dispose() {
    _sourcesScrollController.dispose();
    _notesScrollController.dispose();
    _noteEditController.dispose();
    super.dispose();
  }

  void _togglePanelVisibility(String panel) {
    setState(() {
      if (panel == 'chat' && !_isChatVisible) {
        _isChatVisible = true;
        final double screenWidth = MediaQuery.of(context).size.width;
        const double targetChatWidth = 400.0;
        final currentSidePanelsWidth = (_isSourcesVisible ? _sourcesWidth : 0) + (_isNotesVisible ? _notesWidth : 0);
        final availableSpaceForSidePanels = screenWidth - targetChatWidth - 16;
        if (currentSidePanelsWidth > availableSpaceForSidePanels) {
          final overflow = currentSidePanelsWidth - availableSpaceForSidePanels;
          if (_isSourcesVisible && _isNotesVisible) {
            double sourcesProportion = _sourcesWidth / currentSidePanelsWidth;
            _sourcesWidth -= overflow * sourcesProportion;
            _notesWidth -= overflow * (1 - sourcesProportion);
          } else if (_isSourcesVisible) {
            _sourcesWidth -= overflow;
          } else if (_isNotesVisible) {
            _notesWidth -= overflow;
          }
        }
        return;
      }
      int visibleCount = (_isSourcesVisible ? 1 : 0) + (_isChatVisible ? 1 : 0) + (_isNotesVisible ? 1 : 0);
      if (visibleCount > 1) {
        if (panel == 'sources') _isSourcesVisible = !_isSourcesVisible;
        if (panel == 'chat') _isChatVisible = !_isChatVisible;
        if (panel == 'notes') _isNotesVisible = !_isNotesVisible;
      }
      if (panel == 'sources' && _isSourcesVisible) _sourcesWidth = 280.0;
      if (panel == 'notes' && _isNotesVisible) _notesWidth = 400.0;
    });
  }

  Widget _buildVisibilityToggleButton({
    required String tooltip, required IconData icon, required Color color,
    required bool isVisible, required VoidCallback onPressed, required bool isDisabled,
  }) {
    return IconButton(
      tooltip: tooltip,
      icon: Icon(icon),
      style: IconButton.styleFrom(
        foregroundColor: color,
        backgroundColor: isVisible ? color.withOpacity(0.20) : Colors.transparent,
        disabledForegroundColor: color.withOpacity(0.3),
      ),
      onPressed: isDisabled ? null : onPressed,
    );
  }

  Widget _buildResizer({required GestureDragUpdateCallback onDrag}) {
    return GestureDetector(
      onHorizontalDragUpdate: onDrag,
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeLeftRight,
        child: Container(width: 8, color: Colors.grey[300]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ProjectProvider>();
    final int visibleCount = (_isSourcesVisible ? 1 : 0) + (_isChatVisible ? 1 : 0) + (_isNotesVisible ? 1 : 0);
    final double screenWidth = MediaQuery.of(context).size.width;
    
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 50,
        backgroundColor: Colors.grey[100],
        elevation: 0,
        automaticallyImplyLeading: false,
        title: const Text("View Panels", style: TextStyle(color: Colors.black54, fontSize: 16)),
        actions: [
          _buildVisibilityToggleButton(
            tooltip: 'Toggle Sources', icon: Icons.folder_open, color: Colors.blue[300]!,
            isVisible: _isSourcesVisible, onPressed: () => _togglePanelVisibility('sources'),
            isDisabled: _isSourcesVisible && visibleCount == 1,
          ),
          _buildVisibilityToggleButton(
            tooltip: 'Toggle AI Chat', icon: Icons.chat_bubble_outline, color: Colors.purple[300]!,
            isVisible: _isChatVisible, onPressed: () => _togglePanelVisibility('chat'),
            isDisabled: _isChatVisible && visibleCount == 1,
          ),
          _buildVisibilityToggleButton(
            tooltip: 'Toggle Notes', icon: Icons.note_alt, color: Colors.green[300]!,
            isVisible: _isNotesVisible, onPressed: () => _togglePanelVisibility('notes'),
            isDisabled: _isNotesVisible && visibleCount == 1,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Row(
        children: [
          if (_isSourcesVisible)
            _isChatVisible
              ? SizedBox(width: _sourcesWidth, child: SourcesPanel(scrollController: _sourcesScrollController))
              : Expanded(flex: _sourcesWidth.round(), child: SourcesPanel(scrollController: _sourcesScrollController)),
          
          if (_isSourcesVisible && _isChatVisible)
            _buildResizer(onDrag: (details) { setState(() {
              _sourcesWidth = max(_collapseThreshold, _sourcesWidth + details.delta.dx);
              if (_sourcesWidth < _minPanelWidth) _isSourcesVisible = false;
              final chatWidth = screenWidth - _sourcesWidth - (_isNotesVisible ? _notesWidth + 8 : 0) - 8;
              if (chatWidth < _minChatPanelWidth && visibleCount > 1) _isChatVisible = false;
            }); }),
          
          if (_isChatVisible) const Expanded(child: AiChatPanel()),
          
          if (_isChatVisible && _isNotesVisible)
            _buildResizer(onDrag: (details) { setState(() {
              _notesWidth = max(_collapseThreshold, _notesWidth - details.delta.dx);
              if (_notesWidth < _minPanelWidth) _isNotesVisible = false;
              final chatWidth = screenWidth - _notesWidth - (_isSourcesVisible ? _sourcesWidth + 8 : 0) - 8;
              if (chatWidth < _minChatPanelWidth && visibleCount > 1) _isChatVisible = false;
            }); }),

          if (_isNotesVisible)
            _isChatVisible
              ? SizedBox(width: _notesWidth, child: _buildScratchpadPanel(context, provider))
              : Expanded(flex: _notesWidth.round(), child: _buildScratchpadPanel(context, provider)),
        ],
      ),
    );
  }

  Widget _noteActions(BuildContext ctx, ProjectProvider p, String html) =>
      Container(
        padding: const EdgeInsets.all(12),
        child: Column(children: [
          ElevatedButton.icon(
              onPressed: p.selectedSource == null ? null : p.getNoteForSelectedSource,
              icon: const Icon(Icons.refresh),
              label: const Text("Reload")),
          const SizedBox(height: 8),
          OutlinedButton.icon(
              onPressed: () => _copyRichTextToClipboard(ctx, html),
              icon: const Icon(Icons.copy),
              label: const Text("Copy Note")),
          const Divider(height: 24),
          TextField(
              controller: p.topicController,
              maxLines: 2,
              decoration: const InputDecoration(hintText: "e.g. Explain OOP")),
          ElevatedButton.icon(
              onPressed: () {
                final t = p.topicController.text.trim();
                if (t.isNotEmpty) p.generateTopicNote(t);
              },
              icon: const Icon(Icons.auto_awesome),
              label: const Text("Generate")),
        ]),
      );

  Widget _buildNoteViewer(String html) {
    return Scrollbar(
      controller: _notesScrollController,
      thumbVisibility: true,
      child: SingleChildScrollView(
        controller: _notesScrollController,
        padding: const EdgeInsets.all(16),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Html(
              data: html,
              extensions: [
                TagExtension(
                  tagsToExtend: {"firestore-image"},
                  builder: (ExtensionContext context) {
                    final String mediaId = context.attributes['src'] ?? '';
                    return FirestoreImage(mediaId: mediaId);
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _copyRichTextToClipboard(BuildContext context, String html) async {
    final item = DataWriterItem();
    item.add(Formats.htmlText(html));
    
    // Helper to create a plain text fallback
    String stripHtmlTags(String html) {
      final RegExp exp = RegExp(r"<[^>]*>", multiLine: true, caseSensitive: true);
      return html.replaceAll(exp, '').replaceAll('&nbsp;', ' ');
    }

    final plainText = stripHtmlTags(html).trim();
    item.add(Formats.plainText(plainText));
    
    await SystemClipboard.instance?.write([item]);
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Formatted note copied!"),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  Widget _buildNoteEditor() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: TextField(
        controller: _noteEditController,
        maxLines: null,
        expands: true,
        keyboardType: TextInputType.multiline,
        decoration: const InputDecoration(
          hintText: "Edit your notes here...",
          border: OutlineInputBorder(),
          isDense: true,
        ),
        textAlignVertical: TextAlignVertical.top,
      ),
    );
  }

  Widget _buildScratchpadPanel(BuildContext context, ProjectProvider p) {
    final html = p.scratchpadContent;
    return Container(
      color: Colors.white,
      child: Column(
        children: [
          Container( // Header
            padding: const EdgeInsets.all(16),
            color: Colors.green[50],
            child: Row(children: [
              Icon(Icons.note_alt, color: Colors.green[700]),
              const SizedBox(width: 8),
              const Text("Study Notes", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ]),
          ),
          
          // Edit/Save Buttons
          if (!_isEditingNote)
            TextButton.icon(
              icon: const Icon(Icons.edit, size: 18),
              label: const Text("Edit"),
              onPressed: () {
                setState(() {
                  _noteEditController.text = html;
                  _isEditingNote = true;
                });
              },
            )
          else
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TextButton(
                  child: const Text("Cancel", style: TextStyle(color: Colors.red)),
                  onPressed: () => setState(() { _isEditingNote = false; _noteEditController.clear(); }),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  icon: p.isSavingNote
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Icon(Icons.save, size: 18),
                  label: Text(p.isSavingNote ? "Saving..." : "Save"),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.green[700]),
                  onPressed: p.isSavingNote ? null : () async {
                    final newHtml = _noteEditController.text;
                    final success = await p.saveNoteChanges(newHtml);
                    if (success) {
                      setState(() {
                        _isEditingNote = false;
                        _noteEditController.clear();
                      });
                    }
                  },
                ),
              ],
            ),

          Expanded(
            child: p.isLoadingNote
                ? const Center(child: CircularProgressIndicator())
                : _isEditingNote
                    ? _buildNoteEditor()
                    : _buildNoteViewer(html),
          ),

          if (!_isEditingNote) _noteActions(context, p, html),
        ],
      ),
    );
  }
}


// --- 4. MOBILE STUDY LAYOUT ---
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
  }

  @override
  void dispose() {
    _tabController.dispose();
    _noteEditController.dispose();
    super.dispose();
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
}


// --- 5. PAPER SOLVER VIEW ---
class PaperSolverView extends StatefulWidget {
  const PaperSolverView({super.key});

  @override
  State<PaperSolverView> createState() => _PaperSolverViewState();
}

class _PaperSolverViewState extends State<PaperSolverView> {
  PastPaper? _selectedPaper;

  final TextEditingController _noteEditController = TextEditingController();
  final ScrollController _notesScrollController = ScrollController();

  String markdownToHtml(String markdown) {
    return md.markdownToHtml(markdown, extensionSet: md.ExtensionSet.gitHubWeb);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<ProjectProvider>();

    if (p.isUploadingPaper) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 20),
            Text("Analyzing your paper...", style: TextStyle(fontSize: 16)),
            Padding(
              padding: EdgeInsets.all(16.0),
              child: Text(
                "This may take a moment as we read the document and generate answers based on your notes.",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
            ),
          ],
        ),
      );
    }

    // Handle errors from the provider
    if (p.paperError != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) { // Check if the widget is still in the tree
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error: ${p.paperError}'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 5),
            ),
          );
          p.clearPaperError(); // Clear error after showing it
        }
      });
    }

    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: p.isLoadingPapers
          ? const Center(child: CircularProgressIndicator())
          : p.pastPapers.isEmpty
              ? _buildEmptyState(p)
              : _buildMainContent(p),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: p.pickAndProcessPaper,
        icon: const Icon(Icons.upload_file),
        label: const Text('Upload Paper'),
        backgroundColor: Colors.indigo,
      ),
    );
  }

  Widget _buildEmptyState(ProjectProvider p) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.quiz_outlined, size: 100, color: Colors.grey[300]),
          const SizedBox(height: 20),
          const Text('No Past Papers Solved',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 24.0),
            child: Text(
              'Upload a PDF or image of a question paper to get started.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: p.pickAndProcessPaper,
            icon: const Icon(Icons.add),
            label: const Text("Upload First Paper"),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
          )
        ],
      ),
    );
  }

  Widget _buildMainContent(ProjectProvider p) {
    return LayoutBuilder(builder: (context, constraints) {
      // For mobile, show a list view. For desktop, show side-by-side.
      if (constraints.maxWidth < 600) {
        return _buildMobilePaperView(p);
      } else {
        return _buildDesktopPaperView(p);
      }
    });
  }

  // View for Desktop
  Widget _buildDesktopPaperView(ProjectProvider p) {
    return Row(
      children: [
        SizedBox(
          width: 300,
          child: _buildPaperList(p, isMobile: false),
        ),
        Expanded(
          child: _selectedPaper == null
              ? const Center(child: Text("Select a paper to view the solution"))
              : _buildQAPanel(_selectedPaper!),
        ),
      ],
    );
  }

  // View for Mobile
  Widget _buildMobilePaperView(ProjectProvider p) {
    if (_selectedPaper != null) {
      return Scaffold(
        appBar: AppBar(
          title: Text(_selectedPaper!.filename, style: const TextStyle(fontSize: 16)),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => setState(() => _selectedPaper = null),
          ),
        ),
        body: _buildQAPanel(_selectedPaper!),
      );
    }
    return _buildPaperList(p, isMobile: true);
  }

  Widget _buildPaperList(ProjectProvider p, {required bool isMobile}) {
    return Container(
      color: Colors.white,
      child: Column(
        children: [
          _buildPanelHeader("Solved Papers", Icons.history_edu, Colors.indigo),
          Expanded(
            child: ListView.builder(
              itemCount: p.pastPapers.length,
              itemBuilder: (context, index) {
                final paper = p.pastPapers[index];
                final isSelected = !isMobile && _selectedPaper?.id == paper.id;
                return ListTile(
                  leading: const Icon(Icons.article_outlined),
                  title: Text(paper.filename, maxLines: 2, overflow: TextOverflow.ellipsis),
                  tileColor: isSelected ? Colors.indigo.withOpacity(0.1) : null,
                  onTap: () {
                    setState(() {
                      _selectedPaper = paper;
                    });
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPanelHeader(String title, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Colors.grey[200]!)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 8),
          Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildQAPanel(PastPaper paper) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: paper.qaPairs.length,
      itemBuilder: (context, index) {
        final qa = paper.qaPairs[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 16),
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: ExpansionTile(
            leading: CircleAvatar(child: Text('${index + 1}')),
            title: Text(qa.question, style: const TextStyle(fontWeight: FontWeight.w600)),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: SelectionArea(
                  child: Html(
                    data: markdownToHtml(qa.answer),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildNoteViewer(String html) {
    return Scrollbar(
      controller: _notesScrollController,
      thumbVisibility: true,
      child: SingleChildScrollView(
        controller: _notesScrollController,
        padding: const EdgeInsets.all(16),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            // --- THIS IS THE CLEANED-UP IMPLEMENTATION ---
            child: Html(
              data: html,
              extensions: [
                TagExtension(
                  tagsToExtend: {"firestore-image"},
                  builder: (ExtensionContext context) {
                    final String mediaId = context.attributes['src'] ?? '';
                    // Just return the new reusable widget. No complex logic here.
                    return FirestoreImage(mediaId: mediaId);
                  },
                ),
              ],
            ),
            // --- END OF FIX ---
          ),
        ),
      ),
    );
  }

  Widget _buildNoteEditor() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: TextField(
        controller: _noteEditController,
        maxLines: null, // Allows the text field to expand vertically
        expands: true, // Fills the available space
        keyboardType: TextInputType.multiline,
        decoration: const InputDecoration(
          hintText: "Edit your notes here...",
          border: OutlineInputBorder(),
          isDense: true,
        ),
        textAlignVertical: TextAlignVertical.top,
      ),
    );
  }

  Widget _emptySources() => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.upload_file, size: 64, color: Colors.grey[400]),
          Text("No PDFs yet", style: TextStyle(color: Colors.grey[600])),
          Text("Tap below to upload",
              style: TextStyle(color: Colors.grey[500])),
        ]),
      );

  Widget _uploadFooter(ProjectProvider p, List<Source> s) => Container(
        padding: const EdgeInsets.all(12),
        color: Colors.grey[50],
        child: Column(children: [
          ElevatedButton.icon(
            onPressed: p.isUploading ? null : p.pickAndUploadFiles,
            icon: p.isUploading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(color: Colors.white))
                : const Icon(Icons.upload_file),
            label: Text(p.isUploading ? "Uploading..." : "Upload PDFs"),
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue[600],
                minimumSize: const Size(double.infinity, 50)),
          ),
          if (s.isNotEmpty)
            Text("${s.length} source${s.length > 1 ? 's' : ''}",
                style: const TextStyle(fontSize: 12, color: Colors.grey)),
        ]),
      );

  Widget _noteActions(BuildContext ctx, ProjectProvider p, String html) =>
      Container(
        padding: const EdgeInsets.all(12),
        child: Column(children: [
          ElevatedButton.icon(
              onPressed:
                  p.selectedSource == null ? null : p.getNoteForSelectedSource,
              icon: const Icon(Icons.refresh),
              label: const Text("Reload")),
          const SizedBox(height: 8),
          OutlinedButton.icon(
              onPressed: () => _copyRichTextToClipboard(ctx, html),
              icon: const Icon(Icons.copy),
              label: const Text("Copy Note")),
          const Divider(height: 24),
          TextField(
              controller: p.topicController,
              maxLines: 2,
              decoration: const InputDecoration(hintText: "e.g. Explain OOP")),
          ElevatedButton.icon(
              onPressed: () {
                final t = p.topicController.text.trim();
                if (t.isNotEmpty) p.generateTopicNote(t);
              },
              icon: const Icon(Icons.auto_awesome),
              label: const Text("Generate")),
        ]),
      );

    Future<void> _copyRichTextToClipboard(BuildContext context, String html) async {
    final item = DataWriterItem();
    item.add(Formats.htmlText(html));
    
    // Helper to create a plain text fallback
    String stripHtmlTags(String html) {
      final RegExp exp = RegExp(r"<[^>]*>", multiLine: true, caseSensitive: true);
      return html.replaceAll(exp, '').replaceAll('&nbsp;', ' ');
    }

    final plainText = stripHtmlTags(html).trim();
    item.add(Formats.plainText(plainText));
    
    await SystemClipboard.instance?.write([item]);
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Formatted note copied!"),
          backgroundColor: Colors.green,
        ),
      );
    }
  }
}