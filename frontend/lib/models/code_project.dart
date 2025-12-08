// frontend/lib/models/code_project.dart

class CodeProject {
  final String id;
  final String name;
  
  // Sync Configuration Properties
  final String? localPath;
  final List<String> allowedExtensions;
  final List<String> ignoredPaths; 
  final List<String> includedPaths;
  final String syncMode; 
  final bool isActive;
  final String status;
  final dynamic lastSynced;

  CodeProject({
    required this.id,
    required this.name,
    this.localPath,
    required this.allowedExtensions,
    required this.ignoredPaths, 
    required this.includedPaths,
    required this.syncMode,
    required this.isActive,
    required this.status,
    this.lastSynced,
  });

  factory CodeProject.fromMap(Map<String, dynamic> map) {
    return CodeProject(
      id: map['id'],
      name: map['name'] ?? 'Untitled Code Project',
      localPath: map['local_path'],
      allowedExtensions: List<String>.from(map['allowed_extensions'] ?? []),
      ignoredPaths: List<String>.from(map['ignored_paths'] ?? []),
      includedPaths: List<String>.from(map['included_paths'] ?? []), // New
      syncMode: map['sync_mode'] ?? 'ignore', // New
      isActive: map['is_active'] ?? false,
      status: map['status'] ?? 'idle',
      lastSynced: map['last_synced'],
    );
  }
}