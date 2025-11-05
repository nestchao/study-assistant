// frontend/lib/screens/workspace_screen.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:study_assistance/provider/project_provider.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:super_clipboard/super_clipboard.dart';

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
    return Consumer<ProjectProvider>(
      builder: (context, provider, child) {
        final project = provider.currentProject!;

        return Scaffold(
          backgroundColor: Colors.grey[100],
          appBar: AppBar(
            title: Text(project.name,
                style: const TextStyle(color: Colors.black87)),
            backgroundColor: Colors.white,
            elevation: 1.0,
            iconTheme: const IconThemeData(color: Colors.black54),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () {
                // Clear selected source when leaving
                provider.selectSource(null);
                Navigator.pop(context);
              },
            ),
          ),
          body: Row(
            children: [
              // Use Flexible for a more responsive layout
              Flexible(
                flex: 2, // Takes up 2/7 of the space
                child: _buildSourcesPanel(
                    context, provider, provider.sources, provider.selectedSource),
              ),
              _buildResizer(),
              Flexible(
                flex: 3, // Takes up 3/7 of the space
                child: _buildChatPanel(
                    context, provider, provider.chatHistory, provider.isBotThinking),
              ),
              _buildResizer(),
              Flexible(
                flex: 3, // Takes up 3/7 of the space
                child: _buildScratchpadPanel(
                    context, provider, provider.scratchpadContent),
              ),
            ],
          ),
        );
      },
    );
  }

  // --- REBUILT SOURCES PANEL ---
  Widget _buildSourcesPanel(
      BuildContext context, ProjectProvider p, List<Source> sources, Source? selected) {
    return Container(
      color: Colors.white,
      color: Colors.white,
      child: Column(
        children: [
          _buildPanelHeader(
              "Sources", Icons.folder_open_rounded, Colors.indigo),
          Expanded(
            child: p.isLoadingSources
                ? const Center(child: CircularProgressIndicator())
                : sources.isEmpty
                    ? _buildSourcesEmptyState()
                    : ListView.builder(
                        itemCount: sources.length + 1, // +1 for "All Sources"
                        padding: const EdgeInsets.all(8),
                        itemBuilder: (ctx, i) {
                          if (i == 0) {
                             // "All Sources" Option
                            final isSelected = selected == null;
                            return _buildSourceTile(
                                'All Sources', Icons.all_inclusive, isSelected, () => p.selectSource(null));
                          }
                          final s = sources[i-1];
                          final isSelected = s.id == selected?.id;
                          return _buildSourceTile(s.filename, Icons.picture_as_pdf_rounded, isSelected, () => p.selectSource(s));
                        },
                      ),
          ),
          const Divider(height: 1),
          Container(
            padding: const EdgeInsets.all(12),
            child: ElevatedButton.icon(
              onPressed: p.isUploading ? null : () => p.pickAndUploadFiles(),
              icon: p.isUploading
                  ? const SizedBox(
                      width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.upload_file_rounded),
              label: Text(p.isUploading ? "Uploading..." : "Upload PDFs"),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.indigo,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 50),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSourceTile(String title, IconData icon, bool isSelected, VoidCallback onTap) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4.0),
        child: Material(
          color: isSelected ? Colors.indigo.withOpacity(0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: isSelected ? Colors.indigo : Colors.transparent),
              ),
              child: Row(
                children: [
                  Icon(icon, color: isSelected ? Colors.indigo : Colors.grey[700]),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        color: Colors.black87,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (isSelected) const Icon(Icons.check_circle, color: Colors.indigo, size: 20),
                ],
              ),
            ),
          ),
        ),
      );
  }

  Widget _buildSourcesEmptyState() {
     return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.upload_file_outlined, size: 64, color: Colors.grey[300]),
            const SizedBox(height: 16),
            Text("No PDFs uploaded", style: TextStyle(color: Colors.grey[600], fontSize: 16)),
            const SizedBox(height: 8),
            Text("Click below to add sources", style: TextStyle(color: Colors.grey[500])),
          ],
        ),
      ),
    );
  }

  // --- REBUILT CHAT PANEL ---
  Widget _buildChatPanel(
      BuildContext context, ProjectProvider p, List<ChatMessage> chat, bool thinking) {
    ScrollController scrollController = ScrollController();
    // Scroll to bottom when new message appears
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (scrollController.hasClients) {
        scrollController.animateTo(
          scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });

    return Container(
      color: Colors.grey[50],
      child: Column(
        children: [
           _buildPanelHeader(
              "AI Chat", Icons.smart_toy_rounded, Colors.blue),
          Expanded(
            child: ListView.builder(
              controller: scrollController,
              padding: const EdgeInsets.all(16),
              itemCount: chat.length + (thinking ? 1 : 0),
              itemBuilder: (ctx, i) {
                if (i == chat.length && thinking) {
                  return _buildThinkingIndicator();
                }
                final msg = chat[i];
                return _chatBubble(msg.content, msg.isUser);
              },
            ),
          ),
          _chatInput(p),
        ],
      ),
    );
  }

  Widget _chatBubble(String text, bool isUser) {
    final alignment = isUser ? Alignment.centerRight : Alignment.centerLeft;
    final color = isUser ? Colors.indigo : Colors.white;
    final textColor = isUser ? Colors.white : Colors.black87;
    final borderRadius = isUser
        ? const BorderRadius.only(
            topLeft: Radius.circular(16),
            bottomLeft: Radius.circular(16),
            bottomRight: Radius.circular(16),
          )
        : const BorderRadius.only(
            topRight: Radius.circular(16),
            bottomLeft: Radius.circular(16),
            bottomRight: Radius.circular(16),
          );

    return Align(
      alignment: alignment,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.all(14),
        constraints: const BoxConstraints(maxWidth: 500),
        decoration: BoxDecoration(
          color: color,
          borderRadius: borderRadius,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 5,
              offset: const Offset(0, 2),
            )
          ],
        ),
        child: isUser
            ? Text(text, style: TextStyle(color: textColor, fontSize: 15))
            : Html(data: text),
      ),
    );
  }

  // NEW: Animated "Thinking..." indicator
  Widget _buildThinkingIndicator() {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: const BorderRadius.only(
            topRight: Radius.circular(16),
            bottomLeft: Radius.circular(16),
            bottomRight: Radius.circular(16),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 5,
              offset: const Offset(0, 2),
            )
          ],
        ),
        child: const _TypingIndicator(), // Use the animated widget
      ),
    );
  }

  Widget _chatInput(ProjectProvider p) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey[200]!)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: p.chatController,
              decoration: InputDecoration(
                hintText: "Ask a question about your sources...",
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                filled: true,
                fillColor: Colors.grey[100],
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              ),
              onSubmitted: (_) => _sendChat(p),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            style: IconButton.styleFrom(
              backgroundColor: Colors.indigo,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.all(14),
            ),
            icon: const Icon(Icons.send_rounded, color: Colors.white),
            onPressed: () => _sendChat(p),
          ),
        ],
      ),
    );
  }

  void _sendChat(ProjectProvider p) {
    final q = p.chatController.text.trim();
    if (q.isNotEmpty && !p.isBotThinking) {
      p.askQuestion(q);
      p.chatController.clear();
    }
  }

  // --- REBUILT SCRATCHPAD PANEL ---
  Widget _buildScratchpadPanel(BuildContext context, ProjectProvider p, String html) {
    return Container(
      color: Colors.white,
      color: Colors.white,
      child: Column(
        children: [
          _buildPanelHeader(
              "Study Note", Icons.edit_note_rounded, Colors.green),
          Expanded(
            child: Container(
              color: Colors.grey[50],
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: p.isLoadingNote
                    ? _buildNoteLoadingState()
                    : Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey[200]!),
                        ),
                        padding: const EdgeInsets.all(16),
                        child: SelectionArea(child: Html(data: html)),
                      ),
              ),
            ),
          ),
          _buildScratchpadActions(context, p, html),
        ],
      ),
    );
  }

  Widget _buildNoteLoadingState() {
     return const Center(
      child: Padding(
        padding: EdgeInsets.all(20.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text("Generating AI study note...", style: TextStyle(color: Colors.grey)),
          ],
        ),
      ),
    );
  }

  Widget _buildScratchpadActions(BuildContext context, ProjectProvider p, String html) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Colors.grey[200]!))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: p.selectedSource == null ? null : () => p.getNoteForSelectedSource(),
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text("Reload Source Note"),
                  style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _copyRichTextToClipboard(context, html),
                  icon: const Icon(Icons.copy_all_rounded),
                  label: const Text("Copy Note"),
                   style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12)),
                ),
              ),
            ],
          ),
          const Divider(height: 24),
          const Text("Generate Custom Note", style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          TextField(
            controller: p.topicController,
            maxLines: 2,
            decoration: InputDecoration(
              hintText: "e.g., Explain the main theories...",
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              filled: true,
              fillColor: Colors.grey[100],
            ),
          ),
          const SizedBox(height: 8),
          ElevatedButton.icon(
            onPressed: () {
              final topic = p.topicController.text.trim();
              if (topic.isNotEmpty) p.generateTopicNote(topic);
            },
            icon: const Icon(Icons.auto_awesome_rounded),
            label: const Text("Generate"),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.amber[700],
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ],
      ),
    );
  }

  // --- HELPER WIDGETS ---
  
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

  String _stripHtmlTags(String html) {
    final RegExp exp = RegExp(r"<[^>]*>", multiLine: true, caseSensitive: true);
    return html.replaceAll(exp, '').replaceAll('&nbsp;', ' ');
  }

  Future<void> _copyRichTextToClipboard(BuildContext context, String html) async {
    final item = DataWriterItem();
    item.add(Formats.htmlText(html));
    final plainText = _stripHtmlTags(html).trim();
    item.add(Formats.plainText(plainText));

    await SystemClipboard.instance?.write([item]);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Formatted note copied!"),
        backgroundColor: Colors.green,
      ),
    );
  }

  Widget _buildResizer() {
    return Container(width: 1, color: Colors.grey[300]);
  }
}


// --- NEW WIDGET FOR ANIMATED TYPING INDICATOR ---
class _TypingIndicator extends StatefulWidget {
  const _TypingIndicator();

  @override
  _TypingIndicatorState createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<_TypingIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (index) {
            final dotOffset = (index == 1) ? 0.25 : 0.0;
            final dotDelay = (index * 0.25);
            final animationValue = (_controller.value - dotDelay).clamp(0.0, 1.0);
            
            // A simple sine wave for the up/down motion
            final y = -4 * (0.5 - (0.5 - animationValue).abs()) * 2;
            
            return Transform.translate(
              offset: Offset(0, y),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: Colors.grey[400],
                  shape: BoxShape.circle,
                ),
              ),
            );
          }),
        );
      },
    );
  }
}
