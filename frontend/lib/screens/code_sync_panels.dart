// --- FILE: frontend/lib/screens/code_sync_panels.dart ---
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:study_assistance/provider/project_provider.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:study_assistance/widgets/tracking_mind_map.dart';
import 'package:study_assistance/widgets/dependency_cassette.dart';

// --- SHARED HEADER COMPONENT (To match WorkspacePanels) ---
class CodePanelHeader extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color iconColor;
  final List<Widget>? actions;

  const CodePanelHeader({
    super.key, 
    required this.title, 
    required this.icon, 
    required this.iconColor,
    this.actions
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE0E0E0), width: 0.5)),
      ),
      child: Row(
        children: [
          Icon(icon, color: iconColor, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF444746)),
            ),
          ),
          if (actions != null) ...actions!,
        ],
      ),
    );
  }
}

// ========================================
// 1. FILE TREE PANEL
// ========================================
class FileTreePanel extends StatelessWidget {
  const FileTreePanel({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF9FAFB), // Very light grey background
      child: Column(
        children: [
          CodePanelHeader(
            title: "Explorer", 
            icon: Icons.folder_open_rounded, 
            iconColor: Colors.blueAccent,
            actions: [
              IconButton(
                icon: const Icon(Icons.account_tree_rounded, color: Colors.black54, size: 20),
                tooltip: "Context Map",
                onPressed: () => _showMindMapDialog(context),
              )
            ],
          ),
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
                        Icon(Icons.folder_off, size: 48, color: Colors.grey.shade300),
                        const SizedBox(height: 12),
                        Text('No structure loaded', style: TextStyle(color: Colors.grey.shade500)),
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

// (Keep _showMindMapDialog logic here, omitted for brevity but should be included)
void _showMindMapDialog(BuildContext context) {
    final provider = Provider.of<ProjectProvider>(context, listen: false);
    final rootNode = provider.getFileTreeAsMindMap();
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          width: 800, height: 600,
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                const Text("Context Map", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
              ]),
              Expanded(child: TrackingMindMap(rootNode: rootNode, onTrackingChanged: provider.updateTrackedNodes)),
            ],
          ),
        ),
      ),
    );
}

class FileTreeWidget extends StatelessWidget {
  final Map<String, dynamic> tree;
  const FileTreeWidget({super.key, required this.tree});

