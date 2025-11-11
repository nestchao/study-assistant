// lib/screens/code_sync_panels.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:study_assistance/provider/project_provider.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

// ========================================
// 1. FILE TREE PANEL
// ========================================
class FileTreePanel extends StatelessWidget {
  const FileTreePanel({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.grey.shade50,
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              border: Border(bottom: BorderSide(color: Colors.blue.shade200)),
            ),
            child: Row(
              children: [
                Icon(Icons.folder_outlined, color: Colors.blue.shade700),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'File Structure',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
          // Content
          Expanded(
            child: Consumer<ProjectProvider>(
              builder: (context, provider, child) {
                if (provider.isLoadingFileTree) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (provider.fileTree == null) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.folder_open, size: 60, color: Colors.grey.shade400),
                        const SizedBox(height: 12),
                        Text(
                          'No files loaded',
                          style: TextStyle(color: Colors.grey.shade600),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Sync a configuration first',
                          style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
                        ),
                      ],
                    ),
                  );
                }
                return FileTreeWidget(tree: provider.fileTree!);
              },
            ),
          ),
        ],
      ),
    );
  }
}

class FileTreeWidget extends StatelessWidget {
  final Map<String, dynamic> tree;
  const FileTreeWidget({super.key, required this.tree});

  List<Widget> _buildTree(
    Map<String, dynamic> subTree,
    BuildContext context,
    int depth,
  ) {
    final provider = context.read<ProjectProvider>();
    final List<Widget> widgets = [];
    final sortedKeys = subTree.keys.toList()..sort();

    for (var key in sortedKeys) {
      final value = subTree[key];
      if (value is Map) {
        // Folder
        widgets.add(
          ExpansionTile(
            leading: Icon(Icons.folder, color: Colors.amber.shade700, size: 20),
            title: Text(
              key,
              style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
            ),
            tilePadding: EdgeInsets.only(left: 16.0 + (depth * 12), right: 16),
            childrenPadding: EdgeInsets.zero,
            children: _buildTree(value as Map<String, dynamic>, context, depth + 1),
          ),
        );
      } else if (value is String) {
        // File
        widgets.add(
          ListTile(
            leading: Icon(Icons.insert_drive_file, color: Colors.blue.shade600, size: 18),
            title: Text(key, style: const TextStyle(fontSize: 13)),
            contentPadding: EdgeInsets.only(left: 28.0 + (depth * 12), right: 16),
            dense: true,
            onTap: () {
              // --- THIS IS THE FIX ---
              // 1. Clear the chat history for the previous file.
              provider.clearCodeSuggestionHistory();
              
              // 2. Fetch the content for the NEW file.
              provider.fetchFileContent(value);
              // --- END OF FIX ---
            },
          ),
        );
      }
    }
    return widgets;
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: _buildTree(tree, context, 0),
    );
  }
}

// ========================================
// 2. AI CHAT PANEL
// ========================================
class CodeChatPanel extends StatefulWidget {
  const CodeChatPanel({super.key});

  @override
  State<CodeChatPanel> createState() => _CodeChatPanelState();
}

