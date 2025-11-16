// lib/screens/code_sync_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:study_assistance/provider/project_provider.dart';
import 'package:study_assistance/models/code_project.dart'; // <-- Using the new model
import 'package:study_assistance/screens/code_sync_desktop_layout.dart';
import 'package:study_assistance/screens/code_sync_mobile_layout.dart';

class CodeSyncScreen extends StatefulWidget {
  const CodeSyncScreen({super.key});
  @override
  State<CodeSyncScreen> createState() => _CodeSyncScreenState();
}

class _CodeSyncScreenState extends State<CodeSyncScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _projectNameController = TextEditingController();
  final _pathController = TextEditingController();
  final _extensionsController = TextEditingController();
  final _ignoreController = TextEditingController();

  static const double mobileBreakpoint = 900.0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<ProjectProvider>(context, listen: false).fetchSyncProjects();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _projectNameController.dispose();
    _pathController.dispose();
    _extensionsController.dispose();
    _ignoreController.dispose();
    super.dispose();
  }

  void _showRegisterDialog() {
    final provider = Provider.of<ProjectProvider>(context, listen: false);
    _projectNameController.clear();
    _pathController.clear();
    _extensionsController.clear();
    _ignoreController.clear();

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Dialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Container(
                constraints: const BoxConstraints(maxWidth: 500),
                padding: const EdgeInsets.all(24),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Theme.of(context).primaryColor.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(Icons.code, color: Theme.of(context).primaryColor),
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Text(
                              'Register Code Project',
                              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () => Navigator.pop(dialogContext),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Create a new code project and register a folder for syncing',
                        style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
                      ),
                      const SizedBox(height: 24),
                      TextField(
                        controller: _projectNameController,
                        decoration: InputDecoration(
                          labelText: 'Code Project Name',
                          hintText: 'My Awesome App',
                          prefixIcon: const Icon(Icons.folder_special),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          filled: true,
                          helperText: 'This will be the name of your new code project',
                        ),
                        textCapitalization: TextCapitalization.words,
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _pathController,
                        decoration: InputDecoration(
                          labelText: 'Folder Path',
                          hintText: 'C:/Projects/MyApp',
                          prefixIcon: const Icon(Icons.create_new_folder),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          filled: true,
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _extensionsController,
                        decoration: InputDecoration(
                          labelText: 'File Extensions',
                          hintText: 'py, dart, kt, java',
                          prefixIcon: const Icon(Icons.extension),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          filled: true,
                          helperText: 'Comma-separated list of file types',
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _ignoreController,
                        decoration: InputDecoration(
                          labelText: 'Ignored Paths (one per line)',
                          hintText: 'build/\n.dart_tool/\nnode_modules/',
                          prefixIcon: const Icon(Icons.visibility_off),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          filled: true,
                        ),
                        maxLines: 3,
                      ),
                      const SizedBox(height: 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () => Navigator.pop(dialogContext),
                            child: const Text('Cancel'),
                          ),
                          const SizedBox(width: 8),
                          FilledButton.icon(
                            onPressed: () async {
                              final projectName = _projectNameController.text.trim();
                              final path = _pathController.text.trim();
                              final extensions = _extensionsController.text.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
                              final ignoredPaths = _ignoreController.text.split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();

                              if (projectName.isEmpty || path.isEmpty) {
                                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Project Name and Folder Path are required.')));
                                return;
                              }

                              try {
                                showDialog(context: dialogContext, barrierDismissible: false, builder: (ctx) => const Center(child: Card(child: Padding(padding: EdgeInsets.all(24.0), child: Column(mainAxisSize: MainAxisSize.min, children: [CircularProgressIndicator(), SizedBox(height: 16), Text('Creating project...')])))));
                                await provider.createCodeProjectAndRegisterFolder(
                                  projectName,
                                  path,
                                  extensions,
                                  ignoredPaths,
                                );
                                Navigator.pop(dialogContext); // Close loading
                                Navigator.pop(dialogContext); // Close register dialog
                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('✅ Code project "$projectName" created and registered!'), behavior: SnackBarBehavior.floating, backgroundColor: Colors.green));
                              } catch (e) {
                                Navigator.pop(dialogContext); // Close loading
                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('❌ Error: ${e.toString()}'), behavior: SnackBarBehavior.floating, backgroundColor: Colors.red));
                              }
                            },
                            icon: const Icon(Icons.add),
                            label: const Text('Create & Register'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Code Sync'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_rounded),
            onPressed: _showRegisterDialog,
            tooltip: 'Register Folder',
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.folder_outlined), text: 'Configurations'),
            Tab(icon: Icon(Icons.code), text: 'Code Viewer'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildConfigurationsTab(),
          _buildCodeViewerTab(),
        ],
      ),
    );
  }

  // --- MODIFIED: Use GridView.builder for a responsive grid layout ---
  Widget _buildConfigurationsTab() {
    return Consumer<ProjectProvider>(
      builder: (context, provider, child) {
        if (provider.isLoadingSyncProjects) {
          return const Center(child: CircularProgressIndicator());
        }
        if (provider.syncProjects.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.folder_off, size: 80, color: Colors.grey.shade400),
                const SizedBox(height: 16),
                Text(
                  'No folders registered',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        color: Colors.grey.shade600,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Click the + button to add your first folder',
                  style: TextStyle(color: Colors.grey.shade500),
                ),
              ],
            ),
          );
        }

        return RefreshIndicator(
          onRefresh: provider.fetchSyncProjects,
          child: GridView.builder(
            padding: const EdgeInsets.all(16),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 350.0, // Wider cards for more content
              mainAxisSpacing: 16.0,
              crossAxisSpacing: 16.0,
              childAspectRatio: 0.9, // Taller cards
            ),
            itemCount: provider.syncProjects.length,
            itemBuilder: (context, index) {
              final project = provider.syncProjects[index];
              return _SyncProjectCard(
                project: project,
                onViewFiles: () {
                  provider.fetchFileTree(project.id);
                  _tabController.animateTo(1);
                },
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildCodeViewerTab() {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < mobileBreakpoint) {
          return const CodeSyncMobileLayout();
        } else {
          return const CodeSyncDesktopLayout();
        }
      },
    );
  }
}

