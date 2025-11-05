// lib/screens/workspace_screen.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:study_assistance/provider/project_provider.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:study_assistance/models/past_paper.dart';
import 'package:study_assistance/screens/workspace_panels.dart'; // Make sure this import is correct
import 'package:super_clipboard/super_clipboard.dart';
import 'package:study_assistance/screens/workspace_panels.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:study_assistance/services/firestore_image_service.dart';
import 'package:study_assistance/widgets/firestore_image.dart';

// Re-usable helper widget.
class SourceTile extends StatelessWidget {
  final String title;
  final IconData icon;
  final bool isSelected;
  final bool isDeleting;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;

  const SourceTile({
    super.key,
    required this.title,
    required this.icon,
    this.isSelected = false,
    this.isDeleting = false,
    this.onTap,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Material(
        color:
            isSelected ? Colors.indigo.withOpacity(0.1) : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: isDeleting ? null : onTap,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: isSelected ? Colors.indigo : Colors.transparent),
            ),
            child: Row(
              children: [
                Icon(icon, color: isSelected ? Colors.indigo : Colors.grey[700]),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontWeight:
                          isSelected ? FontWeight.bold : FontWeight.normal,
                      color: Colors.black87,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (isDeleting)
                  const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else if (onDelete != null)
                  IconButton(
                    icon: Icon(Icons.delete_outline, color: Colors.grey[600]),
                    onPressed: onDelete,
                    tooltip: 'Delete Source',
                  )
                else if (isSelected)
                  const Icon(Icons.check_circle, color: Colors.indigo, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}


// --- Main Workspace Screen ---
// This is now the single source of truth for the workspace layout.
class WorkspaceScreen extends StatefulWidget {
  const WorkspaceScreen({super.key});

  @override
  State<WorkspaceScreen> createState() => _WorkspaceScreenState();
}

class _WorkspaceScreenState extends State<WorkspaceScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  State<DesktopWorkspaceLayout> createState() => _DesktopWorkspaceLayoutState();
}

class _DesktopWorkspaceLayoutState extends State<DesktopWorkspaceLayout> {
  // State variables to manage panel widths and visibility
  double _sourcesWidth = 280.0;
  double _notesWidth = 400.0;
  bool _isSourcesVisible = true;
  bool _isChatVisible = true;
  bool _isNotesVisible = true;
  final double _minPanelWidth = 150.0; // Minimum width before a panel is useful
  final double _collapseThreshold = 50.0; // Width at which panels auto-hide
  final double _minChatPanelWidth = 200.0;

  static const String _firestoreImagePlaceholderPrefix = '%%FIRESTORE_IMAGE_';
  static const String _firestoreImagePlaceholderSuffix = '%%';

  bool _isEditingNote = false;
  final TextEditingController _noteEditController = TextEditingController();

  final ScrollController _sourcesScrollController = ScrollController();
  final ScrollController _notesScrollController = ScrollController();
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
    final project = provider.currentProject!;

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

// --- WIDGET FOR TAB 1: STUDY HUB (NOW RESPONSIVE) ---
class StudyHubView extends StatefulWidget {
  const StudyHubView({super.key});

  @override
  State<StudyHubView> createState() => _StudyHubViewState();
}

class _StudyHubViewState extends State<StudyHubView> with SingleTickerProviderStateMixin {
  late TabController _studyTabController;

  // Breakpoint to switch between desktop (Row) and mobile (TabBar) layouts
  static const double mobileBreakpoint = 900.0; // Increased breakpoint for 3 panels
          // --- RESIZER 1 ---
          if (_isSourcesVisible && _isChatVisible)
            _buildResizer(
              onDrag: (details) {
                setState(() {
                  _sourcesWidth =
                      max(_collapseThreshold, _sourcesWidth + details.delta.dx);
                  if (_sourcesWidth < _minPanelWidth) _isSourcesVisible = false;
                  final chatWidth = screenWidth -
                      _sourcesWidth -
                      (_isNotesVisible ? _notesWidth + 8 : 0) -
                      8;
                  if (chatWidth < _minChatPanelWidth && visibleCount > 1) {
                    _isChatVisible = false;
                  }
                });
              },
            ),

  @override
  void initState() {
    super.initState();
    // This controller is now for 3 panels on mobile
    _studyTabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _studyTabController.dispose();
    super.dispose();
  }
          // --- RESIZER 2 ---
          if (_isChatVisible && _isNotesVisible)
            _buildResizer(
              onDrag: (details) {
                setState(() {
                  _notesWidth =
                      max(_collapseThreshold, _notesWidth - details.delta.dx);
                  if (_notesWidth < _minPanelWidth) _isNotesVisible = false;
                  final chatWidth = screenWidth -
                      _notesWidth -
                      (_isSourcesVisible ? _sourcesWidth + 8 : 0) -
                      8;
                  if (chatWidth < _minChatPanelWidth && visibleCount > 1) {
                    _isChatVisible = false;
                  }
                });
              },
            ),

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < mobileBreakpoint) {
          // --- MOBILE LAYOUT: Use a TabBar for Sources, Chat, and Notes ---
          return Scaffold(
            appBar: TabBar(
              controller: _studyTabController,
              labelColor: Colors.indigo,
              tabs: const [
                Tab(icon: Icon(Icons.folder_open), text: "Sources"),
                Tab(icon: Icon(Icons.smart_toy), text: "AI Chat"),
                Tab(icon: Icon(Icons.edit_note), text: "Note"), // ADDED NOTE TAB
              ],
            ),
            body: TabBarView(
              controller: _studyTabController,
              children: const [
                SourcesPanel(),
                AiChatPanel(),
                NotesPanel(), // ADDED NOTE PANEL
              ],
            ),
          );
        } else {
          // --- DESKTOP LAYOUT: Use a Row for three side-by-side panels ---
          return Row(
            children: [
              const Expanded(flex: 2, child: SourcesPanel()),
              Container(width: 1, color: Colors.grey[300]),
              const Expanded(flex: 3, child: AiChatPanel()),
              Container(width: 1, color: Colors.grey[300]), // ADDED DIVIDER
              const Expanded(flex: 3, child: NotesPanel()),   // ADDED NOTE PANEL
            ],
          );
        }
      },
    );
  }
}

