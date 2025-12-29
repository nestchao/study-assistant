// lib/screens/code_sync_desktop_layout.dart
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:study_assistance/screens/code_sync_panels.dart';

class CodeSyncDesktopLayout extends StatefulWidget {
  const CodeSyncDesktopLayout({super.key});
  @override
  State<CodeSyncDesktopLayout> createState() => _CodeSyncDesktopLayoutState();
}

class _CodeSyncDesktopLayoutState extends State<CodeSyncDesktopLayout> {
  double _fileTreeWidth = 280.0;
  double _fileViewerWidth = 400.0;
  bool _isFileTreeVisible = true;
  bool _isChatVisible = true;
  bool _isFileViewerVisible = true;
  
  final double _minPanelWidth = 200.0;

  void _togglePanelVisibility(String panel) {
    setState(() {
      if (panel == 'tree') _isFileTreeVisible = !_isFileTreeVisible;
      if (panel == 'chat') _isChatVisible = !_isChatVisible;
      if (panel == 'viewer') _isFileViewerVisible = !_isFileViewerVisible;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Clean Toolbar
        Container(
          height: 48,
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(bottom: BorderSide(color: Color(0xFFE0E0E0))),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              const Text("Panels: ", style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold)),
              const SizedBox(width: 8),
              _ViewToggleBtn(
                label: "Files", icon: Icons.folder_open, 
                isActive: _isFileTreeVisible, 
                onTap: () => _togglePanelVisibility('tree'),
              ),
              const SizedBox(width: 8),
              _ViewToggleBtn(
                label: "Chat", icon: Icons.auto_awesome, 
                isActive: _isChatVisible, 
                onTap: () => _togglePanelVisibility('chat'),
              ),
              const SizedBox(width: 8),
              _ViewToggleBtn(
                label: "Code", icon: Icons.code, 
                isActive: _isFileViewerVisible, 
                onTap: () => _togglePanelVisibility('viewer'),
              ),
            ],
          ),
        ),
        
        Expanded(
          child: Row(
            children: [
              if (_isFileTreeVisible) SizedBox(width: _fileTreeWidth, child: const FileTreePanel()),
              if (_isFileTreeVisible) _buildResizer((d) => setState(() => _fileTreeWidth = max(_minPanelWidth, _fileTreeWidth + d.delta.dx))),
              
              if (_isChatVisible) const Expanded(child: CodeChatPanel()),
              
              if (_isFileViewerVisible && _isChatVisible) _buildResizer((d) => setState(() => _fileViewerWidth = max(_minPanelWidth, _fileViewerWidth - d.delta.dx))),
              if (_isFileViewerVisible) SizedBox(width: _fileViewerWidth, child: const FileViewerPanel()),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildResizer(GestureDragUpdateCallback onDrag) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeLeftRight,
      child: GestureDetector(
        onHorizontalDragUpdate: onDrag,
        child: Container(width: 1, color: const Color(0xFFE0E0E0)),
      ),
    );
  }
}

class _ViewToggleBtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isActive;
  final VoidCallback onTap;

  const _ViewToggleBtn({required this.label, required this.icon, required this.isActive, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isActive ? Colors.grey.shade100 : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: isActive ? Colors.grey.shade300 : Colors.transparent),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: isActive ? Colors.black87 : Colors.grey),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(fontSize: 12, color: isActive ? Colors.black87 : Colors.grey, fontWeight: isActive ? FontWeight.w600 : FontWeight.normal)),
          ],
        ),
      ),
    );
  }
}