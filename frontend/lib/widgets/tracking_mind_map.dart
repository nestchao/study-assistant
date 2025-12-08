import 'package:flutter/material.dart';

// 1. The Data Model
class MindMapNode {
  final String id;
  final String name;
  final List<MindMapNode> children;

  MindMapNode({
    required this.id,
    required this.name,
    this.children = const [],
  });
}

// 2. The Layout Model (Internal use)
class LayoutNode {
  final MindMapNode data;
  final double x;
  final double y;
  final int depth;
  final bool isExpanded;
  final bool isTracked; // True if parent is expanded
  final bool hasChildren;

  LayoutNode({
    required this.data,
    required this.x,
    required this.y,
    required this.depth,
    required this.isExpanded,
    required this.isTracked,
    required this.hasChildren,
  });
}

class TrackingMindMap extends StatefulWidget {
  final MindMapNode rootNode;
  final Function(Set<String>) onTrackingChanged;
  final Set<String>? initialSelectedIds; 

  const TrackingMindMap({
    super.key,
    required this.rootNode,
    required this.onTrackingChanged,
    this.initialSelectedIds,
  });

  @override
  State<TrackingMindMap> createState() => _TrackingMindMapState();
}

class _TrackingMindMapState extends State<TrackingMindMap> {
  late Set<String> _expandedNodes;

  @override
  void initState() {
    super.initState();
    // Initialize with passed IDs OR just the root
    if (widget.initialSelectedIds != null && widget.initialSelectedIds!.isNotEmpty) {
      _expandedNodes = Set.from(widget.initialSelectedIds!);
      _expandedNodes.add(widget.rootNode.id); // Ensure root is always open
      
      // OPTIONAL: Auto-expand parents. 
      // Since we only pass Leaf IDs (candidates), the tree might look collapsed.
      // You might need logic here to expand parent folders of selected items.
    } else {
      _expandedNodes = {widget.rootNode.id};
    }
  }

  // Layout Constants
  final double nodeWidth = 220;
  final double nodeHeight = 50;
  final double levelSpacing = 260; 
  final double nodeSpacing = 70;

  void _toggleNode(String nodeId) {
    setState(() {
      if (_expandedNodes.contains(nodeId)) {
        _expandedNodes.remove(nodeId);
      } else {
        _expandedNodes.add(nodeId);
      }
    });
    // Notify parent (ProjectProvider) about which paths are active
    widget.onTrackingChanged(_expandedNodes);
  }

  List<LayoutNode> _calculateLayout() {
    List<LayoutNode> results = [];
    double currentY = 0;

    void traverse(MindMapNode node, int depth, bool parentExpanded) {
      final isExpanded = _expandedNodes.contains(node.id);
      final hasChildren = node.children.isNotEmpty;
      
      // TRACKING LOGIC:
      // A node is "Tracked" (Solid) if its parent is expanded.
      // If parent is collapsed, this node wouldn't even be visited by this recursion
      // usually, but here we want to render it as "Transparent" if it's the child of a collapsed node?
      // Actually, standard tree view hides children of collapsed nodes.
      // Based on your request: "half-transparent node mean the ai will not track this and its subnode"
      // We will treat "Collapsed" = "Stop Tracking Here".
      
      final layoutNode = LayoutNode(
        data: node,
        x: depth * levelSpacing + 50,
        y: currentY,
        depth: depth,
        isExpanded: isExpanded,
        isTracked: parentExpanded, 
        hasChildren: hasChildren,
      );

      results.add(layoutNode);

      if (isExpanded && hasChildren) {
        for (var child in node.children) {
          traverse(child, depth + 1, true); // Child is tracked because I am expanded
        }
      } else {
        // If I am collapsed, my children are NOT generated in layout, 
        // effectively cutting off the AI tracking path.
        currentY += nodeSpacing;
      }
    }

    traverse(widget.rootNode, 0, true);
    return results;
  }

