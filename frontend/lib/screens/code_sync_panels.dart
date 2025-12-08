// lib/screens/code_sync_panels.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:study_assistance/provider/project_provider.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:study_assistance/widgets/tracking_mind_map.dart';

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
                IconButton(
                  icon: const Icon(Icons.account_tree_rounded),
                  tooltip: "View Tracking Map",
                  color: Colors.blue.shade700,
                  onPressed: () {
                    _showMindMapDialog(context);
                  },
                )
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

void _showMindMapDialog(BuildContext context) {
    final provider = Provider.of<ProjectProvider>(context, listen: false);
    
    // Generate the node structure from current provider data
    final rootNode = provider.getFileTreeAsMindMap();

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(20),
        child: Container(
          width: double.infinity,
          height: double.infinity,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              // Dialog Header
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text("AI Context Tracking Map", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                    IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
                  ],
                ),
              ),
              const Divider(height: 1),
              
              // The Mind Map Widget
              Expanded(
                child: TrackingMindMap(
                  rootNode: rootNode,
                  onTrackingChanged: (trackedIds) {
                    provider.updateTrackedNodes(trackedIds);
                  },
                ),
              ),
              
              // Footer info
              Container(
                padding: const EdgeInsets.all(12),
                color: Colors.grey[50],
                child: const Row(
                  children: [
                    Icon(Icons.info_outline, size: 16, color: Colors.grey),
                    SizedBox(width: 8),
                    Text("Solid nodes are tracked by AI. Click (+) to expand/track a path.", style: TextStyle(color: Colors.grey)),
                  ],
                ),
              )
            ],
          ),
        ),
      ),
    );
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

    FocusScope.of(context).unfocus();
    
    _chatController.clear();

    provider.getRetrievalCandidates(prompt);
  }

  void _copyMessageToClipboard(String content) {
    Clipboard.setData(ClipboardData(text: content));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Row(
          children: [
            Icon(Icons.check_circle, color: Colors.white, size: 20),
            SizedBox(width: 8),
            Text('Response copied to clipboard!'),
          ],
        ),
        backgroundColor: Colors.purple.shade700,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),
      ),
    );
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

          // Content Area (Switch between Chat and Checklist)
          Expanded(
            child: provider.isReviewingContext 
              ? _buildContextChecklist(provider) 
              : _buildChatList(provider), // This method is now defined below
          ),
          
          // Chat Input (Only show if not reviewing context)
          if (!provider.isReviewingContext)
            _buildChatInput(),
        ],
      ),
    );
  }

  Widget _buildChatList(ProjectProvider provider) {
    if (provider.codeSuggestionHistory.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.chat_bubble_outline, size: 60, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            Text(
              'Ask AI about your code',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 16),
            ),
            const SizedBox(height: 8),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                'Type a question to find relevant files and generate answers.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(16),
      itemCount: provider.codeSuggestionHistory.length,
      itemBuilder: (context, index) {
        final message = provider.codeSuggestionHistory[index];
        return _buildChatMessage(message, context);
      },
    );
  }

  Widget _buildContextChecklist(ProjectProvider provider) {
    // 1. Convert candidates to Tree Structure suitable for MindMap
    // Ensure getCandidatesAsMindMap() exists in ProjectProvider
    final rootNode = provider.getCandidatesAsMindMap(); 

    // 2. Get the IDs of currently selected items for the visualizer to initialize correctly
    final Set<String> selectedIds = provider.contextCandidates
        .where((c) => c.isSelected)
        .map((c) => c.id)
        .toSet();

    return Column(
      children: [
        // Header
        Container(
          padding: const EdgeInsets.all(12),
          color: Colors.amber.shade50,
          child: Row(
            children: [
              const Icon(Icons.lightbulb_outline, color: Colors.amber),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  "Found ${provider.contextCandidates.length} relevant items. Click nodes to toggle selection.",
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ),
            ],
          ),
        ),
        
        // --- MIND MAP VISUALIZATION ---
        Expanded(
          child: Container(
            color: const Color(0xFFF8FAFC),
            child: TrackingMindMap(
              rootNode: rootNode,
              // Pass the currently selected IDs so the map shows correct initial state
              initialSelectedIds: selectedIds, 
              // Callback when user clicks nodes in the map
              onTrackingChanged: (activeIds) {
                // Loop through all provider candidates
                for (var candidate in provider.contextCandidates) {
                  // If the MindMap reports this ID as active, select it.
                  if (activeIds.contains(candidate.id)) {
                    if (!candidate.isSelected) {
                      provider.toggleCandidate(candidate.id); // This updates provider state
                    }
                  } else {
                    // If not in activeIds, deselect it
                    if (candidate.isSelected) {
                      provider.toggleCandidate(candidate.id); // This updates provider state
                    }
                  }
                }
              },
            ),
          ),
        ),
        // ------------------------------

        // Footer Actions (Generate / Cancel)
        Container(
          padding: const EdgeInsets.all(16.0),
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 4,
                offset: const Offset(0, -2),
              )
            ],
          ),
          child: Row(
            children: [
              TextButton(
                onPressed: () {
                  // Cancel logic: Just refresh the candidates list or toggle the viewing flag
                  // For now, assume provider handles state reset or just reload empty
                  // Ideally: provider.cancelContextReview();
                },
                child: const Text("Cancel"),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.auto_awesome),
                  label: Text("Generate Answer (${provider.contextCandidates.where((c) => c.isSelected).length})"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.purple,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  onPressed: () => provider.confirmContextAndGenerate(),
                ),
              ),
            ],
          ),
        )
      ],
    );
  }

  Widget _buildChatMessage(CodeSuggestionMessage message, BuildContext context) {
    return Align(
      alignment: message.isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.85, 
        ),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: message.isUser ? Colors.purple.shade600 : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            message.isUser
                ? Text(message.content, style: const TextStyle(color: Colors.white))
                : MarkdownBody(data: message.content, selectable: true),
            if (!message.isUser) ...[
              const SizedBox(height: 8),
              Divider(color: Colors.grey.shade300, height: 1),
              InkWell(
                onTap: () => _copyMessageToClipboard(message.content),
                child: const Padding(
                  padding: EdgeInsets.all(4.0),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.copy, size: 12), SizedBox(width: 4), Text("Copy", style: TextStyle(fontSize: 12))
                  ]),
                ),
              ),
            ],
          ],
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
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _chatController,
              decoration: InputDecoration(
                hintText: 'Ask about the code...',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)),
              ),
              onSubmitted: (_) => _sendMessage(),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            onPressed: _sendMessage,
            icon: const Icon(Icons.send),
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
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    // Add listener to detect scrolling
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    // If we are within 500 pixels of the bottom
    if (_scrollController.position.pixels >= 
        _scrollController.position.maxScrollExtent - 500) {
      
      final provider = context.read<ProjectProvider>();
      
      // If there is more text to show, load it
      if (provider.hasMoreContent) {
        provider.loadMoreFileContent();
      }
    }
  }

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
                Expanded(
                  child: Text(
                    provider.hasMoreContent 
                        ? 'Code Viewer (Scroll to load more...)' 
                        : 'Code Viewer',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
                if (provider.selectedFileContent != null)
                  IconButton.filled(
                    onPressed: () => _copyToClipboard(context, provider.selectedFileContent!),
                    icon: const Icon(Icons.copy, size: 18),
                    tooltip: 'Copy full file content',
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
                : provider.displayFileContent == null
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
                        controller: _scrollController, // Attach controller here
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SelectableText(
                              provider.displayFileContent!,
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                color: Color(0xFFD4D4D4),
                                fontSize: 13,
                                height: 1.5,
                              ),
                            ),
                            // Optional: Show a tiny loader at the bottom if more is available
                            if (provider.hasMoreContent)
                              const Padding(
                                padding: EdgeInsets.all(20.0),
                                child: Center(
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2, 
                                    color: Colors.grey
                                  )
                                ),
                              ),
                          ],
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
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white),
            const SizedBox(width: 8),
            Text('Full content (${(content.length / 1024).toStringAsFixed(1)} KB) copied!'),
          ],
        ),
        backgroundColor: Colors.green.shade700,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }
}