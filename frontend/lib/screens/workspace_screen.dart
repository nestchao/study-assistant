// lib/screens/workspace_screen.dart
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:study_assistance/provider/project_provider.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:super_clipboard/super_clipboard.dart';
import 'package:study_assistance/screens/workspace_panels.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:study_assistance/services/firestore_image_service.dart';
import 'package:study_assistance/widgets/firestore_image.dart';

class WorkspaceScreen extends StatelessWidget {
  const WorkspaceScreen({super.key});

  // Define a breakpoint. Anything narrower than this will be considered "mobile".
  static const double mobileBreakpoint = 600.0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < mobileBreakpoint) {
          // If the screen is narrow, show the mobile layout
          return const MobileWorkspaceLayout();
        } else {
          // If the screen is wide, show the desktop layout
          return const DesktopWorkspaceLayout();
        }
      },
    );
  }
}

class DesktopWorkspaceLayout extends StatefulWidget {
  const DesktopWorkspaceLayout({super.key});

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

  @override
  void dispose() {
    _sourcesScrollController.dispose();
    _notesScrollController.dispose();
    _noteEditController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ProjectProvider>();
    final project = provider.currentProject!;
    final int visibleCount = (_isSourcesVisible ? 1 : 0) +
        (_isChatVisible ? 1 : 0) +
        (_isNotesVisible ? 1 : 0);
    final double screenWidth = MediaQuery.of(context).size.width;

    return Scaffold(
      appBar: AppBar(
        title: Text(project.name),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        // --- RESTORED AppBar actions ---
        actions: [
          _buildVisibilityToggleButton(
            tooltip: 'Toggle Sources',
            icon: Icons.folder_open,
            color: Colors.blue[300]!,
            isVisible: _isSourcesVisible,
            onPressed: () => _togglePanelVisibility('sources'),
            isDisabled: _isSourcesVisible && visibleCount == 1,
          ),
          _buildVisibilityToggleButton(
            tooltip: 'Toggle AI Chat',
            icon: Icons.chat_bubble_outline,
            color: Colors.purple[300]!,
            isVisible: _isChatVisible,
            onPressed: () => _togglePanelVisibility('chat'),
            isDisabled: _isChatVisible && visibleCount == 1,
          ),
          _buildVisibilityToggleButton(
            tooltip: 'Toggle Notes',
            icon: Icons.note_alt,
            color: Colors.green[300]!,
            isVisible: _isNotesVisible,
            onPressed: () => _togglePanelVisibility('notes'),
            isDisabled: _isNotesVisible && visibleCount == 1,
          ),
          const SizedBox(width: 8),
        ],
      ),

      // In your build method...

      body: Row(
        children: [
          // --- SOURCES PANEL (Left) ---
          if (_isSourcesVisible)
            _isChatVisible
                ? SizedBox(
                    width: _sourcesWidth,
                    // PASS THE CONTROLLER HERE
                    child: SourcesPanel(
                        scrollController: _sourcesScrollController),
                  )
                : Expanded(
                    flex: _sourcesWidth.round(),
                    // AND PASS IT HERE
                    child: SourcesPanel(
                        scrollController: _sourcesScrollController),
                  ),

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

          // --- CHAT PANEL (Center) ---
          if (_isChatVisible) const Expanded(child: AiChatPanel()),

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

          // --- NOTES PANEL (Right) ---
          if (_isNotesVisible)
            _isChatVisible
                ? SizedBox(
                    width: _notesWidth,
                    child: _buildScratchpadPanel(context, provider),
                  )
                : Expanded(
                    flex: _notesWidth.round(),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        return SizedBox(
                          width: constraints.maxWidth,
                          height: constraints.maxHeight,
                          child: _buildScratchpadPanel(context, provider),
                        );
                      },
                    ),
                  ),
        ],
      ),
    );
  }

  // In _WorkspaceScreenState

  void _togglePanelVisibility(String panel) {
    setState(() {
      // --- Logic for enabling the chat panel ---
      if (panel == 'chat' && !_isChatVisible) {
        _isChatVisible = true;

        // Get total screen width to perform calculations
        final double screenWidth = MediaQuery.of(context).size.width;

        // Define a target width for the re-opened chat panel
        const double targetChatWidth = 400.0;

        // Calculate the current combined width of the side panels
        final currentSidePanelsWidth = (_isSourcesVisible ? _sourcesWidth : 0) +
            (_isNotesVisible ? _notesWidth : 0);

        // Calculate the available space for the side panels
        final availableSpaceForSidePanels =
            screenWidth - targetChatWidth - 16; // 16 for 2 resizers

        // If the side panels are too big for the chat to re-open comfortably...
        if (currentSidePanelsWidth > availableSpaceForSidePanels) {
          // Calculate the overflow amount
          final overflow = currentSidePanelsWidth - availableSpaceForSidePanels;

          // Shrink the visible side panels proportionally
          if (_isSourcesVisible && _isNotesVisible) {
            double sourcesProportion = _sourcesWidth / currentSidePanelsWidth;
            double notesProportion = _notesWidth / currentSidePanelsWidth;
            _sourcesWidth -= overflow * sourcesProportion;
            _notesWidth -= overflow * notesProportion;
          } else if (_isSourcesVisible) {
            _sourcesWidth -= overflow;
          } else if (_isNotesVisible) {
            _notesWidth -= overflow;
          }
        }
        return; // Exit after handling this special case
      }

      // --- Original logic for all other cases ---
      bool isDisablingSources = (panel == 'sources' && _isSourcesVisible);
      bool isDisablingChat = (panel == 'chat' && _isChatVisible);
      bool isDisablingNotes = (panel == 'notes' && _isNotesVisible);

      int visibleCount = (_isSourcesVisible ? 1 : 0) +
          (_isChatVisible ? 1 : 0) +
          (_isNotesVisible ? 1 : 0);

      if (visibleCount > 1) {
        if (isDisablingSources) _isSourcesVisible = false;
        if (isDisablingChat) _isChatVisible = false;
        if (isDisablingNotes) _isNotesVisible = false;
      }

      if (panel == 'sources' && !_isSourcesVisible) {
        _isSourcesVisible = true;
        _sourcesWidth = 280.0;
      }
      if (panel == 'notes' && !_isNotesVisible) {
        _isNotesVisible = true;
        _notesWidth = 400.0;
      }
    });
  }

  // Replace the old helper method with this one
  // In _WorkspaceScreenState

  Widget _buildVisibilityToggleButton({
    required String tooltip,
    required IconData icon,
    required Color color,
    required bool isVisible,
    required VoidCallback onPressed,
    required bool isDisabled,
  }) {
    return IconButton(
      tooltip: tooltip,
      icon: Icon(icon), // Icon color is now managed by the style
      // Style the button itself
      style: IconButton.styleFrom(
        foregroundColor: color,
        backgroundColor:
            isVisible ? color.withOpacity(0.20) : Colors.transparent,
        // Make the disabled state more obvious
        disabledForegroundColor: color.withOpacity(0.3),
      ),
      // Disable the button if it's the last one visible
      onPressed: isDisabled ? null : onPressed,
    );
  }

  Widget _buildResizer({required GestureDragUpdateCallback onDrag}) {
    return GestureDetector(
      onHorizontalDragUpdate: onDrag,
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeLeftRight,
        child: Container(
          width: 8,
          color: Colors.grey[300],
        ),
      ),
    );
  }

  String _stripHtmlTags(String html) {
    final RegExp exp = RegExp(r"<[^>]*>", multiLine: true, caseSensitive: true);
    return html.replaceAll(exp, '');
  }

  Future<void> _copyRichTextToClipboard(
      BuildContext context, String html) async {
    final item = DataWriterItem();
    item.add(Formats.htmlText(html));
    final plainText = _stripHtmlTags(html).trim();
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

  // --- EXISTING PANEL BUILDERS (Slightly modified to accept provider) ---

  Widget _buildSourcesPanel(BuildContext context, ProjectProvider p) {
    final sources = p.sources;
    final selected = p.selectedSource;

    return Container(
      color: Colors.white,
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.blue[50],
              border: Border(bottom: BorderSide(color: Colors.grey[300]!)),
            ),
            child: Row(children: [
              Icon(Icons.folder_open, color: Colors.blue[700]),
              const SizedBox(width: 8),
              const Text("Sources",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ]),
          ),

          // SCROLLABLE LIST with controller
          Expanded(
            child: p.isLoadingSources
                ? const Center(child: CircularProgressIndicator())
                : sources.isEmpty
                    ? _emptySources()
                    : Scrollbar(
                        controller: _sourcesScrollController, // Add controller
                        thumbVisibility: true,
                        thickness: 8.0,
                        radius: const Radius.circular(4),
                        child: ListView.builder(
                          controller:
                              _sourcesScrollController, // Add controller here too
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          itemBuilder: (ctx, i) {
                            final s = sources[i];
                            final active = s.id == selected?.id;
                            return Card(
                              margin: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              color: active ? Colors.blue[600] : null,
                              child: ListTile(
                                leading: Icon(Icons.picture_as_pdf,
                                    color: active
                                        ? Colors.white
                                        : Colors.red[700]),
                                title: Text(s.filename,
                                    style: TextStyle(
                                        color: active ? Colors.white : null)),
                                onTap: () => p.selectSource(s),
                              ),
                            );
                          },
                          itemCount: sources.length,
                        ),
                      ),
          ),

          // Upload Footer
          _uploadFooter(p, sources),
        ],
      ),
    );
  }

  Widget _buildChatPanel(BuildContext context, ProjectProvider p) {
    final chat = p.chatHistory;
    final thinking = p.isBotThinking;
    // The rest of this method's content is EXACTLY the same as your previous version.
    return Column(
      children: [
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text("AI Chat",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: chat.length + (thinking ? 1 : 0),
            itemBuilder: (ctx, i) {
              if (i == chat.length && thinking) {
                return _chatBubble("Thinking...", false);
              }
              final msg = chat[i];
              return _chatBubble(msg.content, msg.isUser);
            },
          ),
        ),
        _chatInput(p),
      ],
    );
  }

  Widget _chatBubble(String text, bool isUser) {
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isUser ? Colors.blue : Colors.grey[200],
          borderRadius: BorderRadius.circular(16),
        ),
        child: isUser
            ? Text(text, style: const TextStyle(color: Colors.white))
            : Html(data: text),
      ),
    );
  }

  Widget _chatInput(ProjectProvider p) {
    return Container(
      padding: const EdgeInsets.all(12),
      color: Colors.grey[100],
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: p.chatController,
              decoration: InputDecoration(
                hintText: "Ask a question...",
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(25)),
                filled: true,
                fillColor: Colors.white,
              ),
              onSubmitted: (_) => _sendChat(p),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.send, color: Colors.blue),
            onPressed: () => _sendChat(p),
          ),
        ],
      ),
    );
  }

  void _sendChat(ProjectProvider p) {
    final q = p.chatController.text.trim();
    if (q.isNotEmpty) {
      p.askQuestion(q);
      p.chatController.clear();
    }
  }

  Widget _buildScratchpadPanel(BuildContext context, ProjectProvider p) {
    final html = p.scratchpadContent;

    if (_isEditingNote && _noteEditController.text.isEmpty) {
      _noteEditController.text = html;
    }

    return Container(
      color: Colors.white,
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.green[50],
            child: Row(children: [
              Icon(Icons.note_alt, color: Colors.green[700]),
              const SizedBox(width: 8),
              const Text("Study Notes",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ]),
          ),

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
