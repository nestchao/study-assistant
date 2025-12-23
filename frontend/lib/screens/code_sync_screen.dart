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
  final TextEditingController _searchController = TextEditingController();
  
  static const double mobileBreakpoint = 900.0;
  String _searchQuery = '';
  bool _isGridView = true;

  // Pastel colors matching Dashboard
  final List<Color> _cardColors = [
    const Color(0xFFFDF6E3), // Cream
    const Color(0xFFE8F5E9), // Light Green
    const Color(0xFFE3F2FD), // Light Blue
    const Color(0xFFF3E5F5), // Light Purple
    const Color(0xFFFFF3E0), // Light Orange
  ];

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
    _searchController.dispose();
    super.dispose();
  }

  Color _getCardColor(int index) => _cardColors[index % _cardColors.length];

  void _showRegisterDialog() {
    showDialog(
      context: context,
      builder: (context) => const _RegisterProjectDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            _buildTopActions(),
            const Divider(height: 1, color: Color(0xFFE0E0E0)),
            
            // Tab Bar integrated into the flow
            Container(
              color: Colors.white,
              width: double.infinity,
              alignment: Alignment.centerLeft,
              child: TabBar(
                controller: _tabController,
                labelColor: Colors.indigo,
                unselectedLabelColor: Colors.grey,
                indicatorColor: Colors.indigo,
                indicatorSize: TabBarIndicatorSize.label,
                isScrollable: true,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                tabs: const [
                  Tab(text: 'Configurations'),
                  Tab(text: 'Workspace'),
                ],
              ),
            ),
            
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildConfigurationsTab(),
                  _buildCodeViewerTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopActions() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Row(
        children: [
          // 1. Logo/Title
          const Text('Code Intelligence',
              style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.5)),

          const SizedBox(width: 40),

          // 2. Search Bar
          Expanded(
            child: Container(
              height: 48,
              decoration: BoxDecoration(
                color: const Color(0xFFF0F4F9),
                borderRadius: BorderRadius.circular(24),
              ),
              child: TextField(
                controller: _searchController,
                onChanged: (v) => setState(() => _searchQuery = v),
                decoration: const InputDecoration(
                  hintText: 'Search repositories...',
                  prefixIcon: Icon(Icons.search, color: Colors.black54),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
          ),

          const SizedBox(width: 20),

          // 3. Navigation (Back to Home)
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: const Color(0xFFE0E0E0)),
              borderRadius: BorderRadius.circular(12),
            ),
            child: IconButton(
              tooltip: 'Back to Study Assistance',
              icon: const Icon(Icons.home_outlined, size: 20, color: Colors.black87),
              onPressed: () => Navigator.pop(context),
            ),
          ),

          const SizedBox(width: 12),

          // 4. View Toggle (Grid/List)
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFFF0F4F9),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                IconButton(
                  icon: Icon(Icons.grid_view_rounded,
                      size: 20,
                      color: _isGridView ? Colors.blue[800] : Colors.black54),
                  onPressed: () => setState(() => _isGridView = true),
                ),
                IconButton(
                  icon: Icon(Icons.list_rounded,
                      size: 20,
                      color: !_isGridView ? Colors.blue[800] : Colors.black54),
                  onPressed: () => setState(() => _isGridView = false),
                ),
              ],
            ),
          ),

          const SizedBox(width: 20),

          // 5. Create Button
          ElevatedButton.icon(
            onPressed: _showRegisterDialog,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('New Repo', style: TextStyle(fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.black,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            ),
          ),
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
        
        final filteredProjects = provider.syncProjects
            .where((p) => p.name.toLowerCase().contains(_searchQuery.toLowerCase()))
            .toList();

        if (filteredProjects.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.folder_off_outlined, size: 80, color: Colors.grey.shade200),
                const SizedBox(height: 16),
                Text(
                  _searchQuery.isEmpty ? 'No Synced Projects' : 'No matching projects found',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        color: Colors.grey.shade600,
                        fontWeight: FontWeight.bold
                      ),
                ),
                const SizedBox(height: 8),
                if (_searchQuery.isEmpty)
                  const Text('Register a folder to start.', style: TextStyle(color: Colors.grey)),
              ],
            ),
          );
        }

        return RefreshIndicator(
          onRefresh: provider.fetchSyncProjects,
          child: CustomScrollView(
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
                sliver: SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 20),
                    child: Text(
                      "Active Repositories (${filteredProjects.length})", 
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: Color(0xFF444746)),
                    ),
                  ),
                ),
              ),
              
              _isGridView
                  ? SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      sliver: SliverGrid(
                        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 350.0,
                          mainAxisSpacing: 20.0,
                          crossAxisSpacing: 20.0,
                          childAspectRatio: 1.1,
                        ),
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            final project = filteredProjects[index];
                            return _SyncProjectCard(
                              project: project,
                              color: _getCardColor(index),
                              isGrid: true,
                              onViewFiles: () {
                                provider.fetchFileTree(project.id);
                                _tabController.animateTo(1);
                              },
                            );
                          },
                          childCount: filteredProjects.length,
                        ),
                      ),
                    )
                  : SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            final project = filteredProjects[index];
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: _SyncProjectCard(
                                project: project,
                                color: _getCardColor(index),
                                isGrid: false,
                                onViewFiles: () {
                                  provider.fetchFileTree(project.id);
                                  _tabController.animateTo(1);
                                },
                              ),
                            );
                          },
                          childCount: filteredProjects.length,
                        ),
                      ),
                    ),
                    
              const SliverPadding(padding: EdgeInsets.only(bottom: 100), sliver: SliverToBoxAdapter(child: SizedBox())),
            ],
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

