// frontend/lib/models/project.dart

import 'package:cloud_firestore/cloud_firestore.dart';

class Project {
  final String id;
  final String name;
  final DateTime? createdAt;

  Project({required this.id, required this.name, this.createdAt});

  /// Converts a Project object into a Map.
  /// This is used for saving data to the local cache (SharedPreferences).
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      // Convert DateTime to a standardized string format (ISO 8601) for JSON compatibility.
      // If createdAt is null, this will correctly store null in the map.
      'created_at': createdAt?.toIso8601String(),
    };
  }

  /// Extracts a Project object from a Map object.
  /// This handles data coming from either Firestore (as a Timestamp)
  /// or from the local JSON cache (as an ISO 8601 String).
  factory Project.fromMap(Map<String, dynamic> map) {
    var createdAtValue = map['created_at'] ?? map['timestamp']; // Also check for 'timestamp' for backward compatibility
    
    DateTime? parsedDate;
    if (createdAtValue is Timestamp) {
      // Data is from Firestore
      parsedDate = createdAtValue.toDate();
    } else if (createdAtValue is String) {
      // Data is from local cache (JSON)
      parsedDate = DateTime.tryParse(createdAtValue);
    }
    // If createdAtValue is null or another type, parsedDate will remain null.

    return Project(
      id: map['id'] ?? '',
      name: map['name'] ?? 'No Name',
      createdAt: parsedDate,
    );
  }
}