// lib/screens/workspace_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:study_assistance/provider/project_provider.dart';
import 'package:study_assistance/screens/desktop_study_layout.dart';
import 'package:study_assistance/screens/mobile_study_layout.dart';
import 'package:study_assistance/screens/paper_solver_view.dart';
import 'package:study_assistance/models/project.dart';

// --- 1. TOP-LEVEL WORKSPACE SCREEN (Manages the two main tabs) ---
class WorkspaceScreen extends StatefulWidget {
  final Project project;

  const WorkspaceScreen({
    super.key,
    required this.project, // Make the project a required parameter
  });

  @override
  State<WorkspaceScreen> createState() => _WorkspaceScreenState();
}

class _WorkspaceScreenState extends State<WorkspaceScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<ProjectProvider>(context, listen: false).setCurrentProject(widget.project);
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ProjectProvider>();
    final project = provider.currentProject;

    if (project == null) {
      return const Scaffold(body: Center(child: Text("No project selected.")));
    }

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


// --- 2. STUDY HUB GATEKEEPER (Decides mobile vs. desktop) ---
class StudyHubView extends StatelessWidget {
  const StudyHubView({super.key});
  static const double mobileBreakpoint = 900.0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < mobileBreakpoint) {
          return const MobileStudyLayout();
        } else {
          return const DesktopStudyLayout();
        }
      },
    );
  }
}