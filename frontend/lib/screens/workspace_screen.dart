// lib/screens/workspace_screen.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:study_assistance/provider/project_provider.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:study_assistance/models/past_paper.dart';
import 'package:study_assistance/screens/workspace_panels.dart'; // Make sure this import is correct

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
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ADDED BACK THIS MISSING HELPER FUNCTION
  String markdownToHtml(String text) {
      text = text.replaceAllMapped(RegExp(r'\*\*(.*?)\*\*'), (match) => '<b>${match.group(1)}</b>');
      text = text.replaceAllMapped(RegExp(r'\*(.*?)\*'), (match) => '<i>${match.group(1)}</i>');
      text = text.replaceAll('\n', '<br>');
      return text;
  }
}