class _CodeChatPanelState extends State<CodeChatPanel> {
  final _chatController = TextEditingController();
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _chatController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _sendMessage() {
    final provider = context.read<ProjectProvider>();
    final prompt = _chatController.text.trim();
    if (prompt.isEmpty) return;

    _chatController.clear();
    FocusScope.of(context).unfocus();
    provider.generateCodeSuggestion(prompt);

    // Auto-scroll to bottom
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ProjectProvider>();

    return Container(
      color: Colors.white,
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.purple.shade50,
              border: Border(bottom: BorderSide(color: Colors.purple.shade200)),
            ),
            child: Row(
              children: [
                Icon(Icons.smart_toy, color: Colors.purple.shade700),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'AI Code Assistant',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
                if (provider.codeSuggestionHistory.isNotEmpty)
                  TextButton.icon(
                    onPressed: () => provider.clearCodeSuggestionHistory(),
                    icon: const Icon(Icons.clear_all, size: 18),
                    label: const Text('Clear', style: TextStyle(fontSize: 12)),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    ),
                  ),
              ],
            ),
          ),
          // Chat Messages
          Expanded(
            child: provider.codeSuggestionHistory.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.chat_bubble_outline, size: 60, color: Colors.grey.shade400),
                        const SizedBox(height: 12),
                        Text(
                          'Ask AI about your code',
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 32),
                          child: Text(
                            'Select a file and start chatting to get explanations, suggestions, or improvements',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.grey.shade500,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16),
                    itemCount: provider.codeSuggestionHistory.length,
                    itemBuilder: (context, index) {
                      final message = provider.codeSuggestionHistory[index];
                      return _buildChatMessage(message, context);
                    },
                  ),
          ),
          // Loading indicator
          if (provider.isGeneratingSuggestion)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.purple.shade400,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'AI is thinking...',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                  ),
                ],
              ),
            ),
          // Chat Input
          _buildChatInput(),
        ],
      ),
    );
  }

  Widget _buildChatMessage(CodeSuggestionMessage message, BuildContext context) {
    return Align(
      alignment: message.isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: message.isUser ? Colors.purple.shade600 : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: message.isUser
            ? Text(
                message.content,
                style: const TextStyle(color: Colors.white, fontSize: 14),
              )
            : MarkdownBody(
                data: message.content,
                selectable: true,
                styleSheet: MarkdownStyleSheet(
                  p: const TextStyle(fontSize: 14, height: 1.5),
                  code: TextStyle(
                    backgroundColor: Colors.grey.shade200,
                    fontFamily: 'monospace',
                    fontSize: 13,
                  ),
                  codeblockDecoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
      ),
    );
  }

  Widget _buildChatInput() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _chatController,
              decoration: InputDecoration(
                hintText: 'Ask about the code...',
                hintStyle: TextStyle(fontSize: 14, color: Colors.grey.shade500),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                filled: true,
                fillColor: Colors.grey.shade50,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                isDense: true,
              ),
              onSubmitted: (_) => _sendMessage(),
              maxLines: null,
              textInputAction: TextInputAction.send,
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            onPressed: _sendMessage,
            icon: const Icon(Icons.send, size: 20),
            style: IconButton.styleFrom(
              backgroundColor: Colors.purple.shade600,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

// ========================================
// 3. FILE VIEWER PANEL
// ========================================
class FileViewerPanel extends StatefulWidget {
  const FileViewerPanel({super.key});

  @override
  State<FileViewerPanel> createState() => _FileViewerPanelState();
}

class _FileViewerPanelState extends State<FileViewerPanel> {

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ProjectProvider>();

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        border: Border.all(color: Colors.grey.shade800),
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.green.shade50,
              border: Border(bottom: BorderSide(color: Colors.green.shade200)),
            ),
            child: Row(
              children: [
                Icon(Icons.code, color: Colors.green.shade700, size: 20),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Code Viewer',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
                if (provider.selectedFileContent != null)
                  IconButton.filled(
                    onPressed: () => _copyToClipboard(context, provider.selectedFileContent!),
                    icon: const Icon(Icons.copy, size: 18),
                    tooltip: 'Copy all code',
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.green.shade100,
                      foregroundColor: Colors.green.shade700,
                      padding: const EdgeInsets.all(8),
                    ),
                  ),
              ],
            ),
          ),
          // Content
          Expanded(
            child: provider.isLoadingFileContent
                ? const Center(
                    child: CircularProgressIndicator(color: Colors.white70),
                  )
                : provider.selectedFileContent == null
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.code_off, size: 60, color: Colors.grey.shade600),
                            const SizedBox(height: 12),
                            Text(
                              'No file selected',
                              style: TextStyle(color: Colors.grey.shade400, fontSize: 16),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Click a file from the tree to view',
                              style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
                            ),
                          ],
                        ),
                      )
                    : SingleChildScrollView(
                        padding: const EdgeInsets.all(16),
                        child: SelectableText(
                          provider.selectedFileContent!,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            color: Color(0xFFD4D4D4),
                            fontSize: 13,
                            height: 1.5,
                          ),
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  void _copyToClipboard(BuildContext context, String content) {
    Clipboard.setData(ClipboardData(text: content));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Row(
          children: [
            Icon(Icons.check_circle, color: Colors.white),
            SizedBox(width: 8),
            Text('Code copied to clipboard!'),
          ],
        ),
        backgroundColor: Colors.green.shade700,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }
}