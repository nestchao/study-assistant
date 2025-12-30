// lib/screens/desktop_study_layout.dart
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:study_assistance/provider/project_provider.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:study_assistance/screens/workspace_panels.dart';
import 'package:super_clipboard/super_clipboard.dart';
import 'package:study_assistance/widgets/firestore_image.dart';

class DesktopStudyLayout extends StatefulWidget {
  const DesktopStudyLayout({super.key});

  @override
  State<DesktopStudyLayout> createState() => _DesktopStudyLayoutState();
}

class _DesktopStudyLayoutState extends State<DesktopStudyLayout> {
  // All desktop-specific state and controllers
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
        leading: const Padding(
          padding: EdgeInsets.only(left: 16.0),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text("View Panels", style: TextStyle(color: Colors.black54, fontSize: 16)),
          ),
        ),
        leadingWidth: 150,
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

  Widget _noteActions(BuildContext ctx, ProjectProvider p, String html) {
    // A helper to build a dropdown item
    DropdownMenuItem<Source?> buildDropdownItem(Source? source) {
      return DropdownMenuItem<Source?>(
        value: source,
        child: Row(
          children: [
            Icon(
              source == null ? Icons.all_inclusive : Icons.picture_as_pdf,
              size: 18,
              color: Colors.black54,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                source?.filename ?? "Project Overview",
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text("Note Controls", style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),

          // --- 1. THE NEW NOTE SELECTOR DROPDOWN ---
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12.0),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(8.0),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<Source?>(
                isExpanded: true,
                value: p.selectedSource,
                // Create a list of items: "Project Overview" + all sources
                items: [
                  buildDropdownItem(null), // The "Project Overview" option
                  ...p.sources.map((s) => buildDropdownItem(s)),
                ],
                onChanged: (Source? source) {
                  // When a new source is selected, call the provider method
                  p.selectSource(source);
                },
              ),
            ),
          ),
          const SizedBox(height: 12),

          // --- 2. THE NEW REGENERATE BUTTON & COPY BUTTON ---
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: p.selectedSource == null || p.isRegeneratingNote
                      ? null // Disable if no source is selected or if already regenerating
                      : () => p.regenerateNoteForSelectedSource(),
                  icon: p.isRegeneratingNote && p.selectedSource != null
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.auto_awesome),
                  label: Text(p.isRegeneratingNote && p.selectedSource != null ? "Working..." : "Regenerate"),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      const SnackBar(content: Text("Preparing note for copying...")),
                    );
                    final String richHtml = await p.getNoteAsRichHtml();
                    await _copyRichTextToClipboard(ctx, richHtml);
                    ScaffoldMessenger.of(ctx).hideCurrentSnackBar();
                  },
                  icon: const Icon(Icons.copy),
                  label: const Text("Copy Note"),
                ),
              ),
              const SizedBox(width: 8),

              // 3. NEW: PDF Export Button
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => p.exportCurrentNoteToPdf(ctx),
                  icon: const Icon(Icons.picture_as_pdf, size: 18),
                  label: const Text("PDF", style: TextStyle(fontSize: 12)),
                  style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8)),
                ),
              ),
            ],
          ),

          const Divider(height: 24),
          const Text("Generate Custom Note From Topic", style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          TextField(
            controller: p.topicController,
            maxLines: 2,
            decoration: const InputDecoration(
              hintText: "e.g. Explain Object-Oriented Programming",
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.all(12),
            ),
          ),
          const SizedBox(height: 8),
          ElevatedButton.icon(
            onPressed: () {
              final t = p.topicController.text.trim();
              if (t.isNotEmpty) p.generateTopicNote(t);
            },
            icon: const Icon(Icons.psychology),
            label: const Text("Generate Topic Note"),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
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