  @override
  Widget build(BuildContext context) {
    final layoutNodes = _calculateLayout();
    
    double maxWidth = 0;
    double maxHeight = 0;
    for (var node in layoutNodes) {
      if (node.x > maxWidth) maxWidth = node.x;
      if (node.y > maxHeight) maxHeight = node.y;
    }
    maxWidth += nodeWidth + 100;
    maxHeight += nodeSpacing + 100;

    return Container(
      color: const Color(0xFFF8FAFC), 
      child: InteractiveViewer(
        boundaryMargin: const EdgeInsets.all(500), // Large margin for panning
        minScale: 0.1,
        maxScale: 3.0,
        constrained: false,
        child: SizedBox(
          width: maxWidth,
          height: maxHeight,
          child: Stack(
            children: [
              CustomPaint(
                size: Size(maxWidth, maxHeight),
                painter: _MindMapPainter(
                  nodes: layoutNodes,
                  nodeWidth: nodeWidth,
                  nodeHeight: nodeHeight,
                ),
              ),
              ...layoutNodes.map((node) => _buildNodeWidget(node)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNodeWidget(LayoutNode layoutNode) {
    final colors = _getNodeColors(layoutNode.depth);
    
    // Opacity Logic: If user collapsed this node, it's opaque (active end point).
    // If it is inside a collapsed parent, it wouldn't be rendered.
    // The visualization implies: Visible = Tracked.
    // To achieve the "Half Transparent" effect for "Not Tracked", 
    // we can change the visual style if it is NOT expanded but HAS children.
    
    final bool isPathActive = layoutNode.isExpanded; 

    return Positioned(
      left: layoutNode.x,
      top: layoutNode.y,
      child: Opacity(
        opacity: 1.0, 
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            InkWell(
              onTap: layoutNode.hasChildren ? () => _toggleNode(layoutNode.data.id) : null,
              child: Container(
                width: nodeWidth,
                height: nodeHeight,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: isPathActive ? colors['bg'] : Colors.grey[200], // Grey if path stops here
                  border: Border.all(
                    color: isPathActive ? colors['border']! : Colors.grey[400]!, 
                    width: 2
                  ),
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    )
                  ],
                ),
                alignment: Alignment.center,
                child: Text(
                  layoutNode.data.name,
                  style: TextStyle(
                    color: isPathActive ? colors['text'] : Colors.grey[600],
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            
            if (layoutNode.hasChildren)
              Transform.translate(
                offset: const Offset(-12, 0),
                child: InkWell(
                  onTap: () => _toggleNode(layoutNode.data.id),
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isPathActive ? colors['border']! : Colors.grey[400]!, 
                        width: 2
                      ),
                    ),
                    child: Icon(
                      layoutNode.isExpanded 
                          ? Icons.remove // Expanded (Minus)
                          : Icons.add,   // Collapsed (Plus)
                      size: 16,
                      color: isPathActive ? colors['text'] : Colors.grey[600],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Map<String, Color> _getNodeColors(int depth) {
    const styles = [
      {'bg': Color(0xFFE0E7FF), 'border': Color(0xFF818CF8), 'text': Color(0xFF4338CA)}, // Purple
      {'bg': Color(0xFFDBEAFE), 'border': Color(0xFF60A5FA), 'text': Color(0xFF1E40AF)}, // Blue
      {'bg': Color(0xFFD1FAE5), 'border': Color(0xFF34D399), 'text': Color(0xFF047857)}, // Green
      {'bg': Color(0xFFFEF3C7), 'border': Color(0xFFFBBF24), 'text': Color(0xFFB45309)}, // Amber
    ];
    return styles[depth % styles.length];
  }
}

class _MindMapPainter extends CustomPainter {
  final List<LayoutNode> nodes;
  final double nodeWidth;
  final double nodeHeight;

  _MindMapPainter({required this.nodes, required this.nodeWidth, required this.nodeHeight});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFCBD5E1) // Slate-300
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    for (var parent in nodes) {
      if (!parent.isExpanded || !parent.hasChildren) continue;

      for (var childData in parent.data.children) {
        try {
          final child = nodes.firstWhere((n) => n.data.id == childData.id);
          
          final startX = parent.x + nodeWidth; 
          final startY = parent.y + (nodeHeight / 2);
          final endX = child.x;
          final endY = child.y + (nodeHeight / 2);

          final path = Path();
          path.moveTo(startX, startY);
          final midX = startX + (endX - startX) / 2;
          path.cubicTo(midX, startY, midX, endY, endX, endY);

          canvas.drawPath(path, paint);
        } catch (_) {}
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}