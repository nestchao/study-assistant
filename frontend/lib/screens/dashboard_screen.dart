import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
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
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  bool _isGridView = true; // Toggle for List/Grid view

  // Pastel colors for the cards to match reference image
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<ProjectProvider>(context, listen: false)
          .fetchProjects(forceRefresh: true);
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Color _getCardColor(int index) => _cardColors[index % _cardColors.length];

  void _showCreateProjectDialog() {
    final provider = Provider.of<ProjectProvider>(context, listen: false);
    provider.projectNameController.clear();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Create New Project'),
        content: TextField(
          controller: provider.projectNameController,
          autofocus: true,
          decoration: const InputDecoration(hintText: "Project Name"),
          onSubmitted: (value) => _createProject(context, value),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () =>
                _createProject(context, provider.projectNameController.text),
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  void _createProject(BuildContext context, String name) {
    if (name.trim().isNotEmpty) {
      Provider.of<ProjectProvider>(context, listen: false)
          .createProject(name.trim());
      Navigator.of(context).pop();
    }
  }

  void _showRenameProjectDialog(Project project) {
    final provider = Provider.of<ProjectProvider>(context, listen: false);
    provider.projectNameController.text = project.name;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Rename Notebook'),
        content: TextField(
          controller: provider.projectNameController,
          autofocus: true,
          decoration: const InputDecoration(hintText: "Enter new name"),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              if (provider.projectNameController.text.trim().isNotEmpty) {
                provider.renameProject(project.id, provider.projectNameController.text.trim());
                Navigator.pop(context);
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showDeleteConfirmDialog(Project project) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Delete Notebook?'),
        content: Text('Are you sure you want to delete "${project.name}"? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () {
              Provider.of<ProjectProvider>(context, listen: false).deleteProject(project.id);
              Navigator.pop(context);
            },
            child: const Text('Delete'),
          ),
        ],
      ),
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
            const Divider(
                height: 1, color: Color(0xFFE0E0E0)), // Subtle separator
            Expanded(
              child: Consumer<ProjectProvider>(
                builder: (context, provider, child) {
                  final filteredProjects = provider.projects
                      .where((p) => p.name
                          .toLowerCase()
                          .contains(_searchQuery.toLowerCase()))
                      .toList();

                  return RefreshIndicator(
                    onRefresh: () => provider.fetchProjects(forceRefresh: true),
                    child: CustomScrollView(
                      slivers: [
                        const SliverPadding(
                          padding: EdgeInsets.fromLTRB(24, 32, 24, 16),
                          sliver: SliverToBoxAdapter(
                            child: Text(
                              'Recent notebooks',
                              style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w500,
                                  color: Color(0xFF444746)),
                            ),
                          ),
                        ),
                        _isGridView
                            ? _buildProjectGrid(filteredProjects)
                            : _buildProjectList(filteredProjects),
                        const SliverToBoxAdapter(child: SizedBox(height: 100)),
                      ],
                    ),
                  );
                },
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
          // 1. Logo Text
          const Text('NotebookLM',
              style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.5)),

          const SizedBox(width: 40),

          // 2. Search Bar (Flexible)
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
                  hintText: 'Search your notebooks...',
                  prefixIcon: Icon(Icons.search, color: Colors.black54),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
          ),

          const SizedBox(width: 20),

          // 3. Utility Group (Refresh, Sync, Converter)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: const Color(0xFFE0E0E0)),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                IconButton(
                  tooltip: 'Refresh',
                  icon: const Icon(Icons.refresh_rounded,
                      size: 20, color: Colors.black87),
                  onPressed: () =>
                      Provider.of<ProjectProvider>(context, listen: false)
                          .fetchProjects(forceRefresh: true),
                ),
                IconButton(
                  tooltip: 'Code Sync',
                  icon: const Icon(Icons.sync_alt_rounded,
                      size: 20, color: Colors.black87),
                  onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const CodeSyncScreen())),
                ),
                IconButton(
                  tooltip: 'Converter',
                  icon: const Icon(Icons.transform_rounded,
                      size: 20, color: Colors.black87),
                  onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const LocalConverterScreen())),
                ),
              ],
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

          // 5. Create New Button
          ElevatedButton.icon(
            onPressed: _showCreateProjectDialog,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Create new',
                style: TextStyle(fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.black,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProjectGrid(List<Project> projects) {
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 250,
          mainAxisSpacing: 20,
          crossAxisSpacing: 20,
          childAspectRatio: 0.85,
        ),
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            if (index == 0) return _buildCreateNewCard();
            final project = projects[index - 1];
            return _NotebookCard(
              project: project,
              backgroundColor: _getCardColor(index),
              isGrid: true,
              onRename: () => _showRenameProjectDialog(project), // Added
              onDelete: () => _showDeleteConfirmDialog(project), // Added
            );
          },
          childCount: projects.length + 1,
        ),
      ),
    );
  }

  Widget _buildProjectList(List<Project> projects) {
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            if (index == 0) {
              return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _buildCreateNewCard(isList: true),
            );
            }
            final project = projects[index - 1];
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _NotebookCard(
                project: project,
                backgroundColor: _getCardColor(index),
                isGrid: false,
                onRename: () => _showRenameProjectDialog(project), // Added
                onDelete: () => _showDeleteConfirmDialog(project), // Added
              ),
            );
          },
          childCount: projects.length + 1,
        ),
      ),
    );
  }

  Widget _buildCreateNewCard({bool isList = false}) {
    return InkWell(
      onTap: _showCreateProjectDialog,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        // IMPORTANT: Give the list item a fixed height so it doesn't disappear
        height: isList ? 100 : null,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade200),
          borderRadius: BorderRadius.circular(16),
        ),
        child: isList
            ? Row(
                // List Layout
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: const BoxDecoration(
                        color: Color(0xFFF0F4F9), shape: BoxShape.circle),
                    child: const Icon(Icons.add, color: Colors.blueAccent),
                  ),
                  const SizedBox(width: 16),
                  const Text('Create new notebook',
                      style:
                          TextStyle(fontWeight: FontWeight.w500, fontSize: 16)),
                ],
              )
            : Column(
                // Grid Layout
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: const BoxDecoration(
                        color: Color(0xFFF0F4F9), shape: BoxShape.circle),
                    child: const Icon(Icons.add, color: Colors.blueAccent),
                  ),
                  const SizedBox(height: 12),
                  const Text('Create new notebook',
                      style: TextStyle(fontWeight: FontWeight.w500)),
                ],
              ),
      ),
    );
  }
}