// --- WIDGET FOR TAB 2: PAPER SOLVER ---
class PaperSolverView extends StatefulWidget {
  const PaperSolverView({super.key});

  @override
  _PaperSolverViewState createState() => _PaperSolverViewState();
}

class _PaperSolverViewState extends State<PaperSolverView> {
  PastPaper? _selectedPaper;

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
            shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
            collapsedShape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
            leading: CircleAvatar(child: Text('${index + 1}')),
            title: Text(qa.question, style: const TextStyle(fontWeight: FontWeight.w600)),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: SelectionArea(
                  child: Html(
                    data: markdownToHtml(qa.answer),
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
              children: [
                TextButton(
                  child:
                      const Text("Cancel", style: TextStyle(color: Colors.red)),
                  onPressed: () {
                    setState(() {
                      _isEditingNote = false;
                      _noteEditController.clear();
                    });
                  },
                ),
                ElevatedButton.icon(
                  icon: p.isSavingNote
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: const CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2))
                      : const Icon(Icons.save, size: 18),
                  label: Text(p.isSavingNote ? "Saving..." : "Save"),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green[700]),
                  // Disable button while saving
                  onPressed: p.isSavingNote
                      ? null
                      : () async {

                        final newHtml = _noteEditController.text;

                        final success = await p.saveNoteChanges(newHtml);

                        if (success) {
                          setState(() {
                            _isEditingNote = false;
                            _noteEditController.clear();
                          });
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text("Error: Could not save note."),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      },
                ),
              ],
            ),

          Expanded(
            child: p.isLoadingNote
                ? const Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                    CircularProgressIndicator(),
                    Text("Generating...")
                  ]))
                : _isEditingNote
                    ? _buildNoteEditor()
                    : _buildNoteViewer(html),
          ),

          // Actions (This part remains the same)
          if (!_isEditingNote) _noteActions(context, p, html),
        ],
      ),
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
}

class MobileWorkspaceLayout extends StatefulWidget {
  const MobileWorkspaceLayout({super.key});

  @override
  State<MobileWorkspaceLayout> createState() => _MobileWorkspaceLayoutState();
}

