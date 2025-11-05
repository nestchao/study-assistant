// lib/screens/workspace_panels.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:study_assistance/provider/project_provider.dart';
import 'package:flutter_html/flutter_html.dart';

// --- PANEL 1: SOURCES ---
class SourcesPanel extends StatelessWidget {

  final ScrollController? scrollController;
  const SourcesPanel({
    super.key,
    this.scrollController, // Make the controller optional
  });

  @override
  Widget build(BuildContext context) {
    final p = context.watch<ProjectProvider>();
    final sources = p.sources;
    final selected = p.selectedSource;

    final scrollableList = ListView.builder(
      controller: scrollController, // <-- USE THE PASSED-IN CONTROLLER
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemBuilder: (ctx, i) {
        final s = sources[i];
        final active = s.id == selected?.id;
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          color: active ? Colors.blue[600] : null,
          child: ListTile(
            leading: Icon(Icons.picture_as_pdf, color: active ? Colors.white : Colors.red[700]),
            title: Text(s.filename, style: TextStyle(color: active ? Colors.white : null)),
            onTap: () => p.selectSource(s),
          ),
        );
      },
      itemCount: sources.length,
    );

    // This is the exact UI code from your old _buildSourcesPanel method
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
              const Text("Sources", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ]),
          ),
          // Scrollable List
          Expanded(
            child: p.isLoadingSources
                ? const Center(child: CircularProgressIndicator())
                : sources.isEmpty
                ? _emptySources()
            // --- UPDATE THE LOGIC HERE ---
            // If a controller was provided, wrap the list in a Scrollbar
                : scrollController != null
                ? Scrollbar(
              controller: scrollController,
              thumbVisibility: true,
              child: scrollableList,
            )
            // Otherwise, just show the list
                : scrollableList,
          ),
          // Upload Footer
          _uploadFooter(p, sources),
        ],
      ),
    );
  }

  // --- Helper widgets for Sources Panel ---
  Widget _emptySources() => Center(
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.upload_file, size: 64, color: Colors.grey[400]),
      Text("No PDFs yet", style: TextStyle(color: Colors.grey[600])),
      Text("Tap below to upload", style: TextStyle(color: Colors.grey[500])),
    ]),
  );
  Widget _uploadFooter(ProjectProvider p, List<Source> s) => Container(
    padding: const EdgeInsets.all(12),
    color: Colors.grey[50],
    child: Column(children: [
      ElevatedButton.icon(
        onPressed: p.isUploading ? null : p.pickAndUploadFiles,
        icon: p.isUploading
            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white))
            : const Icon(Icons.upload_file),
        label: Text(p.isUploading ? "Uploading..." : "Upload PDFs"),
        style: ElevatedButton.styleFrom(backgroundColor: Colors.blue[600], minimumSize: const Size(double.infinity, 50)),
      ),
      if (s.isNotEmpty) Text("${s.length} source${s.length > 1 ? 's' : ''}", style: const TextStyle(fontSize: 12, color: Colors.grey)),
    ]),
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

// NOTE: The Notes panel is more complex because it has its own state (_isEditingNote).
// For the mobile layout, you've already created a good implementation.
// For the desktop layout, you can keep the _buildScratchpadPanel method inside the
// _DesktopWorkspaceLayoutState since its editing state is tied to that specific layout.