// --- PROJECT CARD ---
class _SyncProjectCard extends StatelessWidget {
  final CodeProject project;
  final VoidCallback onViewFiles;
  final Color color;
  final bool isGrid;

  const _SyncProjectCard({
    required this.project,
    required this.onViewFiles,
    required this.color,
    required this.isGrid,
  });

  void _showEditConfigDialog(BuildContext context) {
    showDialog(context: context, builder: (context) => _EditConfigDialog(project: project));
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ProjectProvider>();
    final isSyncing = provider.syncingProjectId == project.id || project.status == 'syncing';

    if (!isGrid) {
      // LIST VIEW LAYOUT
      return Container(
        height: 100,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4))],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: Colors.white.withOpacity(0.6), shape: BoxShape.circle),
              child: const Icon(Icons.code_rounded, color: Colors.black87, size: 20),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(project.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold), maxLines: 1),
                  const SizedBox(height: 4),
                  Text(project.localPath ?? 'Path unknown', style: TextStyle(fontSize: 12, color: Colors.black.withOpacity(0.6)), maxLines: 1),
                ],
              ),
            ),
            if (isSyncing)
              const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
            else
              Row(
                children: [
                  IconButton.filledTonal(
                    onPressed: onViewFiles,
                    icon: const Icon(Icons.open_in_new, size: 18),
                    tooltip: "Open Workspace",
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: () => provider.runSync(project.id),
                    icon: const Icon(Icons.sync),
                    tooltip: "Sync",
                  ),
                  const SizedBox(width: 8),
                  _buildMenu(context, provider),
                ],
              )
          ],
        ),
      );
    }

    // GRID VIEW LAYOUT
    return Container(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.transparent),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4))
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.6),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.code_rounded, color: Colors.black87, size: 20),
              ),
              const Spacer(),
              _buildMenu(context, provider),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            project.name,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87),
            maxLines: 1, overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Text(
            project.localPath ?? 'Path unknown',
            style: TextStyle(fontSize: 12, color: Colors.black.withOpacity(0.6)),
            maxLines: 1, overflow: TextOverflow.ellipsis,
          ),
          
          const Spacer(),
          
          // Extensions Chips
          if (project.allowedExtensions.isNotEmpty)
            SizedBox(
              height: 24,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: project.allowedExtensions.length,
                separatorBuilder: (_, __) => const SizedBox(width: 4),
                itemBuilder: (ctx, i) => Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(".${project.allowedExtensions[i]}", style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.black54)),
                ),
              ),
            ),
            
          const SizedBox(height: 16),
          
          // Action Buttons
          if (isSyncing)
            Row(children: const [
              SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
              SizedBox(width: 8),
              Text("Syncing...", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.indigo)),
            ])
          else
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: onViewFiles,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.black87,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text("Open"),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: () => provider.runSync(project.id),
                  icon: const Icon(Icons.sync),
                  tooltip: "Sync Now",
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.black.withOpacity(0.05),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                )
              ],
            )
        ],
      ),
    );
  }

  Widget _buildMenu(BuildContext context, ProjectProvider provider) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_horiz, color: Colors.black54),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      onSelected: (value) {
        if (value == 'edit') _showEditConfigDialog(context);
        if (value == 'delete') {
          // Add a confirmation dialog for safety
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text("Delete Repository?"),
              content: const Text("This will permanently delete the project configuration and indexed data. This action cannot be undone."),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
                  onPressed: () {
                    Navigator.pop(ctx);
                    provider.deleteSyncFromProject(project.id);
                  },
                  child: const Text("Delete"),
                ),
              ],
            ),
          );
        }
      },
      itemBuilder: (c) => [
        const PopupMenuItem(value: 'edit', child: Text('Configuration')),
        // Changed label from 'Unregister' to 'Delete'
        const PopupMenuItem(value: 'delete', child: Text('Delete', style: TextStyle(color: Colors.red))),
      ],
    );
  }
}

