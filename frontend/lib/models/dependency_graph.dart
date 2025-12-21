class GraphNode {
  final String id;
  final String label;
  final String type; // 'root', 'dependency'

  GraphNode({required this.id, required this.label, required this.type});

  factory GraphNode.fromJson(Map<String, dynamic> json) {
    return GraphNode(
      id: json['id'],
      label: json['label'],
      type: json['type'],
    );
  }
}

class GraphEdge {
  final String source;
  final String target;

  GraphEdge({required this.source, required this.target});

  factory GraphEdge.fromJson(Map<String, dynamic> json) {
    return GraphEdge(
      source: json['source'],
      target: json['target'],
    );
  }
}

class DependencyGraph {
  final List<GraphNode> nodes;
  final List<GraphEdge> edges;

  DependencyGraph({required this.nodes, required this.edges});

  factory DependencyGraph.fromJson(Map<String, dynamic> json) {
    return DependencyGraph(
      nodes: (json['nodes'] as List).map((e) => GraphNode.fromJson(e)).toList(),
      edges: (json['edges'] as List).map((e) => GraphEdge.fromJson(e)).toList(),
    );
  }
}