// frontend/lib/screens/dashboard_screen.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart'; // Add this package for date formatting
import 'package:provider/provider.dart';
import 'package:study_assistance/provider/project_provider.dart';
import 'package:study_assistance/screens/workspace_screen.dart';
import 'package:study_assistance/models/project.dart';
import 'package:flutter/services.dart';
import 'package:study_assistance/screens/code_sync_screen.dart';
import 'package:study_assistance/screens/local_converter_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = Provider.of<ProjectProvider>(context, listen: false);
      provider.fetchProjects(forceRefresh: true);
    });
  }

  void _showCreateProjectDialog() {
    final provider = Provider.of<ProjectProvider>(context, listen: false);
    provider.projectNameController.clear();

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Create New Project'),
          content: TextField(
            controller: provider.projectNameController,
            autofocus: true,
            decoration: InputDecoration(
              hintText: "e.g., Biology Midterm",
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onSubmitted: (value) => _createProject(context, value),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () =>
                  _createProject(context, provider.projectNameController.text),
              child: const Text('Create'),
            ),
          ],
        );
      },
    );
  }

  // --- NEW: Rename Project Dialog ---
  void _showRenameProjectDialog(Project project) {
    final provider = Provider.of<ProjectProvider>(context, listen: false);
    provider.projectNameController.text = project.name; // Pre-fill with current name

    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Rename Project'),
          content: TextField(
            controller: provider.projectNameController,
            autofocus: true,
            decoration: InputDecoration(
              hintText: "Enter a new name",
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onSubmitted: (value) => _renameProject(dialogContext, project.id, value),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () => _renameProject(
                dialogContext,
                project.id,
                provider.projectNameController.text,
              ),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  // --- NEW: Rename Project Logic ---
  void _renameProject(BuildContext dialogContext, String projectId, String newName) {
    if (newName.trim().isNotEmpty) {
      Provider.of<ProjectProvider>(context, listen: false)
          .renameProject(projectId, newName.trim());
      Navigator.of(dialogContext).pop();
    }
  }

  void _createProject(BuildContext context, String name) {
    final provider = Provider.of<ProjectProvider>(context, listen: false);
    if (name.trim().isNotEmpty) {
      provider.createProject(name.trim());
      Navigator.of(context).pop(); // Close the create dialog
    }
  }

  @override
  Widget build(BuildContext context) {
    final Color primaryColor = Colors.indigo[800]!;
    final Color backgroundColor = Colors.grey[50]!;

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        title: const Text(
          'My Projects',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        backgroundColor: primaryColor,
        elevation: 1.0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: () {
              Provider.of<ProjectProvider>(context, listen: false)
                  .fetchProjects(forceRefresh: true);
            },
            tooltip: 'Refresh Projects',
          ),
          IconButton(
              icon: const Icon(Icons.sync_alt),
              onPressed: () {
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CodeSyncScreen()));
              },
              tooltip: 'Code Sync Service',
            ),
          IconButton(
            icon: const Icon(Icons.transform_rounded),
            onPressed: () {
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LocalConverterScreen()));
            },
            tooltip: 'Local Code Converter',
          ),
        ],
      ),
      body: Consumer<ProjectProvider>(
        builder: (context, provider, child) {
          if (provider.isLoadingProjects && provider.projects.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }

          return RefreshIndicator(
            onRefresh: () => provider.fetchProjects(forceRefresh: true),
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(
                  child: _buildHeader(),
                ),
                provider.projects.isEmpty
                    ? SliverFillRemaining(
                        hasScrollBody: false,
                        child: _buildEmptyState(),
                      )
                    // --- MODIFIED: Use the new grid layout ---
                    : _buildProjectGrid(provider.projects),
              ],
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showCreateProjectDialog,
        icon: const Icon(Icons.add),
        label: const Text('New Project'),
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Welcome Back!',
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.bold,
              color: Colors.grey[850],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Select a project to continue your study session.',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.school_outlined, size: 120, color: Colors.indigo[100]),
          const SizedBox(height: 24),
          Text(
            'Your study space awaits!',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Colors.grey[800],
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40.0),
            child: Text(
              'Create your first project to start organizing your notes and materials.',
              style: TextStyle(fontSize: 16, color: Colors.grey[600]),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  void _showDeleteConfirmDialog(Project project) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Delete Project?'),
          content: Text(
              'Are you sure you want to delete "${project.name}"? This action cannot be undone.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () async {
                try {
                  await Provider.of<ProjectProvider>(context, listen: false)
                      .deleteProject(project.id);
                  if (!mounted) return;
                  Navigator.of(dialogContext).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                        content: Text('"${project.name}" was deleted.'),
                        backgroundColor: Colors.green),
                  );
                } catch (e) {
                  if (!mounted) return;
                  Navigator.of(dialogContext).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content:
                            Text('Failed to delete project. Please try again.'),
                        backgroundColor: Colors.red),
                  );
                }
              },
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
  }

  // --- NEW: Replaces _buildProjectList with a responsive grid ---
  Widget _buildProjectGrid(List<Project> projects) {
    return SliverPadding(
      padding: const EdgeInsets.all(16.0),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 280.0, // Each card can be up to 280px wide
          mainAxisSpacing: 16.0,
          crossAxisSpacing: 16.0,
          childAspectRatio: 1.0, // Makes the cards roughly square
        ),
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final project = projects[index];
            return _ProjectCard(
              project: project,
              onTap: (project) {
                final provider = context.read<ProjectProvider>();
                HapticFeedback.lightImpact();
                provider.setCurrentProject(project);
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => WorkspaceScreen(project: project),
                ));
              },
              onRename: _showRenameProjectDialog,
              onDelete: _showDeleteConfirmDialog,
            );
          },
          childCount: projects.length,
        ),
      ),
    );
  }
}

// --- NEW: A dedicated widget for the project card UI ---
class _ProjectCard extends StatelessWidget {
  final Project project;
  final Function(Project) onTap;
  final Function(Project) onRename;
  final Function(Project) onDelete;

  const _ProjectCard({
    required this.project,
    required this.onTap,
    required this.onRename,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ProjectProvider>();
    final isDeleting = provider.deletingProjectId == project.id;
    final isRenaming = provider.renamingProjectId == project.id;
    final isLoading = isDeleting || isRenaming;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16.0),
        side: BorderSide(color: Colors.grey[200]!),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16.0),
        onTap: isLoading ? null : () => onTap(project),
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Top row: Icon and Menu Button
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.indigo.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(Icons.topic_outlined, color: Colors.indigo[600]),
                      ),
                      const Spacer(),
                      PopupMenuButton<String>(
                        tooltip: 'Project Options',
                        icon: Icon(Icons.more_vert, color: Colors.grey[600]),
                        onSelected: (value) {
                          if (value == 'rename') onRename(project);
                          if (value == 'delete') onDelete(project);
                        },
                        itemBuilder: (BuildContext context) => [
                          const PopupMenuItem(value: 'rename', child: Text('Rename')),
                          const PopupMenuItem(value: 'delete', child: Text('Delete')),
                        ],
                      ),
                    ],
                  ),
                  const Spacer(),
                  // Bottom section: Title and Date
                  Text(
                    project.name,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  if (project.createdAt != null)
                    Text(
                      'Created: ${DateFormat.yMMMd().format(project.createdAt!)}',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                ],
              ),
            ),
            // Loading Overlay
            if (isLoading)
              Container(
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.7),
                  borderRadius: BorderRadius.circular(16.0),
                ),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 8),
                      Text(isRenaming ? "Renaming..." : "Deleting..."),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}