  List<Widget> _buildTree(Map<String, dynamic> subTree, BuildContext context, int depth) {
    final provider = context.read<ProjectProvider>();
    final List<Widget> widgets = [];
    final sortedKeys = subTree.keys.toList()..sort();

    for (var key in sortedKeys) {
      final value = subTree[key];
      if (value is Map) {
        widgets.add(
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              leading: Icon(Icons.folder, color: Colors.amber.shade400, size: 20),
              title: Text(key, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13, color: Colors.black87)),
              tilePadding: EdgeInsets.only(left: 16.0 + (depth * 10), right: 12),
              childrenPadding: EdgeInsets.zero,
              dense: true,
              minTileHeight: 40,
              children: _buildTree(value as Map<String, dynamic>, context, depth + 1),
            ),
          ),
        );
      } else if (value is String) {
        widgets.add(
          InkWell(
            onTap: () {
              provider.clearCodeSuggestionHistory();
              provider.fetchFileContent(value);
            },
            child: Container(
              height: 36,
              padding: EdgeInsets.only(left: 16.0 + (depth * 10) + 24, right: 16),
              alignment: Alignment.centerLeft,
              child: Row(
                children: [
                  Icon(Icons.description_outlined, color: Colors.blueGrey.shade300, size: 16),
                  const SizedBox(width: 8),
                  Expanded(child: Text(key, style: const TextStyle(fontSize: 13, color: Colors.black87), overflow: TextOverflow.ellipsis)),
                ],
              ),
            ),
          ),
        );
      }
    }
    return widgets;
  }

  @override
  Widget build(BuildContext context) {
    return ListView(children: _buildTree(tree, context, 0));
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

  void _sendMessage() {
    final provider = context.read<ProjectProvider>();
    if (_chatController.text.trim().isNotEmpty) {
      provider.getRetrievalCandidates(_chatController.text.trim());
      _chatController.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ProjectProvider>();

    return Container(
      color: Colors.white,
      child: Column(
        children: [
          const CodePanelHeader(title: "Code Intelligence", icon: Icons.auto_awesome, iconColor: Colors.deepPurpleAccent),
          
          if (provider.isGeneratingSuggestion)
            const LinearProgressIndicator(minHeight: 2, backgroundColor: Colors.transparent),

          if (provider.isCassetteVisible && provider.activeCassetteGraph != null)
            DependencyCassette(graph: provider.activeCassetteGraph!, onClose: () => provider.hideCassette()),

          Expanded(
            child: provider.isReviewingContext 
              ? _buildContextChecklist(provider) 
              : _buildChatList(provider),
          ),
          
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
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: Colors.purple.shade50, shape: BoxShape.circle),
              child: Icon(Icons.psychology, size: 40, color: Colors.purple.shade300),
            ),
            const SizedBox(height: 16),
            const Text("Ask about your codebase", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black54)),
          ],
        ),
      );
    }
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(20),
      itemCount: provider.codeSuggestionHistory.length,
      itemBuilder: (context, index) => _buildChatMessage(provider.codeSuggestionHistory[index], context),
    );
  }

  Widget _buildChatMessage(CodeSuggestionMessage message, BuildContext context) {
    final isUser = message.isUser;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 24),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.7),
        decoration: BoxDecoration(
          color: isUser ? const Color(0xFFF3F4F6) : Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isUser ? 16 : 4),
            bottomRight: Radius.circular(isUser ? 4 : 16),
          ),
          border: isUser ? null : Border.all(color: Colors.grey.shade200),
          boxShadow: isUser ? [] : [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!isUser) 
              const Padding(
                padding: EdgeInsets.only(bottom: 8.0),
                child: Row(children: [
                  Icon(Icons.auto_awesome, size: 14, color: Colors.deepPurple),
                  SizedBox(width: 6),
                  Text("AI Assistant", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.deepPurple))
                ]),
              ),
            isUser 
              ? Text(message.content, style: const TextStyle(color: Colors.black87, fontSize: 14))
              : MarkdownBody(
                  data: message.content, 
                  selectable: true,
                  styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
                    p: const TextStyle(fontSize: 14, height: 1.5, color: Colors.black87),
                    code: const TextStyle(backgroundColor: Color(0xFFF5F7FA), fontFamily: 'monospace', fontSize: 13),
                    codeblockDecoration: BoxDecoration(color: const Color(0xFFF5F7FA), borderRadius: BorderRadius.circular(8)),
                  ),
                ),
          ],
        ),
      ),
    );
  }

  Widget _buildContextChecklist(ProjectProvider provider) {
    // Reusing the logic but styling it cleanly
    final rootNode = provider.getCandidatesAsMindMap();
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          color: Colors.amber.shade50,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("Context Review", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.amber)),
              const SizedBox(height: 4),
              Text("AI found relevant files. Deselect irrelevant ones to improve accuracy.", style: TextStyle(fontSize: 12, color: Colors.amber.shade900)),
            ],
          ),
        ),
        Expanded(
          child: TrackingMindMap(
            rootNode: rootNode,
            initialSelectedIds: provider.contextCandidates.where((c) => c.isSelected).map((c) => c.id).toSet(),
            onTrackingChanged: (ids) {
               for (var c in provider.contextCandidates) {
                 if (ids.contains(c.id) != c.isSelected) provider.toggleCandidate(c.id);
               }
            },
          ),
        ),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: Colors.grey.shade200))),
          child: Row(
            children: [
              TextButton(onPressed: () { /* Logic to cancel */ }, child: const Text("Cancel")),
              const SizedBox(width: 16),
              Expanded(
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.check),
                  label: const Text("Generate Answer"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.black,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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

  Widget _buildChatInput() {
    return Container(
      padding: const EdgeInsets.all(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: const Color(0xFFF3F4F6),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: Colors.transparent),
        ),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _chatController,
                decoration: const InputDecoration(
                  hintText: "Ask about functionality, bugs, or logic...",
                  border: InputBorder.none,
                  hintStyle: TextStyle(fontSize: 14, color: Colors.grey),
                ),
                onSubmitted: (_) => _sendMessage(),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.arrow_upward_rounded, color: Colors.black),
              onPressed: _sendMessage,
            ),
          ],
        ),
      ),
    );
  }
}

// ========================================
// 3. FILE VIEWER PANEL
// ========================================
class FileViewerPanel extends StatelessWidget {
  const FileViewerPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ProjectProvider>();
    return Container(
      color: const Color(0xFF1E1E1E), // Dark editor theme
      child: Column(
        children: [
          // Custom dark header
          Container(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
            color: const Color(0xFF252526),
            child: Row(
              children: [
                const Icon(Icons.code, color: Colors.blue, size: 18),
                const SizedBox(width: 12),
                Text(
                  provider.hasMoreContent ? "Code Viewer (Partial Load)" : "Code Viewer",
                  style: const TextStyle(color: Colors.white70, fontSize: 13, fontFamily: 'monospace'),
                ),
                const Spacer(),
                if (provider.selectedFileContent != null)
                  IconButton(
                    icon: const Icon(Icons.copy, size: 16, color: Colors.white54),
                    onPressed: () => Clipboard.setData(ClipboardData(text: provider.selectedFileContent!)),
                    tooltip: "Copy All",
                  )
              ],
            ),
          ),
          Expanded(
            child: provider.isLoadingFileContent 
              ? const Center(child: CircularProgressIndicator(color: Colors.white24)) 
              : provider.displayFileContent == null 
                ? Center(child: Text("Select a file to view", style: TextStyle(color: Colors.white24)))
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: SelectableText(
                      provider.displayFileContent!,
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 13, color: Color(0xFFD4D4D4), height: 1.5),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}