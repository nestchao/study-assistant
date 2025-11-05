import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:study_assistance/provider/project_provider.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:flutter/services.dart';
import 'package:super_clipboard/super_clipboard.dart';


class WorkspaceScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Consumer<ProjectProvider>(
      builder: (context, provider, child) {
        final project = provider.currentProject!;
        final sources = provider.sources;
        final selected = provider.selectedSource;
        final scratchpad = provider.scratchpadContent;
        final chat = provider.chatHistory;
        final thinking = provider.isBotThinking;

        return Scaffold(
          backgroundColor: Colors.grey[100], // Consistent background
          appBar: AppBar(
            title: Text(project.name, style: const TextStyle(color: Colors.black87)),
            backgroundColor: Colors.white,
            elevation: 1.0,
            iconTheme: const IconThemeData(color: Colors.black54), // Back button color
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          body: Row(
            children: [
              // LEFT: Sources
              _buildSourcesPanel(context, provider, sources, selected),
              _buildResizer(),
              // CENTER: Chat
              _buildChatPanel(context, provider, chat, thinking),
              _buildResizer(),
              // RIGHT: Scratchpad + Topic Generator
              _buildScratchpadPanel(context, provider, scratchpad),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSourcesPanel(BuildContext context, ProjectProvider p, List<Source> sources, Source? selected) {
    return Container(
      width: 280,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(right: BorderSide(color: Colors.grey[300]!, width: 1)),
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.blue[50],
              border: Border(bottom: BorderSide(color: Colors.grey[300]!)),
            ),
            child: Row(
              children: [
                Icon(Icons.folder_open, color: Colors.blue[700]),
                const SizedBox(width: 8),
                const Text(
                  "Sources",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          
          // Sources List
          Expanded(
            child: p.isLoadingSources
                ? const Center(child: CircularProgressIndicator())
                : sources.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.upload_file, size: 64, color: Colors.grey[400]),
                              const SizedBox(height: 16),
                              Text(
                                "No PDFs uploaded yet",
                                style: TextStyle(color: Colors.grey[600], fontSize: 16),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                "Click below to upload",
                                style: TextStyle(color: Colors.grey[500], fontSize: 14),
                              ),
                            ],
                          ),
                        ),
                      )
                    : ListView.builder(
                        itemCount: sources.length,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemBuilder: (ctx, i) {
                          final s = sources[i];
                          final isSelected = s.id == selected?.id;
                          
                          return Container(
                            margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: isSelected ? Colors.blue[500] : Colors.white,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: isSelected ? Colors.blue[700]! : Colors.grey[300]!,
                                width: isSelected ? 2 : 1,
                              ),
                              boxShadow: isSelected
                                  ? [
                                      BoxShadow(
                                        color: Colors.blue.withOpacity(0.3),
                                        blurRadius: 8,
                                        offset: const Offset(0, 2),
                                      )
                                    ]
                                  : [],
                            ),
                            child: ListTile(
                              leading: Icon(
                                Icons.picture_as_pdf,
                                color: isSelected ? Colors.white : Colors.red[700],
                              ),
                              title: Text(
                                s.filename,
                                style: TextStyle(
                                  color: isSelected ? Colors.white : Colors.black87,
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                  fontSize: 14,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              trailing: isSelected
                                  ? const Icon(Icons.check_circle, color: Colors.white)
                                  : Icon(Icons.chevron_right, color: Colors.grey[400]),
                              onTap: () => p.selectSource(s),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          );
                        },
                      ),
          ),
          
          const Divider(height: 1),
          
          // Upload Button
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              border: Border(top: BorderSide(color: Colors.grey[300]!)),
            ),
            child: Column(
              children: [
                ElevatedButton.icon(
                  onPressed: p.isUploading ? null : () => p.pickAndUploadFiles(),
                  icon: p.isUploading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : const Icon(Icons.upload_file),
                  label: Text(p.isUploading ? "Uploading..." : "Upload PDFs"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue[600],
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 50),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    elevation: p.isUploading ? 0 : 2,
                  ),
                ),
                if (sources.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    "${sources.length} source${sources.length > 1 ? 's' : ''} uploaded",
                    style: TextStyle(color: Colors.grey[600], fontSize: 12),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChatPanel(BuildContext context, ProjectProvider p, List<ChatMessage> chat, bool thinking) {
    return Expanded(
      child: Column(
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
      ),
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
  }

  void _sendChat(ProjectProvider p) {
    final q = p.chatController.text.trim();
    if (q.isNotEmpty) {
      p.askQuestion(q);
      p.chatController.clear();
    }
  }

  Widget _buildScratchpadPanel(BuildContext context, ProjectProvider p, String html) {
    return Container(
      width: 400,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(left: BorderSide(color: Colors.grey[300]!, width: 1)),
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.green[50],
              border: Border(bottom: BorderSide(color: Colors.grey[300]!)),
            ),
            child: Row(
              children: [
                Icon(Icons.note_alt, color: Colors.green[700]),
                const SizedBox(width: 8),
                const Text(
                  "Study Notes",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          
          // Note Content
          Expanded(
            child: Container(
              color: Colors.grey[50],
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: p.isLoadingNote
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const CircularProgressIndicator(),
                            const SizedBox(height: 16),
                            Text(
                              "Generating AI study note...",
                              style: TextStyle(color: Colors.grey[600]),
                            ),
                          ],
                        ),
                      )
                    : Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey[300]!),
                        ),
                        padding: const EdgeInsets.all(16),
                        child: Html(data: html),
                      ),
              ),
            ),
          ),
          
          // Actions
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: Colors.grey[300]!)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Show Source Note Button
                ElevatedButton.icon(
                  onPressed: p.selectedSource == null ? null : () => p.getNoteForSelectedSource(),
                  icon: const Icon(Icons.refresh),
                  label: const Text("Reload Source Note"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue[600],
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 45),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
                
                const SizedBox(height: 8),
                
                // Copy Note Button
                OutlinedButton.icon(
                  // 2. CALL THE NEW COPY FUNCTION
                  onPressed: () => _copyRichTextToClipboard(context, html),
                  icon: const Icon(Icons.copy),
                  label: const Text("Copy Note"),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.green[700],
                    minimumSize: const Size(double.infinity, 45),
                    side: BorderSide(color: Colors.green[300]!),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
                
                const Divider(height: 24),
                
                // Custom Topic Generator
                Text(
                  "Generate Custom Note",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[700],
                  ),
                ),
                const SizedBox(height: 8),
                
                TextField(
                  controller: p.topicController,
                  maxLines: 3,
                  decoration: InputDecoration(
                    hintText: "e.g., Summarize key concepts about object-oriented programming",
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    filled: true,
                    fillColor: Colors.yellow[50],
                  ),
                ),
                
                const SizedBox(height: 8),
                
                ElevatedButton.icon(
                  onPressed: () {
                    final topic = p.topicController.text.trim();
                    if (topic.isNotEmpty) p.generateTopicNote(topic);
                  },
                  icon: const Icon(Icons.auto_awesome),
                  label: const Text("Generate Custom Note"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.amber[600],
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 45),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _stripHtmlTags(String html) {
    // This is a simple regex to remove HTML tags.
    // For more complex HTML, a dedicated package might be better,
    // but this is often sufficient.
    final RegExp exp = RegExp(r"<[^>]*>", multiLine: true, caseSensitive: true);
    return html.replaceAll(exp, '');
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
    return MouseRegion(
      cursor: SystemMouseCursors.resizeLeftRight,
      child: Container(
        width: 8,
        color: Colors.grey[300],
      ),
    );
  }
}