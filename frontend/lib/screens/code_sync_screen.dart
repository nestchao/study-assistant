// lib/screens/code_sync_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:study_assistance/provider/project_provider.dart';
import 'package:study_assistance/models/sync_config.dart';
import 'package:study_assistance/models/project.dart';

class CodeSyncScreen extends StatefulWidget {
  const CodeSyncScreen({super.key});

  @override
  State<CodeSyncScreen> createState() => _CodeSyncScreenState();
}

class _CodeSyncScreenState extends State<CodeSyncScreen> {
  final _pathController = TextEditingController();
  final _extensionsController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<ProjectProvider>(context, listen: false).fetchSyncConfigs();
    });
  }

  @override
  void dispose() {
    _pathController.dispose();
    _extensionsController.dispose();
    super.dispose();
  }
  
  void _showRegisterDialog() {
    final provider = Provider.of<ProjectProvider>(context, listen: false);
    _pathController.clear();
    _extensionsController.clear();

    Project? selectedProject = provider.projects.isNotEmpty ? provider.projects.first : null;

    showDialog(
      context: context,
      builder: (dialogContext) {
        // Use a StatefulWidget to manage the dropdown's state
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Register Folder to Sync'),
              content: SingleChildScrollView( // Use a scroll view for smaller screens
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // --- NEW: PROJECT SELECTOR DROPDOWN ---
                    if (provider.projects.isEmpty)
                      const Text("Please create a project first.", style: TextStyle(color: Colors.red))
                    else
                      DropdownButtonFormField<Project>(
                        initialValue: selectedProject,
                        decoration: const InputDecoration(labelText: 'Associate with Project'),
                        items: provider.projects.map((Project project) {
                          return DropdownMenuItem<Project>(
                            value: project,
                            child: Text(project.name),
                          );
                        }).toList(),
                        onChanged: (Project? newValue) {
                          setDialogState(() {
                            selectedProject = newValue;
                          });
                        },
                      ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _pathController,
                      decoration: const InputDecoration(labelText: 'Absolute Folder Path', hintText: 'C:/...'),
                    ),
                    TextField(
                      controller: _extensionsController,
                      decoration: const InputDecoration(labelText: 'File Extensions (comma-separated)', hintText: 'py, dart, kt'),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
                ElevatedButton(
                  // Disable button if no project is selected
                  onPressed: selectedProject == null ? null : () async {
                    final path = _pathController.text.trim();
                    final extensions = _extensionsController.text.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
                    
                    // Use the projectId from the dropdown, not the global provider state
                    final projectId = selectedProject!.id;

                    if (path.isNotEmpty) {
                      try {
                        await provider.registerSyncConfig(projectId, path, extensions);
                        Navigator.pop(dialogContext);
                      } catch (e) {
                        // ... error handling
                      }
                    }
                  },
                  child: const Text('Register'),
                ),
              ],
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
        title: const Text('Code Sync Service'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            onPressed: _showRegisterDialog,
            tooltip: 'Register New Folder',
          ),
        ],
      ),
      endDrawer: const FileViewerDrawer(), // The file viewer panel
      body: Consumer<ProjectProvider>(
        builder: (context, provider, child) {
          if (provider.isLoadingConfigs) {
            return const Center(child: CircularProgressIndicator());
          }
          if (provider.syncConfigs.isEmpty) {
            return const Center(child: Text('No folders registered. Click "+" to add one.'));
          }

          return RefreshIndicator(
            onRefresh: provider.fetchSyncConfigs,
            child: ListView.builder(
              itemCount: provider.syncConfigs.length,
              itemBuilder: (context, index) {
                final config = provider.syncConfigs[index];
                return SyncConfigTile(config: config);
              },
            ),
          );
        },
      ),
    );
  }
}

class SyncConfigTile extends StatelessWidget {
  final SyncConfig config;
  const SyncConfigTile({super.key, required this.config});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ProjectProvider>();
    final isSyncing = provider.syncingConfigId == config.id;

    return Card(
      margin: const EdgeInsets.all(8.0),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(config.localPath, style: const TextStyle(fontWeight: FontWeight.bold)),
            Text('File types: ${config.allowedExtensions.join(', ')}'),
            Text('Status: ${config.status}'),
            if (config.lastSynced != null) Text('Last Synced: ${config.lastSynced}'),
            const Divider(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Text('Active:'),
                    Switch(
                      value: config.isActive,
                      onChanged: (value) => provider.updateSyncConfigStatus(config.id, value),
                    ),
                  ],
                ),
                ElevatedButton.icon(
                  onPressed: isSyncing ? null : () {
                    provider.runSync(config.id);
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Sync started...')));
                  },
                  icon: isSyncing ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.sync),
                  label: Text(isSyncing ? 'Syncing...' : 'Sync Now'),
                ),
                ElevatedButton(
                  onPressed: () {
                    provider.fetchFileTree(config.projectId);
                    Scaffold.of(context).openEndDrawer();
                  },
                  child: const Text('View Files'),
                ),
                IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red),
                  onPressed: () => provider.deleteSyncConfig(config.id),
                )
              ],
            )
          ],
        ),
      ),
    );
  }
}


class FileViewerDrawer extends StatelessWidget {
  const FileViewerDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    return Drawer(
      width: MediaQuery.of(context).size.width * 0.75, // Take up 75% of screen width
      child: Consumer<ProjectProvider>(
        builder: (context, provider, child) {
          return Column(
            children: [
              AppBar(title: const Text('Converted Files'), automaticallyImplyLeading: false),
              Expanded(
                flex: 1, // File Tree takes 1/3 of the space
                child: provider.isLoadingFileTree
                    ? const Center(child: CircularProgressIndicator())
                    : provider.fileTree == null
                        ? const Center(child: Text('Select a project and click "View Files"'))
                        : FileTreeWidget(tree: provider.fileTree!),
              ),
              const Divider(),
              Expanded(
                flex: 2, // File Content takes 2/3 of the space
                child: provider.isLoadingFileContent
                    ? const Center(child: CircularProgressIndicator())
                    : FileContentWidget(content: provider.selectedFileContent ?? 'Select a file to view its content.'),
              )
            ],
          );
        },
      ),
    );
  }
}

class FileTreeWidget extends StatelessWidget {
  final Map<String, dynamic> tree;
  const FileTreeWidget({super.key, required this.tree});
  
  List<Widget> _buildTree(Map<String, dynamic> subTree, BuildContext context) {
    final provider = context.read<ProjectProvider>();
    final List<Widget> widgets = [];
    final sortedKeys = subTree.keys.toList()..sort();

    for (var key in sortedKeys) {
      final value = subTree[key];
      if (value is Map) {
        // This part is for folders
        widgets.add(
          ExpansionTile(
            leading: const Icon(Icons.folder_outlined, color: Colors.amber),
            title: Text(key),
            children: _buildTree(value as Map<String, dynamic>, context),
          ),
        );
      } else if (value is String) {
        widgets.add(
          ListTile(
            leading: const Icon(Icons.article),
            title: Text(key),
            onTap: () {
              provider.fetchFileContent(value);
            },
          ),
        );
      }
    }
    return widgets;
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: _buildTree(tree, context),
    );
  }
}

class FileContentWidget extends StatelessWidget {
  final String content;
  const FileContentWidget({super.key, required this.content});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: IconButton(
            icon: const Icon(Icons.copy),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: content));
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Content copied to clipboard')));
            },
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: SelectableText(content),
          ),
        ),
      ],
    );
  }
}

//testing hello