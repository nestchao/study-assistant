// lib/screens/workspace_panels.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:study_assistance/provider/project_provider.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:super_clipboard/super_clipboard.dart';

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
    // Use an indigo color scheme for selection to match the TabBars
    const Color selectedColor = Colors.indigo;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Material(
        color: isSelected ? selectedColor.withOpacity(0.3) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: isDeleting ? null : onTap, // Disable tap while deleting
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isSelected ? selectedColor : Colors.grey[300]!,
              ),
            ),
            child: Row(
              children: [
                Icon(icon, color: isSelected ? selectedColor : Colors.grey[700]),
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
                // This logic determines which trailing widget to show
                if (isDeleting)
                  const SizedBox(
                    width: 24,
                    height: 24,
                    child: Padding(
                      padding: EdgeInsets.all(4.0),
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                else if (onDelete != null)
                  IconButton(
                    icon: Icon(Icons.delete_outline, color: Colors.grey[600]),
                    onPressed: onDelete,
                    tooltip: 'Delete Source',
                    splashRadius: 20,
                  )
                else if (isSelected)
                  const Icon(Icons.check_circle, color: selectedColor, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// --- PANEL 1: SOURCES ---
class SourcesPanel extends StatelessWidget {
  final ScrollController? scrollController;

  const SourcesPanel({
    super.key,
    this.scrollController, // Make the controller an optional named parameter
  });

  @override
  Widget build(BuildContext context) {
    final p = context.watch<ProjectProvider>();
    final sources = p.sources;
    final selected = p.selectedSource;

    final listView = ListView.builder(
      controller: scrollController,
      padding: const EdgeInsets.all(8), // Add padding around the whole list
      itemCount: sources.length + 1, // +1 for the "All Sources" tile
      itemBuilder: (ctx, i) {
        // First item is always "All Sources"
        if (i == 0) {
          return SourceTile(
            title: 'All Sources',
            icon: Icons.all_inclusive_rounded,
            isSelected: selected == null, // Selected if no specific source is chosen
            onTap: () => p.selectSource(null),
            // No delete button for "All Sources"
          );
        }

        // Adjust index for the sources list
        final s = sources[i - 1];
        
        // Return a SourceTile for each actual source file
        return SourceTile(
          title: s.filename,
          icon: Icons.picture_as_pdf_rounded,
          isSelected: s.id == selected?.id,
          isDeleting: s.id == p.deletingSourceId, // Check if this source is being deleted
          onTap: () => p.selectSource(s),
          onDelete: () => _showDeleteSourceConfirmDialog(context, p, s),
        );
      },
    );

    // This is the UI code that needs correction
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
          // Scrollable List
          Expanded(
            child: p.isLoadingSources
                ? const Center(child: CircularProgressIndicator())
                : scrollController != null
                    ? Scrollbar(controller: scrollController, thumbVisibility: true, child: listView)
                    : listView,
          ),
          // Upload Footer
          _uploadFooter(p, sources),
        ],
      ),
    );
  }

  void _showDeleteSourceConfirmDialog(BuildContext context, ProjectProvider p, Source s) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Source?'),
        content: Text('Are you sure you want to delete "${s.filename}"? This process cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              p.deleteSource(s.id); // Call the provider method
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Widget _uploadFooter(ProjectProvider p, List<Source> s) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration( // Changed to decoration for border
            color: Colors.white,
            border: Border(top: BorderSide(color: Colors.grey[200]!))),
        child: Column(
          children: [
            ElevatedButton.icon(
              onPressed: p.isUploading ? null : p.pickAndUploadFiles,
              icon: p.isUploading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.upload_file),
              label: Text(p.isUploading ? "Uploading..." : "Upload PDFs"),
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.indigo,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 50),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))
              ),
            ),
            if (s.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Text("${s.length} source${s.length > 1 ? 's' : ''} uploaded",
                    style: const TextStyle(fontSize: 12, color: Colors.grey)),
              ),
          ],
        ),
      );
}

// --- PANEL 2: AI CHAT ---
class AiChatPanel extends StatelessWidget {
  const AiChatPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.watch<ProjectProvider>();
    final chat = p.chatHistory;
    final thinking = p.isBotThinking;

    // This is the exact UI code from your old _buildChatPanel method
    return Column(
      children: [
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text("AI Chat", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: chat.length + (thinking ? 1 : 0),
            itemBuilder: (ctx, i) {
              if (i == chat.length && thinking) return _chatBubble("Thinking...", false);
              final msg = chat[i];
              return _chatBubble(msg.content, msg.isUser);
            },
          ),
        ),
        _chatInput(p),
      ],
    );
  }

  // --- Helper widgets for Chat Panel ---
  Widget _chatBubble(String text, bool isUser) => Align(
    alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
    child: Container(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isUser ? Colors.blue : Colors.grey[200],
        borderRadius: BorderRadius.circular(16),
      ),
      child: isUser ? Text(text, style: const TextStyle(color: Colors.white)) : Html(data: text),
    ),
  );

  Widget _chatInput(ProjectProvider p) => Container(
    padding: const EdgeInsets.all(12),
    color: Colors.grey[100],
    child: Row(
      children: [
        Expanded(
          child: TextField(
            controller: p.chatController,
            decoration: InputDecoration(
              hintText: "Ask a question...",
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(25)),
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
  void _sendChat(ProjectProvider p) {
    final q = p.chatController.text.trim();
    if (q.isNotEmpty) {
      p.askQuestion(q);
      p.chatController.clear();
    }
  }
}

// --- PANEL 3: STUDY NOTE ---
class NotesPanel extends StatelessWidget {
  const NotesPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.watch<ProjectProvider>();
    final html = p.scratchpadContent;

    return Container(
      color: Colors.white,
      child: Column(
        children: [
          _buildPanelHeader("Study Note", Icons.edit_note_rounded, Colors.green),
          Expanded(
            child: Container(
              color: Colors.grey[50],
              child: p.isLoadingNote
                  ? _buildNoteLoadingState()
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Container(
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

  // --- Helper widgets for Notes Panel ---
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
          Text(title,
              style:
                  const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
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
            Text("Loading AI study note...",
                style: TextStyle(color: Colors.grey)),
          ],
        ),
      ),
    );
  }

  Widget _buildScratchpadActions(
      BuildContext context, ProjectProvider p, String html) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Colors.grey[200]!))),
      child: SingleChildScrollView( // Added to prevent overflow on small mobile screens
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: p.selectedSource == null
                        ? null
                        : () => p.getNoteForSelectedSource(),
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text("Reload"),
                    style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _copyRichTextToClipboard(context, html),
                    icon: const Icon(Icons.copy_all_rounded),
                    label: const Text("Copy"),
                    style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12)),
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            const Text("Generate Custom Note",
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            TextField(
              controller: p.topicController,
              decoration: InputDecoration(
                hintText: "e.g., Explain the main theories...",
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                filled: true,
                fillColor: Colors.grey[100],
              ),
            ),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: () {
                final topic = p.topicController.text.trim();
                if (topic.isNotEmpty) {
                  p.generateTopicNote(topic);
                  FocusScope.of(context).unfocus();
                }
              },
              icon: const Icon(Icons.auto_awesome_rounded),
              label: const Text("Generate"),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.amber[700],
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _stripHtmlTags(String html) {
    final RegExp exp = RegExp(r"<[^>]*>", multiLine: true, caseSensitive: true);
    return html.replaceAll(exp, '').replaceAll('&nbsp;', ' ');
  }

  Future<void> _copyRichTextToClipboard(
      BuildContext context, String html) async {
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
}