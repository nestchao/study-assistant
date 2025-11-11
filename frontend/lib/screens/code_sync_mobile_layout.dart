// lib/screens/code_sync_mobile_layout.dart
import 'package:flutter/material.dart';
import 'package:study_assistance/screens/code_sync_panels.dart';

class CodeSyncMobileLayout extends StatefulWidget {
  const CodeSyncMobileLayout({super.key});

  @override
  State<CodeSyncMobileLayout> createState() => _CodeSyncMobileLayoutState();
}

class _CodeSyncMobileLayoutState extends State<CodeSyncMobileLayout> 
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          color: Colors.grey[100],
          child: TabBar(
            controller: _tabController,
            labelColor: Theme.of(context).primaryColor,
            unselectedLabelColor: Colors.grey[600],
            indicatorColor: Theme.of(context).primaryColor,
            tabs: const [
              Tab(
                icon: Icon(Icons.folder_outlined),
                text: 'Files',
              ),
              Tab(
                icon: Icon(Icons.smart_toy),
                text: 'AI Chat',
              ),
              Tab(
                icon: Icon(Icons.code),
                text: 'Viewer',
              ),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: const [
              FileTreePanel(),
              CodeChatPanel(),
              FileViewerPanel(),
            ],
          ),
        ),
      ],
    );
  }
}