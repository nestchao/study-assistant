// e.g., in lib/models/sync_config.dart

// Represents a registered folder from the `sync_configs` collection
class SyncConfig {
  final String id;
  final String projectId;
  final String localPath;
  final List<String> allowedExtensions;
  final bool isActive;
  final String status;
  // Timestamps can be complex, so we'll handle them as strings for now
  final dynamic lastSynced;

  SyncConfig({
    required this.id,
    required this.projectId,
    required this.localPath,
    required this.allowedExtensions,
    required this.isActive,
    required this.status,
    this.lastSynced,
  });

  factory SyncConfig.fromMap(Map<String, dynamic> map) {
    return SyncConfig(
      id: map['id'],
      projectId: map['project_id'],
      localPath: map['local_path'],
      allowedExtensions: List<String>.from(map['allowed_extensions'] ?? []),
      isActive: map['is_active'] ?? false,
      status: map['status'] ?? 'idle',
      lastSynced: map['last_synced'], // Keep it dynamic for now
    );
  }
}