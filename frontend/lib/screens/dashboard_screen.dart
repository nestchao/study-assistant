// frontend/lib/screens/dashboard_screen.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart'; // Add this package for date formatting
import 'package:provider/provider.dart';
import 'package:study_assistance/provider/project_provider.dart';
import 'package:study_assistance/screens/workspace_screen.dart';
import 'package:study_assistance/models/project.dart';

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
      Provider.of<ProjectProvider>(context, listen: false)
          .fetchProjects(forceRefresh: true); // Refresh on each visit
    });
  }

  void _showCreateProjectDialog() {
    // Using the provider's controller is better for state management
    final provider = Provider.of<ProjectProvider>(context, listen: false);
    provider.projectNameController.clear(); // Clear previous input

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

  void _createProject(BuildContext context, String name) {
    if (name.trim().isNotEmpty) {
      Provider.of<ProjectProvider>(context, listen: false)
          .createProject(name.trim());
      Navigator.of(context).pop();
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
          // Add a refresh button for manual updates
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: () {
              Provider.of<ProjectProvider>(context, listen: false)
                  .fetchProjects(forceRefresh: true);
            },
            tooltip: 'Refresh Projects',
          ),
        ],
      ),
      body: Consumer<ProjectProvider>(
        builder: (context, provider, child) {
          // Show loading spinner only if the cache was empty initially
          if (provider.isLoadingProjects && provider.projects.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }

          return CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: _buildHeader(),
              ),
              provider.projects.isEmpty
                  ? SliverFillRemaining(child: _buildEmptyState())
                  : _buildProjectList(provider.projects),
            ],
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
      child: SingleChildScrollView( // Prevents overflow on small screens
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.school_outlined,
                size: 100,
                color: Colors.grey[300],
              ),
              const SizedBox(height: 20),
              Text(
                'No Projects Yet',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[700],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Click the "New Project" button below to get started on your learning journey.',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey[500],
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
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

  // --- REBUILT PROJECT LIST WIDGET ---
  Widget _buildProjectList(List<Project> projects) {
    return Consumer<ProjectProvider>(
      builder: (context, provider, child) {
        return SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final project = projects[index];
                final bool isDeleting = provider.deletingProjectId == project.id;

                return Card(
                  margin: const EdgeInsets.symmetric(vertical: 8.0),
                  elevation: 2.0,
                  shadowColor: Colors.indigo.withOpacity(0.1),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12.0),
                    side: BorderSide(color: Colors.grey[200]!),
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12.0),
                    onTap: isDeleting
                        ? null
                        : () {
                            provider.setCurrentProject(project);
                            Navigator.of(context).push(MaterialPageRoute(
                              builder: (_) => WorkspaceScreen(),
                            ));
                          },
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Row(
                        children: [
                          // Leading Icon
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.indigo[50],
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              Icons.topic_outlined,
                              color: Colors.indigo[600],
                              size: 28,
                            ),
                          ),
                          const SizedBox(width: 16),
                          // Title and Date
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  project.name,
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (project.createdAt != null) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    'Created: ${DateFormat.yMMMd().format(project.createdAt!)}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                ]
                              ],
                            ),
                          ),
                          // Action Button / Spinner
                          SizedBox(
                            width: 48,
                            height: 48,
                            child: isDeleting
                                ? const Center(
                                    child: SizedBox(
                                      width: 24,
                                      height: 24,
                                      child: CircularProgressIndicator(strokeWidth: 2.5),
                                    ),
                                  )
                                : IconButton(
                                    icon: Icon(
                                      Icons.delete_outline,
                                      color: Colors.grey[500],
                                    ),
                                    tooltip: 'Delete Project',
                                    onPressed: () {
                                      _showDeleteConfirmDialog(project);
                                    },
                                  ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
              childCount: projects.length,
            ),
          ),
        );
      },
    );
  }
}