// --- NEW WIDGET: Replaces SyncProjectTile with a card-based design ---
class _SyncProjectCard extends StatelessWidget {
  final CodeProject project;
  final VoidCallback onViewFiles;

  const _SyncProjectCard({
    required this.project,
    required this.onViewFiles,
  });

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ProjectProvider>();
    final isSyncing = provider.syncingProjectId == project.id;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Row: Icon, Title, Switch
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: project.isActive ? Colors.green.shade50 : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.folder_copy_outlined,
                    color: project.isActive ? Colors.green.shade700 : Colors.grey.shade600,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        project.name,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        project.localPath ?? 'Folder not registered',
                        style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Transform.scale(
                  scale: 0.8,
                  child: Switch(
                    value: project.isActive,
                    onChanged: (value) => provider.updateSyncProjectStatus(project.id, value),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Extensions Chips
            if (project.allowedExtensions.isNotEmpty)
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: project.allowedExtensions.map((ext) {
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '.$ext',
                      style: TextStyle(
                        color: Colors.blue.shade700,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  );
                }).toList(),
              ),

            const Spacer(), // Pushes buttons to the bottom

            // Action Buttons
            Row(
              children: [
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: isSyncing ? null : () {
                      provider.runSync(project.id);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Sync started...'), behavior: SnackBarBehavior.floating),
                      );
                    },
                    icon: isSyncing
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.sync, size: 18),
                    label: Text(isSyncing ? 'Syncing...' : 'Sync'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: onViewFiles,
                    icon: const Icon(Icons.visibility_outlined, size: 18),
                    label: const Text('View'),
                  ),
                ),
                const SizedBox(width: 8),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert),
                  tooltip: 'More Options',
                  onSelected: (value) {
                    if (value == 'edit_ignore') _showEditIgnoreDialog(context, provider, project);
                    if (value == 'unregister') _showDeleteConfirmation(context, provider, project);
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(value: 'edit_ignore', child: Text('Edit Ignored Paths')),
                    const PopupMenuItem(value: 'unregister', child: Text('Unregister Folder')),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showDeleteConfirmation(BuildContext context, ProjectProvider provider, CodeProject project) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Unregister Folder?'),
        content: Text('This will remove the sync configuration for "${project.name}". The project and its synced files will remain.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              provider.deleteSyncFromProject(project.id);
              Navigator.pop(ctx);
            },
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Unregister'),
          ),
        ],
      ),
    );
  }

  void _showEditIgnoreDialog(BuildContext context, ProjectProvider provider, CodeProject project) {
    final ignoreController = TextEditingController(text: project.ignoredPaths.join('\n'));
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Edit Ignored Paths'),
        content: TextField(
          controller: ignoreController,
          decoration: const InputDecoration(hintText: 'Enter paths, one per line...', border: OutlineInputBorder()),
          maxLines: 5,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              final newPaths = ignoreController.text.split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
              try {
                await provider.updateIgnoredPaths(project.id, newPaths);
                Navigator.pop(dialogContext);
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}