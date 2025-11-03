import 'package:cloud_firestore/cloud_firestore.dart';

class Project {
  final String id;
  final String name;
  final DateTime? createdAt;

  Project({required this.id, required this.name, this.createdAt});

  factory Project.fromMap(Map<String, dynamic> map) {
    var createdAtValue = map['created_at'];

    DateTime? parsedDate;
    if (createdAtValue is Timestamp) {
      parsedDate = createdAtValue.toDate();
    } else if (createdAtValue is String) {
      parsedDate = DateTime.tryParse(createdAtValue);
    }

    return Project(
      id: map['id'] ?? '',
      name: map['name'] ?? 'No Name',
      createdAt: parsedDate,
    );
  }
}