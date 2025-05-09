import 'package:cloud_firestore/cloud_firestore.dart';

class Ticket {
  final String id;
  final String title;
  final String description;
  final String status;
  final String priority;
  final String? platform;
  final String? platformName; // Add platformName
  final String? equipment;
  final String? equipmentName; // Add equipmentName
  final String createdBy;
  final String createdByName;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? assignedTo;
  final bool reassigned;

  Ticket({
    required this.id,
    required this.title,
    required this.description,
    required this.status,
    required this.priority,
    this.platform,
    this.platformName,
    this.equipment,
    this.equipmentName,
    required this.createdBy,
    required this.createdByName,
    required this.createdAt,
    required this.updatedAt,
    this.assignedTo,
    this.reassigned = false,
  });

  factory Ticket.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Ticket(
      id: doc.id,
      title: data['title'] ?? '',
      description: data['description'] ?? '',
      status: data['status'] ?? 'open',
      priority: data['priority'] ?? 'low',
      platform: data['platform'],
      platformName: data['platformName'], // Parse platformName
      equipment: data['equipment'],
      equipmentName: data['equipmentName'], // Parse equipmentName
      createdBy: data['createdBy'] ?? '',
      createdByName: data['createdByName'] ?? 'Unknown',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      assignedTo: data['assignedTo'],
      reassigned: data['reassigned'] ?? false,
    );
  }

  Map<String, dynamic> toFirestore() {
    final data = {
      'title': title,
      'description': description,
      'status': status,
      'priority': priority,
      'platform': platform,
      'platformName': platformName ?? platform, // Use platform if platformName is null
      'createdBy': createdBy,
      'createdByName': createdByName,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
      'assignedTo': assignedTo,
      'reassigned': reassigned,
    };
    // Only include equipment and equipmentName if equipment is not null
    if (equipment != null) {
      data['equipment'] = equipment;
      data['equipmentName'] = equipmentName ?? equipment; // Use equipment if equipmentName is null
    }
    return data;
  }
}