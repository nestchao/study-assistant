// frontend/lib/screens/dashboard_screen.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:study_assistance/provider/project_provider.dart';
import 'package:study_assistance/screens/workspace_screen.dart';
import 'package:study_assistance/models/project.dart'; // Import the Project model

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  @override
  void initState() {
    super.initState();
    // Use addPostFrameCallback to ensure the context is available
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // We only fetch projects once, so we check if they are already loaded
      // This prevents re-fetching when navigating back to the dashboard
      Provider.of<ProjectProvider>(context, listen: false).fetchProjects();
    });
  }
  
  // No didChangeDependencies is needed anymore since we handle it in initState

  void _showCreateProjectDialog() {
    final TextEditingController nameController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Create New Project'),
          content: TextField(
            controller: nameController,
            autofocus: true, // Automatically focus the text field
            decoration: InputDecoration(
              hintText: "e.g., Biology Midterm",
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () {
                if (nameController.text.trim().isNotEmpty) {
                  Provider.of<ProjectProvider>(context, listen: false)
                      .createProject(nameController.text.trim());
                  Navigator.of(context).pop();
                }
              },
              child: const Text('Create'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // Define our color scheme
    final Color primaryColor = Colors.indigo[800]!;
    final Color backgroundColor = Colors.grey[100]!;

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        title: const Text(
          'Study Assistant',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        backgroundColor: primaryColor,
        elevation: 4.0,
      ),
      body: Container(
        // Add a subtle gradient background
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [backgroundColor, Colors.grey[200]!],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Consumer<ProjectProvider>(
          builder: (context, provider, child) {
            if (provider.isLoadingProjects) {
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

  // Header Widget
  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Welcome!',
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.bold,
              color: Colors.grey[800],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Select a project to continue or create a new one.',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  // Empty State Widget
  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.school_outlined,
            size: 100,
            color: Colors.grey[400],
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
            'Click the "New Project" button to get started.',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey[500],
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  void _showDeleteConfirmDialog(Project project) {
    showDialog(
      context: context,
      barrierDismissible: false, // Prevent closing the dialog while deleting
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
              onPressed: () async { // Make the onPressed callback async
                try {
                  // Await the deletion process
                  await Provider.of<ProjectProvider>(context, listen: false)
                      .deleteProject(project.id);

                  // Check if the widget is still mounted before interacting with context
                  if (!mounted) return;

                  Navigator.of(dialogContext).pop(); // Close the dialog on success
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('"${project.name}" was deleted.')),
                  );
                } catch (e) {
                  // Handle potential errors during deletion
                  if (!mounted) return;
                  Navigator.of(dialogContext).pop(); // Close the dialog on error
                   ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Failed to delete project. Please try again.')),
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

  // UPDATED: This list now shows a progress indicator on the card being deleted.
  Widget _buildProjectList(List<Project> projects) {
  return Consumer<ProjectProvider>(
    builder: (context, provider, child) {
      return SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0),
        sliver: SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              final project = projects[index];
              final bool isDeleting = provider.deletingProjectId == project.id;

              return Card(
                margin: const EdgeInsets.symmetric(vertical: 8.0),
                elevation: 3.0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12.0),
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
                    padding: const EdgeInsets.fromLTRB(16.0, 16.0, 8.0, 16.0),
                    child: Row(
                      children: [
                        Icon(
                          Icons.topic_outlined,
                          color: Colors.indigo[600],
                          size: 32,
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Text(
                            project.name,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        // NEW & IMPROVED: Use a SizedBox to define a fixed area for the action icons/spinner.
                        SizedBox(
                          width: 80, // A fixed width to prevent layout shifts.
                          height: 48, // Standard height for touch targets.
                          child: Center(
                            child: isDeleting
                                ? // The progress indicator is now larger.
                                const SizedBox(
                                    width: 28, // Increase size here
                                    height: 28, // Increase size here
                                    child: CircularProgressIndicator(
                                      strokeWidth: 3.0,
                                      color: Colors.indigo,
                                    ),
                                  )
                                : // The original icons.
                                Row(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      IconButton(
                                        icon: Icon(
                                          Icons.delete_outline,
                                          color: Colors.grey[600],
                                        ),
                                        onPressed: () {
                                          _showDeleteConfirmDialog(project);
                                        },
                                      ),
                                      const Padding(
                                        padding: EdgeInsets.only(right: 8.0),
                                        child: Icon(
                                          Icons.arrow_forward_ios,
                                          color: Color.fromARGB(255, 189, 189, 189),
                                          size: 18,
                                        ),
                                      ),
                                    ],
                                  ),
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