class _MobileWorkspaceLayoutState extends State<MobileWorkspaceLayout> {
  int _selectedIndex = 0; // 0 for Sources, 1 for Chat, 2 for Notes

  final TextEditingController _noteEditController = TextEditingController();
  bool _isEditingNote = false;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ProjectProvider>();
    final project = provider.currentProject!;

    final List<Widget> pages = <Widget>[
      const SourcesPanel(),
      const AiChatPanel(),
      _buildMobileNotesPanel(provider),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(project.name),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        // Add Save/Edit button for notes tab
        actions: [
          if (_selectedIndex == 2)
            // Show a loading indicator while saving
            if (provider.isSavingNote)
              const Padding(
                padding: EdgeInsets.all(16.0),
                child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(color: Colors.white)),
              )
            else
              TextButton(
                onPressed: () async {
                  // Make this async
                  if (_isEditingNote) {
                    // --- SAVE ---
                    // Call the real save method from the provider
                    final success = await provider
                        .saveNoteChanges(_noteEditController.text);
                    if (success) {
                      // Only exit edit mode if save was successful
                      setState(() {
                        _isEditingNote = false;
                      });
                    } else {
                      // Show error snackbar
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text("Error saving note"),
                            backgroundColor: Colors.red),
                      );
                    }
                  } else {
                    // --- EDIT ---
                    // When entering edit mode, set the controller text ONCE.
                    setState(() {
                      _noteEditController.text = provider.scratchpadContent;
                      _isEditingNote = true;
                    });
                  }
                },
                child: Text(
                  _isEditingNote ? "SAVE" : "EDIT",
                  style: const TextStyle(color: Colors.white),
                ),
              ),
        ],
      ),
      body: IndexedStack(
        index: _selectedIndex,
        children: pages,
      ),
      // --- NEW: Add Floating Action Button for Camera ---
      floatingActionButton: _selectedIndex == 2 && _isEditingNote
          ? FloatingActionButton(
              onPressed: () async {
                // Get the current text FROM THE CONTROLLER
              final currentText = _noteEditController.text;

              // Get the image tag from the provider
              // IMPORTANT: We modify takePhotoAndInsertToNote to ONLY do the upload
              // and return the tag. It should NOT modify any state itself.
              final imageTag = await provider.getPhotoAsTag();

              // Update the controller with the new text
              if (imageTag != null) {
                setState(() {
                  _noteEditController.text = currentText + imageTag;
                  _noteEditController.selection = TextSelection.fromPosition(
                    TextPosition(offset: _noteEditController.text.length),
                  );
                });
              }
              },
              child: const Icon(Icons.camera_alt),
            )
          : null,
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) async {
          // Make it async
          if (_isEditingNote) {
            // Auto-save when switching tabs.
            await provider.saveNoteChanges(_noteEditController.text);
            _isEditingNote = false;
          }
          setState(() {
            _selectedIndex = index;
          });
        },
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(
            icon: Icon(Icons.folder_open),
            label: 'Sources',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.chat_bubble_outline),
            label: 'Chat',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.note_alt),
            label: 'Notes',
          ),
        ],
      ),
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
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<FileInfo?> _getOrDownloadImage(
    CacheManager cacheManager,
    String url,
  ) async {
    try {
      // First, try to get from cache
      var fileInfo = await cacheManager.getFileFromCache(url);

      if (fileInfo != null) {
        print("Image loaded from cache: $url");
        return fileInfo;
      }

      // If not in cache, download it
      print("Image not in cache, downloading: $url");
      fileInfo = await cacheManager.downloadFile(url);

      return fileInfo;
    } catch (e) {
      print("Error in _getOrDownloadImage: $e");
      rethrow;
    }
  }
}

  // ADDED BACK THIS MISSING HELPER FUNCTION
  String markdownToHtml(String text) {
      text = text.replaceAllMapped(RegExp(r'\*\*(.*?)\*\*'), (match) => '<b>${match.group(1)}</b>');
      text = text.replaceAllMapped(RegExp(r'\*(.*?)\*'), (match) => '<i>${match.group(1)}</i>');
      text = text.replaceAll('\n', '<br>');
      return text;
  }
}