// --- REGISTER DIALOG ---
class _RegisterProjectDialog extends StatefulWidget {
  const _RegisterProjectDialog();
  @override
  State<_RegisterProjectDialog> createState() => _RegisterProjectDialogState();
}

class _RegisterProjectDialogState extends State<_RegisterProjectDialog> {
  final _nameCtrl = TextEditingController();
  final _pathCtrl = TextEditingController();
  final _extCtrl = TextEditingController(text: 'py, dart, kt, java, ts, js, md');
  final _pathsCtrl = TextEditingController();
  
  String _activeView = 'ignore';
  String _tempIgnored = 'build/\n.dart_tool/\nnode_modules/\n.git/';
  String _tempIncluded = '';

  @override
  void initState() {
    super.initState();
    _pathsCtrl.text = _tempIgnored;
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        padding: const EdgeInsets.all(24),
        constraints: const BoxConstraints(maxWidth: 500),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("New Code Repository", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 24),
              _buildField("Project Name", _nameCtrl, icon: Icons.label_outline),
              const SizedBox(height: 16),
              _buildField("Folder Path", _pathCtrl, icon: Icons.folder_open),
              const SizedBox(height: 16),
              _buildField("Extensions", _extCtrl, icon: Icons.extension_outlined),
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
                    if (_activeView == 'ignore') _tempIgnored = _pathsCtrl.text;
                    else _tempIncluded = _pathsCtrl.text;
                    
                    _activeView = newSelection.first;
                    _pathsCtrl.text = _activeView == 'ignore' ? _tempIgnored : _tempIncluded;
                  });
                },
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _pathsCtrl,
                decoration: InputDecoration(
                  labelText: _activeView == 'ignore' ? 'Paths to Ignore (one per line)' : 'Paths to Force Include (one per line)',
                  border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
                  alignLabelWithHint: true,
                ),
                maxLines: 4,
              ),
              
              const SizedBox(height: 32),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () async {
                      if (_nameCtrl.text.isEmpty || _pathCtrl.text.isEmpty) return;
                      // Save current view state
                      if (_activeView == 'ignore') _tempIgnored = _pathsCtrl.text;
                      else _tempIncluded = _pathsCtrl.text;

                      try {
                        await Provider.of<ProjectProvider>(context, listen: false).createCodeProjectAndRegisterFolder(
                          projectName: _nameCtrl.text,
                          folderPath: _pathCtrl.text,
                          extensions: _extCtrl.text.split(',').map((e) => e.trim()).toList(),
                          ignoredPaths: _tempIgnored.split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty).toList(),
                          includedPaths: _tempIncluded.split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty).toList(),
                          syncMode: 'hybrid'
                        );
                        if(mounted) Navigator.pop(context);
                      } catch (e) {
                        if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("$e")));
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.black,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12)
                    ),
                    child: const Text("Create"),
                  ),
                ],
              )
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildField(String label, TextEditingController ctrl, {required IconData icon}) {
    return TextField(
      controller: ctrl,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 20),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
    );
  }
}

