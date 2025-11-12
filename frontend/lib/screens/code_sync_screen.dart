// lib/screens/code_sync_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:study_assistance/provider/project_provider.dart';
import 'package:study_assistance/models/sync_config.dart';
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
      Provider.of<ProjectProvider>(context, listen: false).fetchSyncConfigs();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _projectNameController.dispose();
    _pathController.dispose();
    _extensionsController.dispose();
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
                            child: Icon(Icons.folder_open, color: Theme.of(context).primaryColor),
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Text(
                              'Register New Project',
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
                        'Create a new project and sync a folder',
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 24),
                      
                      // NEW: Project Name Field
                      TextField(
                        controller: _projectNameController,
                        decoration: InputDecoration(
                          labelText: 'Project Name',
                          hintText: 'My Awesome Project',
                          prefixIcon: const Icon(Icons.folder_special),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          filled: true,
                          helperText: 'This will be the name of your new project',
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
                          prefixIcon: const Icon(Icons.code),
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
                              final extensions = _extensionsController.text
                                  .split(',')
                                  .map((e) => e.trim())
                                  .where((e) => e.isNotEmpty)
                                  .toList();
                              final ignoredPaths = _ignoreController.text
                                  .split('\n')
                                  .map((e) => e.trim())
                                  .where((e) => e.isNotEmpty)
                                  .toList();

                              // Validation
                              if (projectName.isEmpty) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Please enter a project name'),
                                    behavior: SnackBarBehavior.floating,
                                  ),
                                );
                                return;
                              }

                              if (path.isEmpty) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Please enter a folder path'),
                                    behavior: SnackBarBehavior.floating,
                                  ),
                                );
                                return;
                              }

                              try {
                                // Show loading indicator
                                showDialog(
                                  context: dialogContext,
                                  barrierDismissible: false,
                                  builder: (ctx) => const Center(
                                    child: Card(
                                      child: Padding(
                                        padding: EdgeInsets.all(24.0),
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            CircularProgressIndicator(),
                                            SizedBox(height: 16),
                                            Text('Creating project and registering folder...'),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                );

                                // Call the new combined method
                                await provider.createProjectAndRegisterSync(
                                  projectName,
                                  path,
                                  extensions,
                                  ignoredPaths,
                                );

                                // Close loading dialog
                                Navigator.pop(dialogContext);
                                // Close register dialog
                                Navigator.pop(dialogContext);

                                // Show success message
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('✅ Project "$projectName" created and synced!'),
                                    behavior: SnackBarBehavior.floating,
                                    backgroundColor: Colors.green,
                                  ),
                                );
                              } catch (e) {
                                // Close loading dialog if it's open
                                Navigator.pop(dialogContext);
                                
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('❌ Error: ${e.toString()}'),
                                    behavior: SnackBarBehavior.floating,
                                    backgroundColor: Colors.red,
                                  ),
                                );
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

  Widget _buildConfigurationsTab() {
    return Consumer<ProjectProvider>(
      builder: (context, provider, child) {
        if (provider.isLoadingConfigs) {
          return const Center(child: CircularProgressIndicator());
        }
        if (provider.syncConfigs.isEmpty) {
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
          onRefresh: provider.fetchSyncConfigs,
          child: ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: provider.syncConfigs.length,
            itemBuilder: (context, index) {
              final config = provider.syncConfigs[index];
              return SyncConfigTile(
                config: config,
                onViewFiles: () {
                  provider.fetchFileTree(config.projectId);
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

class SyncConfigTile extends StatelessWidget {
  final SyncConfig config;
  final VoidCallback onViewFiles;
  
  const SyncConfigTile({
    super.key,
    required this.config,
    required this.onViewFiles,
  });

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ProjectProvider>();
    final isSyncing = provider.syncingConfigId == config.id;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: config.isActive ? Colors.green.shade50 : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.folder,
                    color: config.isActive ? Colors.green.shade700 : Colors.grey.shade600,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        config.localPath.split('/').last.split('\\').last,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        config.localPath,
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 12,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: config.isActive,
                  onChanged: (value) => provider.updateSyncConfigStatus(config.id, value),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: config.allowedExtensions.map((ext) {
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

            if (config.lastSynced != null) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(Icons.access_time, size: 14, color: Colors.grey.shade600),
                  const SizedBox(width: 4),
                  Text(
                    'Last synced: ${config.lastSynced}',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: isSyncing ? null : () {
                      provider.runSync(config.id);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Sync started...'),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    },
                    icon: isSyncing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.sync, size: 18),
                    label: Text(isSyncing ? 'Syncing...' : 'Sync'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onViewFiles,
                    icon: const Icon(Icons.visibility, size: 18),
                    label: const Text('View'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 8),

                IconButton(
                  onPressed: () => _showEditIgnoreDialog(context, provider, config),
                  icon: const Icon(Icons.playlist_remove_outlined),
                  tooltip: 'Edit Ignored Paths',
                ),

                IconButton.filled(
                  icon: const Icon(Icons.delete_outline, size: 20),
                  onPressed: () => _showDeleteConfirmation(context, provider, config.id),
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.red.shade50,
                    foregroundColor: Colors.red.shade700,
                  ),
                ),
              ],
            ),
            if (config.ignoredPaths.isNotEmpty) ...[
              const SizedBox(height: 8),
              const Text('Ignoring:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
              Padding(
                padding: const EdgeInsets.only(left: 8.0, top: 4.0),
                child: Text(
                  config.ignoredPaths.join(', '),
                  style: const TextStyle(fontSize: 12, fontFamily: 'monospace', color: Colors.grey),
                ),
              ),
            ],
            const Divider(),
          ],
        ),
      ),
    );
  }

  void _showDeleteConfirmation(BuildContext context, ProjectProvider provider, String configId) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Sync Configuration?'),
        content: const Text('This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              provider.deleteSyncConfig(configId);
              Navigator.pop(ctx);
            },
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _showEditIgnoreDialog(BuildContext context, ProjectProvider provider, SyncConfig config) {
    final ignoreController = TextEditingController(
      text: config.ignoredPaths.join('\n'), // Pre-fill with existing paths
    );

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Edit Ignored Paths'),
        content: TextField(
          controller: ignoreController,
          decoration: const InputDecoration(
            hintText: 'Enter paths to ignore, one per line...',
            border: OutlineInputBorder(),
          ),
          maxLines: 5,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              final newIgnoredPaths = ignoreController.text
                  .split('\n')
                  .map((e) => e.trim())
                  .where((e) => e.isNotEmpty)
                  .toList();
              
              try {
                await provider.updateIgnoredPaths(config.id, newIgnoredPaths);
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