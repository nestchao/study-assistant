// lib/screens/code_sync_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:study_assistance/provider/project_provider.dart';
import 'package:study_assistance/models/code_project.dart';
import 'package:study_assistance/screens/code_sync_desktop_layout.dart';
import 'package:study_assistance/screens/code_sync_mobile_layout.dart';

class CodeSyncScreen extends StatefulWidget {
  const CodeSyncScreen({super.key});
  @override
  State<CodeSyncScreen> createState() => _CodeSyncScreenState();
}

class _CodeSyncScreenState extends State<CodeSyncScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  
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
    super.dispose();
  }

  void _showRegisterDialog() {
    showDialog(
      context: context,
      builder: (context) => const _RegisterProjectDialog(),
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
              maxCrossAxisExtent: 350.0,
              mainAxisSpacing: 16.0,
              crossAxisSpacing: 16.0,
              childAspectRatio: 0.85,
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

// --- EXTRACTED REGISTER DIALOG TO ISOLATE STATE ---
class _RegisterProjectDialog extends StatefulWidget {
  const _RegisterProjectDialog();

  @override
  State<_RegisterProjectDialog> createState() => _RegisterProjectDialogState();
}

class _RegisterProjectDialogState extends State<_RegisterProjectDialog> {
  final _projectNameController = TextEditingController();
  final _pathController = TextEditingController();
  final _extensionsController = TextEditingController(text: 'py, dart, kt, java, ts, js, md');
  final _pathsController = TextEditingController();

  // State to track which view is active
  String _activeView = 'ignore'; // 'ignore' or 'include'
  
  // Storage for both lists
  String _tempIgnored = 'build\\\n.dart_tool\\\nnode_modules\\\n.git\\';
  String _tempIncluded = ''; // Empty by default

  @override
  void initState() {
    super.initState();
    _pathsController.text = _tempIgnored;
  }

  @override
  void dispose() {
    _projectNameController.dispose();
    _pathController.dispose();
    _extensionsController.dispose();
    _pathsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<ProjectProvider>(context, listen: false);

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
              const Text('Register Code Project', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 24),
              TextField(controller: _projectNameController, decoration: const InputDecoration(labelText: 'Project Name')),
              const SizedBox(height: 16),
              TextField(controller: _pathController, decoration: const InputDecoration(labelText: 'Folder Path')),
              const SizedBox(height: 16),
              TextField(controller: _extensionsController, decoration: const InputDecoration(labelText: 'File Extensions (comma-separated)')),
              const SizedBox(height: 24),
              
              Text("Path Filters", style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'ignore', label: Text('Ignored Paths'), icon: Icon(Icons.visibility_off_outlined)),
                  ButtonSegment(value: 'include', label: Text('Exceptions (Include)'), icon: Icon(Icons.check_circle_outline)),
                ],
                selected: {_activeView},
                onSelectionChanged: (newSelection) {
                  setState(() {
                    // 1. Save text from current view to its buffer
                    if (_activeView == 'ignore') {
                      _tempIgnored = _pathsController.text;
                    } else {
                      _tempIncluded = _pathsController.text;
                    }

                    // 2. Switch View
                    _activeView = newSelection.first;

                    // 3. Load text for new view
                    _pathsController.text = _activeView == 'ignore' ? _tempIgnored : _tempIncluded;
                  });
                },
              ),
              const SizedBox(height: 8),
              
              // Helper Text
              Text(
                _activeView == 'ignore' 
                  ? "Files in these folders will be SKIPPED." 
                  : "Files in these folders will be UPLOADED, even if they are inside an Ignored folder.",
                style: TextStyle(fontSize: 12, color: _activeView == 'ignore' ? Colors.grey : Colors.green[700]),
              ),
              
              const SizedBox(height: 8),
              TextField(
                controller: _pathsController,
                decoration: InputDecoration(
                  labelText: _activeView == 'ignore' ? 'Paths to Ignore (one per line)' : 'Paths to Force Include (one per line)',
                  hintText: _activeView == 'ignore' ? 'build\\\nnode_modules\\' : 'backend\\src\\\nutils\\helpers.py',
                  border: const OutlineInputBorder(),
                ),
                maxLines: 4,
              ),

              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () async {
                      // 1. Capture final edits from the active text box
                      if (_activeView == 'ignore') {
                        _tempIgnored = _pathsController.text;
                      } else {
                        _tempIncluded = _pathsController.text;
                      }

                      final projectName = _projectNameController.text.trim();
                      final path = _pathController.text.trim();
                      final extensions = _extensionsController.text.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
                      
                      // 2. Prepare Lists
                      final ignoredPaths = _tempIgnored.split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
                      final includedPaths = _tempIncluded.split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();

                      if (projectName.isEmpty || path.isEmpty) return;

                      try {
                        // 3. Send BOTH lists to backend (Mode is always 'hybrid' implicitly)
                        await provider.createCodeProjectAndRegisterFolder(
                          projectName: projectName,
                          folderPath: path,
                          extensions: extensions,
                          ignoredPaths: ignoredPaths,
                          includedPaths: includedPaths,
                          syncMode: 'hybrid', // Just passing a dummy value, backend logic handles it
                        );
                        if (mounted) Navigator.pop(context);
                      } catch (e) {
                        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
                      }
                    },
                    child: const Text('Create & Register'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// --- PROJECT CARD (Stateless) ---
class _SyncProjectCard extends StatelessWidget {
  final CodeProject project;
  final VoidCallback onViewFiles;

  const _SyncProjectCard({
    required this.project,
    required this.onViewFiles,
  });

  void _showEditConfigDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => _EditConfigDialog(project: project),
    );
  }

  void _showDeleteConfirmation(BuildContext context, ProjectProvider provider) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Unregister Folder?'),
        content: Text('This will remove the sync configuration for "${project.name}".'),
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

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ProjectProvider>();
    final isSyncing = provider.syncingProjectId == project.id || project.status == 'syncing';

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: isSyncing ? Colors.blue.shade200 : Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
                    onChanged: isSyncing ? null : (value) => provider.updateSyncProjectStatus(project.id, value),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            if (project.allowedExtensions.isNotEmpty)
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: project.allowedExtensions.take(4).map((ext) {
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '.$ext',
                      style: TextStyle(color: Colors.blue.shade700, fontSize: 11, fontWeight: FontWeight.w500),
                    ),
                  );
                }).toList(),
              ),

            const Spacer(), 

            if (isSyncing) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2)),
                  const SizedBox(width: 8),
                  Text("Syncing files & indexing...", style: TextStyle(fontSize: 12, color: Colors.blue.shade700, fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 4),
              const LinearProgressIndicator(minHeight: 4),
            ] else ...[
              Row(
                children: [
                  Expanded(
                    child: FilledButton.tonalIcon(
                      onPressed: () {
                        provider.runSync(project.id);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Sync job started...'), behavior: SnackBarBehavior.floating),
                        );
                      },
                      icon: const Icon(Icons.sync, size: 18),
                      label: const Text('Sync Now'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
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
                      if (value == 'edit_config') _showEditConfigDialog(context);
                      if (value == 'unregister') _showDeleteConfirmation(context, provider);
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(value: 'edit_config', child: Text('Edit Configuration')),
                      const PopupMenuItem(value: 'unregister', child: Text('Unregister Folder')),
                    ],
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// --- EXTRACTED EDIT CONFIG DIALOG ---
class _EditConfigDialog extends StatefulWidget {
  final CodeProject project;

  const _EditConfigDialog({required this.project});

  @override
  State<_EditConfigDialog> createState() => _EditConfigDialogState();
}

class _EditConfigDialogState extends State<_EditConfigDialog> {
  late TextEditingController _extensionsController;
  late TextEditingController _pathsController;
  
  String _activeView = 'ignore';
  late String _tempIgnored;
  late String _tempIncluded;

  @override
  void initState() {
    super.initState();
    _extensionsController = TextEditingController(text: widget.project.allowedExtensions.join(', '));
    
    // Load existing data
    _tempIgnored = widget.project.ignoredPaths.join('\n');
    _tempIncluded = widget.project.includedPaths.join('\n');
    
    // Initial view shows Ignore paths
    _pathsController = TextEditingController(text: _tempIgnored);
  }

  @override
  void dispose() {
    _extensionsController.dispose();
    _pathsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<ProjectProvider>(context, listen: false);

    return AlertDialog(
      title: const Text('Edit Configuration'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _extensionsController, 
              decoration: const InputDecoration(labelText: 'File Extensions (comma-separated)')
            ),
            const SizedBox(height: 24),
            
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'ignore', label: Text('Ignored')),
                ButtonSegment(value: 'include', label: Text('Exceptions')),
              ],
              selected: {_activeView},
              onSelectionChanged: (newSelection) {
                setState(() {
                  // 1. Save
                  if (_activeView == 'ignore') {
                    _tempIgnored = _pathsController.text;
                  } else {
                    _tempIncluded = _pathsController.text;
                  }
                  
                  // 2. Switch
                  _activeView = newSelection.first;
                  
                  // 3. Load
                  _pathsController.text = _activeView == 'ignore' ? _tempIgnored : _tempIncluded;
                });
              },
            ),
            const SizedBox(height: 8),
             Text(
                _activeView == 'ignore' 
                  ? "Standard Ignore list." 
                  : "Forces upload for these subfolders/files.",
                style: TextStyle(fontSize: 12, color: _activeView == 'ignore' ? Colors.grey : Colors.green[700]),
              ),
            const SizedBox(height: 8),
            TextField(
              controller: _pathsController,
              decoration: InputDecoration(
                labelText: _activeView == 'ignore' ? 'Paths to Ignore' : 'Paths to Force Include', 
                border: const OutlineInputBorder()
              ),
              maxLines: 5,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: () async {
            // Capture final edits
            if (_activeView == 'ignore') {
              _tempIgnored = _pathsController.text;
            } else {
              _tempIncluded = _pathsController.text;
            }

            final newExt = _extensionsController.text.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
            final newIgnored = _tempIgnored.split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
            final newIncluded = _tempIncluded.split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();

            try {
              await provider.updateSyncConfig(
                widget.project.id,
                extensions: newExt,
                syncMode: 'hybrid', // Implicitly hybrid now
                ignoredPaths: newIgnored,
                includedPaths: newIncluded,
              );
              if (mounted) Navigator.pop(context);
            } catch (e) {
              if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
            }
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}