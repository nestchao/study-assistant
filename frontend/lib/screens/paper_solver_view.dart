// lib/screens/paper_solver_view.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:study_assistance/provider/project_provider.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:study_assistance/models/past_paper.dart';
import 'package:markdown/markdown.dart' as md;

class PaperSolverView extends StatefulWidget {
  const PaperSolverView({super.key});

  @override
  State<PaperSolverView> createState() => _PaperSolverViewState();
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

  String markdownToHtml(String markdown) {
    return md.markdownToHtml(markdown, extensionSet: md.ExtensionSet.gitHubWeb);
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

  // Widget _buildNoteViewer(String html) {
  //   return Scrollbar(
  //     controller: _notesScrollController,
  //     thumbVisibility: true,
  //     child: SingleChildScrollView(
  //       controller: _notesScrollController,
  //       padding: const EdgeInsets.all(16),
  //       child: Card(
  //         child: Padding(
  //           padding: const EdgeInsets.all(16),
  //           // --- THIS IS THE CLEANED-UP IMPLEMENTATION ---
  //           child: Html(
  //             data: html,
  //             extensions: [
  //               TagExtension(
  //                 tagsToExtend: {"firestore-image"},
  //                 builder: (ExtensionContext context) {
  //                   final String mediaId = context.attributes['src'] ?? '';
  //                   // Just return the new reusable widget. No complex logic here.
  //                   return FirestoreImage(mediaId: mediaId);
  //                 },
  //               ),
  //             ],
  //           ),
  //           // --- END OF FIX ---
  //         ),
  //       ),
  //     ),
  //   );
  // }

  // Widget _buildNoteEditor() {
  //   return Padding(
  //     padding: const EdgeInsets.all(16.0),
  //     child: TextField(
  //       controller: _noteEditController,
  //       maxLines: null, // Allows the text field to expand vertically
  //       expands: true, // Fills the available space
  //       keyboardType: TextInputType.multiline,
  //       decoration: const InputDecoration(
  //         hintText: "Edit your notes here...",
  //         border: OutlineInputBorder(),
  //         isDense: true,
  //       ),
  //       textAlignVertical: TextAlignVertical.top,
  //     ),
  //   );
  // }

  // Widget _emptySources() => Center(
  //       child: Column(mainAxisSize: MainAxisSize.min, children: [
  //         Icon(Icons.upload_file, size: 64, color: Colors.grey[400]),
  //         Text("No PDFs yet", style: TextStyle(color: Colors.grey[600])),
  //         Text("Tap below to upload",
  //             style: TextStyle(color: Colors.grey[500])),
  //       ]),
  //     );

  // Widget _uploadFooter(ProjectProvider p, List<Source> s) => Container(
  //       padding: const EdgeInsets.all(12),
  //       color: Colors.grey[50],
  //       child: Column(children: [
  //         ElevatedButton.icon(
  //           onPressed: p.isUploading ? null : p.pickAndUploadFiles,
  //           icon: p.isUploading
  //               ? const SizedBox(
  //                   width: 20,
  //                   height: 20,
  //                   child: CircularProgressIndicator(color: Colors.white))
  //               : const Icon(Icons.upload_file),
  //           label: Text(p.isUploading ? "Uploading..." : "Upload PDFs"),
  //           style: ElevatedButton.styleFrom(
  //               backgroundColor: Colors.blue[600],
  //               minimumSize: const Size(double.infinity, 50)),
  //         ),
  //         if (s.isNotEmpty)
  //           Text("${s.length} source${s.length > 1 ? 's' : ''}",
  //               style: const TextStyle(fontSize: 12, color: Colors.grey)),
  //       ]),
  //     );

  // Widget _noteActions(BuildContext ctx, ProjectProvider p, String html) =>
  //     Container(
  //       padding: const EdgeInsets.all(12),
  //       child: Column(children: [
  //         ElevatedButton.icon(
  //             onPressed:
  //                 p.selectedSource == null ? null : p.getNoteForSelectedSource,
  //             icon: const Icon(Icons.refresh),
  //             label: const Text("Reload")),
  //         const SizedBox(height: 8),
  //         OutlinedButton.icon(
  //             onPressed: () => _copyRichTextToClipboard(ctx, html),
  //             icon: const Icon(Icons.copy),
  //             label: const Text("Copy Note")),
  //         const Divider(height: 24),
  //         TextField(
  //             controller: p.topicController,
  //             maxLines: 2,
  //             decoration: const InputDecoration(hintText: "e.g. Explain OOP")),
  //         ElevatedButton.icon(
  //             onPressed: () {
  //               final t = p.topicController.text.trim();
  //               if (t.isNotEmpty) p.generateTopicNote(t);
  //             },
  //             icon: const Icon(Icons.auto_awesome),
  //             label: const Text("Generate")),
  //       ]),
  //     );

  //   Future<void> _copyRichTextToClipboard(BuildContext context, String html) async {
  //   final item = DataWriterItem();
  //   item.add(Formats.htmlText(html));
    
  //   // Helper to create a plain text fallback
  //   String stripHtmlTags(String html) {
  //     final RegExp exp = RegExp(r"<[^>]*>", multiLine: true, caseSensitive: true);
  //     return html.replaceAll(exp, '').replaceAll('&nbsp;', ' ');
  //   }

  //   final plainText = stripHtmlTags(html).trim();
  //   item.add(Formats.plainText(plainText));
    
  //   await SystemClipboard.instance?.write([item]);
    
  //   if (mounted) {
  //     ScaffoldMessenger.of(context).showSnackBar(
  //       const SnackBar(
  //         content: Text("Formatted note copied!"),
  //         backgroundColor: Colors.green,
  //       ),
  //     );
  //   }
  // }
}