// --- EDIT DIALOG ---
class _EditConfigDialog extends StatefulWidget {
  final CodeProject project;
  const _EditConfigDialog({required this.project});

  @override
  State<_EditConfigDialog> createState() => _EditConfigDialogState();
}

class _EditConfigDialogState extends State<_EditConfigDialog> {
  late TextEditingController _nameCtrl;
  late TextEditingController _pathCtrl;
  late TextEditingController _extCtrl;
  late TextEditingController _pathsCtrl;
  
  String _activeView = 'ignore';
  late String _tempIgnored;
  late String _tempIncluded;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.project.name);
    _pathCtrl = TextEditingController(text: widget.project.localPath);
    _extCtrl = TextEditingController(text: widget.project.allowedExtensions.join(', '));
    _tempIgnored = widget.project.ignoredPaths.join('\n');
    _tempIncluded = widget.project.includedPaths.join('\n');
    _pathsCtrl = TextEditingController(text: _tempIgnored);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        padding: const EdgeInsets.all(24),
        constraints: const BoxConstraints(maxWidth: 500),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("Edit Configuration", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 24),
              _buildField("Project Name", _nameCtrl, icon: Icons.label_outline),
              const SizedBox(height: 16),
              _buildField("Folder Path", _pathCtrl, icon: Icons.folder_open),
              const SizedBox(height: 16),
              _buildField("Extensions", _extCtrl, icon: Icons.extension_outlined),
              const SizedBox(height: 24),
              
              Text("Path Filters", style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'ignore', label: Text('Ignored Paths')),
                  ButtonSegment(value: 'include', label: Text('Exceptions')),
                ],
                selected: {_activeView},
                onSelectionChanged: (newSelection) {
                  setState(() {
                    if (_activeView == 'ignore') _tempIgnored = _pathsCtrl.text;
                    else _tempIncluded = _pathsCtrl.text;
                    
                    _activeView = newSelection.first;
                    _pathsCtrl.text = _activeView == 'ignore' ? _tempIgnored : _tempIncluded;
                  });
                },
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _pathsCtrl,
                decoration: InputDecoration(
                  labelText: _activeView == 'ignore' ? 'Ignored' : 'Force Include',
                  border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
                  alignLabelWithHint: true,
                ),
                maxLines: 4,
              ),
              
              const SizedBox(height: 32),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () async {
                      // Save current view state
                      if (_activeView == 'ignore') _tempIgnored = _pathsCtrl.text;
                      else _tempIncluded = _pathsCtrl.text;

                      try {
                        await Provider.of<ProjectProvider>(context, listen: false).updateSyncConfig(
                          widget.project.id,
                          extensions: _extCtrl.text.split(',').map((e) => e.trim()).toList(),
                          ignoredPaths: _tempIgnored.split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty).toList(),
                          includedPaths: _tempIncluded.split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty).toList(),
                          syncMode: 'hybrid'
                        );
                        if(mounted) Navigator.pop(context);
                      } catch (e) {
                        if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("$e")));
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.black,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12)
                    ),
                    child: const Text("Save"),
                  ),
                ],
              )
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildField(String label, TextEditingController ctrl, {required IconData icon}) {
    return TextField(
      controller: ctrl,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 20),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
    );
  }
}