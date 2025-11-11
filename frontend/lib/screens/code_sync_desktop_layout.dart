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
  // Panel widths and visibility
  double _fileTreeWidth = 280.0;
  double _fileViewerWidth = 400.0;
  bool _isFileTreeVisible = true;
  bool _isChatVisible = true;
  bool _isFileViewerVisible = true;
  
  final double _minPanelWidth = 200.0;
  final double _collapseThreshold = 50.0;
  final double _minChatPanelWidth = 300.0;

  void _togglePanelVisibility(String panel) {
    setState(() {
      if (panel == 'chat' && !_isChatVisible) {
        _isChatVisible = true;
        final double screenWidth = MediaQuery.of(context).size.width;
        const double targetChatWidth = 400.0;
        final currentSidePanelsWidth = 
            (_isFileTreeVisible ? _fileTreeWidth : 0) + 
            (_isFileViewerVisible ? _fileViewerWidth : 0);
        final availableSpaceForSidePanels = screenWidth - targetChatWidth - 16;
        
        if (currentSidePanelsWidth > availableSpaceForSidePanels) {
          final overflow = currentSidePanelsWidth - availableSpaceForSidePanels;
          if (_isFileTreeVisible && _isFileViewerVisible) {
            double fileTreeProportion = _fileTreeWidth / currentSidePanelsWidth;
            _fileTreeWidth -= overflow * fileTreeProportion;
            _fileViewerWidth -= overflow * (1 - fileTreeProportion);
          } else if (_isFileTreeVisible) {
            _fileTreeWidth -= overflow;
          } else if (_isFileViewerVisible) {
            _fileViewerWidth -= overflow;
          }
        }
        return;
      }

      int visibleCount = 
          (_isFileTreeVisible ? 1 : 0) + 
          (_isChatVisible ? 1 : 0) + 
          (_isFileViewerVisible ? 1 : 0);

      if (visibleCount > 1) {
        if (panel == 'fileTree') _isFileTreeVisible = !_isFileTreeVisible;
        if (panel == 'chat') _isChatVisible = !_isChatVisible;
        if (panel == 'fileViewer') _isFileViewerVisible = !_isFileViewerVisible;
      }

      if (panel == 'fileTree' && _isFileTreeVisible) _fileTreeWidth = 280.0;
      if (panel == 'fileViewer' && _isFileViewerVisible) _fileViewerWidth = 400.0;
    });
  }

  Widget _buildVisibilityToggleButton({
    required String tooltip,
    required IconData icon,
    required Color color,
    required bool isVisible,
    required VoidCallback onPressed,
    required bool isDisabled,
  }) {
    return IconButton(
      tooltip: tooltip,
      icon: Icon(icon),
      style: IconButton.styleFrom(
        foregroundColor: color,
        backgroundColor: isVisible ? color.withOpacity(0.20) : Colors.transparent,
        disabledForegroundColor: color.withOpacity(0.3),
      ),
      onPressed: isDisabled ? null : onPressed,
    );
  }

  Widget _buildResizer({required GestureDragUpdateCallback onDrag}) {
    return GestureDetector(
      onHorizontalDragUpdate: onDrag,
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeLeftRight,
        child: Container(
          width: 8,
          color: Colors.grey[300],
          child: Center(
            child: Container(
              width: 2,
              color: Colors.grey[400],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final int visibleCount = 
        (_isFileTreeVisible ? 1 : 0) + 
        (_isChatVisible ? 1 : 0) + 
        (_isFileViewerVisible ? 1 : 0);
    final double screenWidth = MediaQuery.of(context).size.width;

    return Column(
      children: [
        // Panel toggle toolbar
        Container(
          height: 50,
          color: Colors.grey[100],
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              const Text(
                "View Panels",
                style: TextStyle(color: Colors.black54, fontSize: 16),
              ),
              const Spacer(),
              _buildVisibilityToggleButton(
                tooltip: 'Toggle File Tree',
                icon: Icons.folder_outlined,
                color: Colors.blue.shade400,
                isVisible: _isFileTreeVisible,
                onPressed: () => _togglePanelVisibility('fileTree'),
                isDisabled: _isFileTreeVisible && visibleCount == 1,
              ),
              _buildVisibilityToggleButton(
                tooltip: 'Toggle AI Chat',
                icon: Icons.smart_toy,
                color: Colors.purple.shade400,
                isVisible: _isChatVisible,
                onPressed: () => _togglePanelVisibility('chat'),
                isDisabled: _isChatVisible && visibleCount == 1,
              ),
              _buildVisibilityToggleButton(
                tooltip: 'Toggle File Viewer',
                icon: Icons.code,
                color: Colors.green.shade400,
                isVisible: _isFileViewerVisible,
                onPressed: () => _togglePanelVisibility('fileViewer'),
                isDisabled: _isFileViewerVisible && visibleCount == 1,
              ),
            ],
          ),
        ),
        // Main content
        Expanded(
          child: Row(
            children: [
              // File Tree Panel
              if (_isFileTreeVisible)
                _isChatVisible
                    ? SizedBox(
                        width: _fileTreeWidth,
                        child: const FileTreePanel(),
                      )
                    : Expanded(
                        flex: _fileTreeWidth.round(),
                        child: const FileTreePanel(),
                      ),

              // Resizer between File Tree and Chat
              if (_isFileTreeVisible && _isChatVisible)
                _buildResizer(
                  onDrag: (details) {
                    setState(() {
                      _fileTreeWidth = max(_collapseThreshold, _fileTreeWidth + details.delta.dx);
                      if (_fileTreeWidth < _minPanelWidth) {
                        _isFileTreeVisible = false;
                      }
                      final chatWidth = screenWidth - 
                          _fileTreeWidth - 
                          (_isFileViewerVisible ? _fileViewerWidth + 8 : 0) - 8;
                      if (chatWidth < _minChatPanelWidth && visibleCount > 1) {
                        _isChatVisible = false;
                      }
                    });
                  },
                ),

              // AI Chat Panel
              if (_isChatVisible) 
                const Expanded(child: CodeChatPanel()),

              // Resizer between Chat and File Viewer
              if (_isChatVisible && _isFileViewerVisible)
                _buildResizer(
                  onDrag: (details) {
                    setState(() {
                      _fileViewerWidth = max(_collapseThreshold, _fileViewerWidth - details.delta.dx);
                      if (_fileViewerWidth < _minPanelWidth) {
                        _isFileViewerVisible = false;
                      }
                      final chatWidth = screenWidth - 
                          _fileViewerWidth - 
                          (_isFileTreeVisible ? _fileTreeWidth + 8 : 0) - 8;
                      if (chatWidth < _minChatPanelWidth && visibleCount > 1) {
                        _isChatVisible = false;
                      }
                    });
                  },
                ),

              // File Viewer Panel
              if (_isFileViewerVisible)
                _isChatVisible
                    ? SizedBox(
                        width: _fileViewerWidth,
                        child: const FileViewerPanel(),
                      )
                    : Expanded(
                        flex: _fileViewerWidth.round(),
                        child: const FileViewerPanel(),
                      ),
            ],
          ),
        ),
      ],
    );
  }
}