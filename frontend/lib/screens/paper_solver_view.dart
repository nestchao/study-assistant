// --- FILE: frontend/lib/screens/paper_solver_view.dart ---
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:study_assistance/provider/project_provider.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:study_assistance/models/past_paper.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:super_clipboard/super_clipboard.dart'; // Import for Rich Text Copy

class PaperSolverView extends StatefulWidget {
  const PaperSolverView({super.key});

  @override
  State<PaperSolverView> createState() => _PaperSolverViewState();
}

class _PaperSolverViewState extends State<PaperSolverView> {
  PastPaper? _selectedPaper;

  /// Shows a dialog for the user to choose between analysis methods.
  void _showUploadOptionsDialog(BuildContext context) {
    final provider = Provider.of<ProjectProvider>(context, listen: false);

    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Choose Analysis Method'),
          content: const SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('How would you like to analyze this paper?'),
                SizedBox(height: 16),
                Text(
                  'Text Only (Fast & Reliable)',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(
                  'Best for text-heavy documents. Ignores images and complex layouts.',
                  style: TextStyle(fontSize: 13, color: Colors.black54),
                ),
                SizedBox(height: 12),
                Text(
                  'Full Analysis (Slower, Visual)',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(
                  'Sends the entire file to the AI. Best for papers with diagrams, charts, or complex formatting.',
                  style: TextStyle(fontSize: 13, color: Colors.black54),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                provider.pickAndProcessPaper('text_only');
              },
              child: const Text('Text Only'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.indigo,
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                Navigator.of(dialogContext).pop();
                provider.pickAndProcessPaper('multimodal');
              },
              child: const Text('Full Analysis'),
            ),
          ],
        );
      },
    );
  }

  void _showDeletePaperConfirmation(BuildContext context, ProjectProvider provider, PastPaper paper) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Past Paper?'),
        content: Text('Are you sure you want to delete "${paper.filename}"? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.of(ctx).pop(); // Close the dialog first
              try {
                await provider.deletePastPaper(paper.id);

                // If the deleted paper was the one being viewed, clear the view
                if (mounted && _selectedPaper?.id == paper.id) {
                  setState(() {
                    _selectedPaper = null;
                  });
                }
                
                if(mounted) {
                   ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('"${paper.filename}" deleted.'), backgroundColor: Colors.green),
                  );
                }
              } catch (e) {
                 if(mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Error: ${e.toString()}'), backgroundColor: Colors.red),
                    );
                 }
              }
            },
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  // --- COPY FUNCTIONALITY ---
  Future<void> _copyPaperToClipboard(PastPaper paper) async {
    final StringBuffer htmlBuffer = StringBuffer();
    final StringBuffer textBuffer = StringBuffer();

    // Header
    htmlBuffer.write("<h1>${paper.filename} - AI Solutions</h1><hr>");
    textBuffer.writeln("${paper.filename} - AI Solutions\n${"=" * 30}");

    // Iterate through QA pairs
    for (int i = 0; i < paper.qaPairs.length; i++) {
      final qa = paper.qaPairs[i];
      
      // HTML Format (Good for Google Docs)
      htmlBuffer.write("<h3>Q${i + 1}: ${qa.question}</h3>");
      htmlBuffer.write(markdownToHtml(qa.answer)); // Convert markdown answer to HTML
      htmlBuffer.write("<br><hr><br>");

      // Plain Text Format (Fallback)
      textBuffer.writeln("\nQ${i + 1}: ${qa.question}");
      textBuffer.writeln("A:\n${qa.answer}\n");
      textBuffer.writeln("-" * 30);
    }

    final item = DataWriterItem();
    item.add(Formats.htmlText(htmlBuffer.toString()));
    item.add(Formats.plainText(textBuffer.toString()));
    
    await SystemClipboard.instance?.write([item]);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Copied to clipboard! Ready to paste into Google Docs."),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _copySingleAnswer(String question, String answer) async {
    final StringBuffer htmlBuffer = StringBuffer();
    htmlBuffer.write("<h3>Q: $question</h3>");
    htmlBuffer.write(markdownToHtml(answer));

    final item = DataWriterItem();
    item.add(Formats.htmlText(htmlBuffer.toString()));
    item.add(Formats.plainText("Q: $question\n\nA:\n$answer"));
    
    await SystemClipboard.instance?.write([item]);
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Answer copied."), duration: Duration(seconds: 1)),
      );
    }
  }

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
                "This may take a moment as the AI reads the document and generates answers based on your notes.",
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
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error: ${p.paperError}'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 5),
            ),
          );
          p.clearPaperError();
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
        onPressed: () => _showUploadOptionsDialog(context),
        icon: const Icon(Icons.upload_file),
        label: const Text('Upload Paper'),
        backgroundColor: Colors.indigo,
      ),
    );
  }

  /// Converts a markdown string to an HTML string for rendering.
  String markdownToHtml(String markdown) {
    return md.markdownToHtml(markdown, extensionSet: md.ExtensionSet.gitHubWeb);
  }

  /// The view shown when no past papers have been uploaded yet.
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
            onPressed: () => _showUploadOptionsDialog(context),
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

  /// The main content area, which uses a LayoutBuilder to be responsive.
  Widget _buildMainContent(ProjectProvider p) {
    return LayoutBuilder(builder: (context, constraints) {
      if (constraints.maxWidth < 600) {
        return _buildMobilePaperView(p);
      } else {
        return _buildDesktopPaperView(p);
      }
    });
  }

  /// The two-panel layout for wider screens (desktop/tablet).
  Widget _buildDesktopPaperView(ProjectProvider p) {
    return Row(
      children: [
        SizedBox(
          width: 300,
          child: _buildPaperList(p, isMobile: false),
        ),
        const VerticalDivider(width: 1),
        Expanded(
          child: _selectedPaper == null
              ? const Center(child: Text("Select a paper to view the solution"))
              : _buildQAPanel(_selectedPaper!),
        ),
      ],
    );
  }

  /// The view for mobile screens, which navigates to a detail view.
  Widget _buildMobilePaperView(ProjectProvider p) {
    if (_selectedPaper != null) {
      return Scaffold(
        appBar: AppBar(
          title: Text(_selectedPaper!.filename, style: const TextStyle(fontSize: 16)),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => setState(() => _selectedPaper = null),
          ),
          // ADDED: Copy button in Mobile AppBar
          actions: [
            IconButton(
              icon: const Icon(Icons.copy),
              tooltip: "Copy All to Google Docs",
              onPressed: () => _copyPaperToClipboard(_selectedPaper!),
            )
          ],
        ),
        body: _buildQAPanel(_selectedPaper!),
      );
    }
    return _buildPaperList(p, isMobile: true);
  }

  /// The list of solved papers.
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
                final isDeleting = p.deletingPaperId == paper.id;

                return ListTile(
                  leading: const Icon(Icons.article_outlined),
                  title: Text(paper.filename, maxLines: 2, overflow: TextOverflow.ellipsis),
                  subtitle: Text(
                    'Mode: ${paper.analysisMode == 'multimodal' ? 'Full Analysis' : 'Text Only'}',
                    style: TextStyle(
                      fontSize: 12,
                      color: paper.analysisMode == 'multimodal' ? Colors.indigo : Colors.black54,
                    ),
                  ),
                  trailing: isDeleting
                      ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                      : IconButton(
                          icon: Icon(Icons.delete_outline, color: Colors.red[700]),
                          onPressed: () => _showDeletePaperConfirmation(context, p, paper),
                          tooltip: 'Delete Paper',
                        ),
                  tileColor: isSelected ? Colors.indigo.withOpacity(0.1) : null,
                  onTap: isDeleting ? null : () {
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

  /// A generic header for panels.
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

  /// The panel that displays the questions and answers for the selected paper.
  /// UPDATED: Added Header with "Copy All" button.
  Widget _buildQAPanel(PastPaper paper) {
    return Column(
      children: [
        // --- ADDED: Header with Copy Action ---
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          color: Colors.white,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "${paper.qaPairs.length} Solutions Found",
                style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.grey),
              ),
              ElevatedButton.icon(
                onPressed: () => _copyPaperToClipboard(paper),
                icon: const Icon(Icons.copy, size: 18),
                label: const Text("Copy All to Docs"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.indigo.shade50,
                  foregroundColor: Colors.indigo,
                  elevation: 0,
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        
        // --- QA List ---
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: paper.qaPairs.length,
            itemBuilder: (context, index) {
              final qa = paper.qaPairs[index];
              return Card(
                margin: const EdgeInsets.only(bottom: 16),
                elevation: 2,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: ExpansionTile(
                  leading: CircleAvatar(child: Text('${index + 1}')),
                  title: Text(qa.question, style: const TextStyle(fontWeight: FontWeight.w600)),
                  // Added trailing copy button for individual answer
                  trailing: IconButton(
                    icon: const Icon(Icons.copy, size: 18, color: Colors.grey),
                    tooltip: "Copy this answer",
                    onPressed: () => _copySingleAnswer(qa.question, qa.answer),
                  ),
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: SelectionArea(
                        child: Html(
                          data: markdownToHtml(qa.answer),
                          style: {
                            "body": Style(fontSize: FontSize(15)),
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}