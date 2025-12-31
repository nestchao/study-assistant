import 'package:flutter/material.dart';
import 'package:study_assistance/models/dependency_graph.dart';
import 'dart:math';

class DependencyCassette extends StatelessWidget {
  final DependencyGraph graph;
  final VoidCallback onClose;

  const DependencyCassette({super.key, required this.graph, required this.onClose});

  @override
  Widget build(BuildContext context) {
    // Find root (fallback to first if explicit root missing)
    final root = graph.nodes.firstWhere(
      (n) => n.type == 'root', 
      orElse: () => graph.nodes.isNotEmpty ? graph.nodes.first : GraphNode(id: 'err', label: 'Error', type: 'root')
    );
    
    final deps = graph.nodes.where((n) => n.id != root.id).toList();

    return Container(
      height: 220,
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B), // Slate 800
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.blue.withOpacity(0.3), width: 1),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 10, offset: const Offset(0, 4))
        ],
      ),
      child: Stack(
        children: [
          // 1. Background Grid
          Positioned.fill(
            child: CustomPaint(painter: _GridPainter()),
          ),

          // 2. The Graph Visualization
          Positioned.fill(
            child: CustomPaint(painter: _GraphPainter(root: root, neighbors: deps)),
          ),

          // 3. Labels
          _buildNodeWidget(context, root, true),
          ...List.generate(deps.length, (index) {
            return _buildNeighborWidget(context, deps[index], index, deps.length);
          }),

          // 4. Header
          Positioned(
            top: 12, left: 16,
            child: Row(
              children: [
                Icon(Icons.hub, color: Colors.blue.shade400, size: 16),
                const SizedBox(width: 8),
                Text("AUTONOMOUS CONTEXT MAP", style: TextStyle(color: Colors.blue.shade200, fontSize: 10, letterSpacing: 1.5, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          
          // Close Button
          Positioned(
            top: 8, right: 8,
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white54, size: 18),
              onPressed: onClose,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNodeWidget(BuildContext context, GraphNode node, bool isRoot) {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isRoot ? Colors.indigo.shade600 : Colors.grey.shade800,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isRoot ? Colors.white : Colors.grey.shade600, width: 2),
          boxShadow: [BoxShadow(color: isRoot ? Colors.indigo.withOpacity(0.5) : Colors.black26, blurRadius: 12)]
        ),
        child: Text(
          _shorten(node.label),
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
        ),
      ),
    );
  }

  Widget _buildNeighborWidget(BuildContext context, GraphNode node, int index, int total) {
    final double angle = (2 * pi * index) / total;
    return Align(
      alignment: Alignment(cos(angle) * 0.75, sin(angle) * 0.75), 
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFF0F172A),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.cyan.withOpacity(0.5)),
        ),
        child: Text(
          _shorten(node.label),
          style: TextStyle(color: Colors.cyan.shade100, fontSize: 10),
        ),
      ),
    );
  }

  String _shorten(String s) {
    final parts = s.split('/');
    String name = parts.last;
    if (name.length > 20) return "${name.substring(0, 17)}...";
    return name;
  }
}

class _GraphPainter extends CustomPainter {
  final GraphNode root;
  final List<GraphNode> neighbors;
  _GraphPainter({required this.root, required this.neighbors});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final paint = Paint()..color = Colors.blue.withOpacity(0.3)..strokeWidth = 1.5..style = PaintingStyle.stroke;
    final double w = size.width / 2;
    final double h = size.height / 2;

    for (int i = 0; i < neighbors.length; i++) {
      final double angle = (2 * pi * i) / neighbors.length;
      final target = Offset(center.dx + (cos(angle) * w * 0.75), center.dy + (sin(angle) * h * 0.75));
      canvas.drawLine(center, target, paint);
    }
  }
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.white.withOpacity(0.03)..strokeWidth = 1;
    double step = 20;
    for(double x=0; x<size.width; x+=step) {
      canvas.drawLine(Offset(x,0), Offset(x, size.height), paint);
    }
    for(double y=0; y<size.height; y+=step) {
      canvas.drawLine(Offset(0,y), Offset(size.width, y), paint);
    }
  }
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}