class _NotebookCard extends StatelessWidget {
  final Project project;
  final Color backgroundColor;
  final bool isGrid;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  const _NotebookCard({
    required this.project, 
    required this.backgroundColor, 
    required this.isGrid,
    required this.onRename,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        final provider = context.read<ProjectProvider>();
        provider.setCurrentProject(project);
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => WorkspaceScreen(project: project)));
      },
      child: Container(
        height: isGrid ? null : 100, 
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4))
          ],
        ),
        child: isGrid ? _buildGridContent() : _buildListContent(),
      ),
    );
  }

  Widget _buildGridContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.book_outlined, size: 28, color: Colors.black54),
            const Spacer(),
            _buildPopupMenu(), // Replaced icon with Menu
          ],
        ),
        const Spacer(),
        Text(
          project.name,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 8),
        Text(
          '${DateFormat.yMMMd().format(project.createdAt ?? DateTime.now())} • 0 sources',
          style: TextStyle(fontSize: 12, color: Colors.black.withOpacity(0.6)),
        ),
      ],
    );
  }

  Widget _buildListContent() {
    return Row(
      children: [
        const Icon(Icons.book_outlined, size: 32, color: Colors.black54),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                project.name,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(
                '${DateFormat.yMMMd().format(project.createdAt ?? DateTime.now())} • 0 sources',
                style: TextStyle(fontSize: 12, color: Colors.black.withOpacity(0.6)),
              ),
            ],
          ),
        ),
        _buildPopupMenu(), // Replaced icon with Menu
      ],
    );
  }

  // The Options Menu
  Widget _buildPopupMenu() {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert, color: Colors.black54),
      padding: EdgeInsets.zero,
      onSelected: (value) {
        if (value == 'rename') onRename();
        if (value == 'delete') onDelete();
      },
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: 'rename',
          child: Row(
            children: [
              Icon(Icons.edit_outlined, size: 20),
              SizedBox(width: 12),
              Text('Rename'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'delete',
          child: Row(
            children: [
              Icon(Icons.delete_outline, size: 20, color: Colors.red),
              SizedBox(width: 12),
              Text('Delete', style: TextStyle(color: Colors.red)),
            ],
          ),
        ),
      ],
    );
  }
}